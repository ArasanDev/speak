// SpeakCore/Engine/CaptureSession.swift
//
// The orchestration actor (architecture.md §6, §7.1). Owns the state machine
// for one dictation, drives the STT engine, runs the optional cleanup pass on
// stop, and returns a `TranscriptionResult`. Paste (P6) and hotkey (P5) live
// in their own modules and consume this actor's API.
//
// State machine (architecture §7.1):
//
//     idle ──start()──► listening ──stop()──► processing ─► done
//       ▲                  │                     │
//       │                  │ cancel              │ cleanup failure
//       └──────────────────┴─────────────────────┴──► error(SpeakError)
//
// Concurrency: `CaptureSession` is an `actor` so all session mutation is
// serialized. The STT stream is consumed by a background `Task`; each chunk
// is `await`ed into the actor before the next is consumed, so `latestChunk`
// is consistent at stop time. The partial stream is exposed for the overlay
// (P4) and the live status icon (P8).
//
// Cleanup contract (architecture §10a.1, roadmap P3.5 done-when):
//   • cleaner == nil (cleanup off)        → cleanedText = nil, engineId = STT id
//   • cleaner.isAvailable == false        → cleanedText = nil, NO error (fallback)
//   • cleaner.clean() throws              → throws SpeakError.llmCleanupFailed
//                                            (genuine API failure only)
//
// Signatures are verbatim from `docs/architecture.md` §6.

import Foundation
import os

public actor CaptureSession {

    public enum State: Sendable {
        case idle
        case listening
        case processing
        case done
        case error(SpeakError)
    }

    // MARK: - Configuration (immutable post-init)

    public nonisolated let locale: Locale
    public nonisolated let cleanupMode: CleanupMode

    private let transcriber: any Transcribing
    private let cleaner: (any LLMCleaning)?
    private let inserter: (any TextInserting)?
    /// Optional snippet expander applied to the raw transcript BEFORE cleanup.
    /// `nil` (default) means no expansion — behavior is identical to pre-Wave-B.
    private let expander: (any SnippetExpanding)?

    // MARK: - Mutable session state (actor-isolated)

    private var state: State = .idle
    private var streamTask: Task<Void, Never>?
    private var latestChunk: TranscriptChunk?
    /// Accumulates text from finalized (isFinal == true) chunks.
    ///
    /// SpeechAnalyzer with `.progressiveTranscription` emits one isFinal segment
    /// per speech window — each contains only that window's text, NOT the whole
    /// utterance. Without accumulation, only the last window's text would be
    /// pasted. finalizedText appends each isFinal chunk's text so the full
    /// multi-segment transcript is assembled here, matching what the user saw
    /// accumulate in the HUD across volatile chunks. [decision: truncation fix]
    ///
    /// Separator " " matches the convention in SpeechTranscriberTests.swift:239.
    /// Whether Apple's on-device model already includes leading whitespace per
    /// segment is [unverified] — if it does, double-spaces may appear; this can
    /// be revisited with a live multi-segment test corpus.
    private var finalizedText: String = ""
    private var sessionStartTime: Date?
    private var partialsContinuation: AsyncStream<TranscriptChunk>.Continuation?

    // MARK: - Init

    /// Create a new CaptureSession for one dictation.
    ///
    /// - Parameters:
    ///   - transcriber: The STT engine. Owned for the lifetime of the session.
    ///   - cleaner: `nil` when AI cleanup is disabled (per-user setting).
    ///     Non-nil enables the cleanup pass on stop.
    ///   - inserter: `nil` (default) leaves paste as a caller responsibility
    ///     (pre-P6 behaviour, all existing call-sites unchanged). Non-nil wires
    ///     paste directly into the session: `insert(cleanedText ?? rawText)` is
    ///     called just before the session settles to `.done`. If `insert` throws,
    ///     the session transitions to `.error` (paste failure = delivery failure).
    ///   - locale: Locale passed to the transcriber. Default: en-US.
    ///   - cleanupMode: `CleanupMode` passed to the cleaner. Default: `.punctuation`.
    ///   - expander: Optional snippet expander applied to the raw transcript before
    ///     cleanup. `nil` (default) = no expansion.
    public init(transcriber: any Transcribing,
                cleaner: (any LLMCleaning)? = nil,
                inserter: (any TextInserting)? = nil,
                locale: Locale = Locale(identifier: "en-US"),
                cleanupMode: CleanupMode = .punctuation,
                expander: (any SnippetExpanding)? = nil) {
        self.transcriber = transcriber
        self.cleaner = cleaner
        self.inserter = inserter
        self.locale = locale
        self.cleanupMode = cleanupMode
        self.expander = expander
    }

    // MARK: - State observation

    /// Current state of the session.
    public var currentState: State {
        get async { state }
    }

    /// `true` once the session has reached a terminal state (`.done` or `.error`).
    public var isTerminal: Bool {
        get async {
            switch state {
            case .done, .error: return true
            default: return false
            }
        }
    }

    // MARK: - Partials stream (consumed by the overlay — P4)

    /// Stream of partial transcript chunks emitted by the STT engine.
    /// Consumers (the live overlay, the menubar icon) attach to this to
    /// receive live updates. The stream finishes when the session ends
    /// (done, error, or cancel).
    ///
    /// Calling this more than once replaces the prior consumer — only the
    /// most recent caller receives subsequent chunks. This is intentional:
    /// the session is single-consumer per dictation.
    public func partials() -> AsyncStream<TranscriptChunk> {
        let (stream, continuation) = AsyncStream<TranscriptChunk>.makeStream()
        // [Engine-L3] Replacing the prior continuation without calling finish() first
        // is safe: AsyncStream.Continuation auto-finishes its stream on deinit, so the
        // old consumer gets .finished. Single-consumer contract means the prior consumer
        // is already gone when this is called again (new session, new HUD consumer).
        self.partialsContinuation = continuation
        return stream
    }

    // MARK: - W2.1: Level stream (consumed by the overlay HUD waveform)

    /// The `AudioCapture` instance providing both the PCM buffer stream (to the
    /// transcriber) and the live level stream (to the HUD). Stored so we can
    /// call `startLevelStream()` after `start()` initiates capture.
    ///
    /// Injected via `levels()` — the transcriber owns the capture object but the
    /// level stream is a parallel read-only side channel. We hold a weak reference
    /// only if the transcriber exposes it; see the note in `levels()` below.
    ///
    /// [decision W2.1: level stream is threaded through the transcriber's AudioCapture.
    ///  We call `transcriber.audioCapture?.startLevelStream()` when available.
    ///  AppleSpeechTranscriber exposes its AudioCapture for this purpose.]
    public func levels() -> AsyncStream<Double>? {
        // The level stream is produced by AudioCapture inside the transcriber.
        // `Transcribing` does not expose `audioCapture` in the protocol — only
        // `AppleSpeechTranscriber` does. We use protocol-existential type checking
        // here, which is the narrowest possible coupling: this stays in CaptureSession
        // (the session's own start() already called transcriber.startStream), so the
        // AudioCapture is already running.
        if let sttTranscriber = transcriber as? AudioCaptureProviding {
            return sttTranscriber.audioCapture?.startLevelStream()
        }
        return nil
    }

    // MARK: - Lifecycle

    /// Begin a new dictation. Transitions `.idle → .listening`. Throws
    /// `SpeakError.unknown` if the session is not idle.
    public func start() async throws {
        guard case .idle = state else {
            throw SpeakError.unknown(
                "CaptureSession.start() called from state \(state) — expected .idle"
            )
        }
        SpeakLog.engine.info(
            "CaptureSession: starting for locale \(self.locale.identifier, privacy: .public)"
        )
        state = .listening
        sessionStartTime = Date()
        latestChunk = nil
        finalizedText = ""

        let stream = transcriber.startStream(locale: locale)

        // Background task consumes the STT stream. Each chunk is awaited into
        // the actor before the next is consumed, so `latestChunk` is
        // consistent at stop time. `await self?.ingest(...)` is the
        // synchronization point.
        let task = Task { [weak self] in
            do {
                for try await chunk in stream {
                    await self?.ingest(chunk)
                }
            } catch {
                await self?.failStream(error)
            }
        }
        self.streamTask = task
    }

    /// End the current dictation. Transitions `.listening → .processing → .done`.
    /// Returns the `TranscriptionResult` (architecture §6) to the caller; the
    /// caller is responsible for the paste (P6) and history (P9) side effects.
    ///
    /// Throws `SpeakError` if the session is not in `.listening`, if a
    /// `cancel()` arrived during one of the awaits (`.sessionCancelled`), or if
    /// the paste step fails.
    public func stop() async throws -> TranscriptionResult {
        // If the stream already failed, surface that error before attempting stop.
        if case .error(let err) = state {
            throw err
        }
        guard case .listening = state else {
            throw SpeakError.unknown(
                "CaptureSession.stop() called from state \(state) — expected .listening"
            )
        }
        SpeakLog.engine.info("CaptureSession: stopping; finalizing transcript.")
        state = .processing

        // t_stop: monotonic instant when stop() was initiated.
        // DispatchTime.uptimeNanoseconds is a monotonic counter — immune to
        // wall-clock adjustments. [decision: DispatchTime over ContinuousClock
        //  because Duration→Double-seconds conversion is less direct; nanoseconds
        //  are stored as REAL in SQLite and converted at aggregation time.]
        let tStop = DispatchTime.now().uptimeNanoseconds

        // Stop the STT — this triggers finalization, which causes the stream
        // to drain (final chunk) and finish. Must be awaited so the stream
        // task below has something to wait for.
        await transcriber.stop()

        // Wait for the stream task to complete (all chunks drained). The
        // task awaits `ingest(_:)` on every chunk, so by the time this
        // returns, `latestChunk` is the most recent chunk processed.
        if let task = streamTask {
            await task.value
        }

        // t_transcript_ready: STT stream fully drained; raw text is available.
        let tTranscriptReady = DispatchTime.now().uptimeNanoseconds

        // Build the result. Use finalizedText when it is non-empty: it
        // accumulates every isFinal segment across all speech windows, giving the
        // full utterance for long dictations. Fall back to latestChunk?.text for
        // very short speech where no isFinal chunk arrived (only volatile chunks
        // were emitted before stop() was called), or when the STT produced no
        // output at all. Empty is valid: the STT may produce no speech.
        let transcribed = finalizedText.isEmpty ? (latestChunk?.text ?? "") : finalizedText
        // Wave B: apply snippet expansion BEFORE cleanup, so the LLM smooths any seams
        // and snippets work even when cleanup is off (the expanded text becomes rawText,
        // which is what the raw-paste fallback delivers). nil expander = unchanged.
        let rawText = expander?.expand(transcribed) ?? transcribed

        // [A2] Empty-transcript guard: a silent start+stop (blocked mic, silence) must
        // never call inserter.insert("") — that wipes the user's clipboard — and must
        // never save a zero-char history entry. Reach .done cleanly and return early.
        // runCleanup is also skipped: sending "" to Foundation Models wastes up to T_cleanup.
        if rawText.isEmpty {
            state = .done
            partialsContinuation?.finish()
            partialsContinuation = nil
            streamTask = nil
            SpeakLog.engine.info("CaptureSession: empty transcript — skip paste + history, reach .done.")
            // Use a single timestamp for both duration and createdAt so they are
            // consistent. [decision: single Date() call prevents sub-millisecond skew
            // between the two fields, which would make duration vs createdAt inconsistent.]
            let sessionEndedAt = Date()
            return TranscriptionResult(
                rawText: rawText,
                cleanedText: nil,
                duration: sessionEndedAt.timeIntervalSince(sessionStartTime ?? sessionEndedAt),
                engineId: transcriber.id,
                createdAt: sessionEndedAt
            )
        }

        // [decision: single Date() call for both duration and createdAt so the two
        // fields are consistent — no sub-millisecond skew between them.]
        let sessionEndedAt = Date()
        let duration = sessionEndedAt.timeIntervalSince(sessionStartTime ?? sessionEndedAt)

        // Run cleanup. Never throws — all failure/timeout paths return raw fallback.
        // `cleanupSeconds` is the measured time spent inside the cleanup pass:
        //   - Exactly 0.0 (sentinel) when cleanup was skipped (cleaner nil or unavailable).
        //   - > 0 when the cleaner's clean() was called (success, error, or timeout).
        // This sentinel distinction drives LatencyStats population partitioning —
        // do NOT replace with a DispatchTime.now() delta here.
        let (cleanedText, engineId, cleanupSeconds) = await runCleanup(rawText: rawText)

        // [A1] Cancel-during-processing guard: cancel() can enter this actor during
        // any of the awaits above (transcriber.stop, task.value, runCleanup). It sets
        // state=.error(.sessionCancelled). Re-check here — AFTER the last await, BEFORE
        // paste — so a cancelled session never pastes against the user's intent and
        // never overwrites .error with .done. This also covers the `inserter == nil`
        // path: we throw rather than settling .done over a cancelled session.
        if case .error(let cancelErr) = state {
            SpeakLog.engine.info(
                "CaptureSession: cancel arrived during stop() awaits — aborting paste+done."
            )
            // partialsContinuation and streamTask are already cleaned up by cancel().
            throw cancelErr
        }

        let result = TranscriptionResult(
            rawText: rawText,
            cleanedText: cleanedText,
            duration: duration,
            engineId: engineId,
            createdAt: sessionEndedAt
            // latency is set below after the paste step, once t_pasted is known.
        )

        // Paste step (P6): if an inserter was injected, paste the final text
        // before settling to `.done`. Text selection rule per architecture §11:
        //   cleanedText ?? rawText
        // (cleanup-unavailable already produced cleanedText=nil, so the raw
        //  transcript is used — the graceful-fallback contract is preserved.)
        // If paste throws, the session transitions to `.error` (paste is the
        // delivery; if it fails, the dictation has not landed at the cursor).
        if let inserter = inserter {
            let textToInsert = result.cleanedText ?? result.rawText
            do {
                try await inserter.insert(textToInsert)
            } catch {
                let speakError = (error as? SpeakError) ?? .pasteboardBusy
                SpeakLog.engine.error(
                    "CaptureSession: paste failed — \(speakError.recoverySuggestion, privacy: .public)"
                )
                state = .error(speakError)
                partialsContinuation?.finish()
                partialsContinuation = nil
                streamTask = nil
                throw speakError
            }
        }

        // t_pasted: text has been written to the pasteboard and Cmd+V simulated
        // (or the pasteboard floor ran). When no inserter is wired (tests / fixture
        // runs), tPasted ≈ tTranscriptReady + cleanup elapsed so stopToPasteSeconds
        // reflects just transcript + cleanup overhead.
        let tPasted = DispatchTime.now().uptimeNanoseconds
        let latency = LatencyRecord(
            tStop: tStop,
            tTranscriptReady: tTranscriptReady,
            tPasted: tPasted,
            cleanupSeconds: cleanupSeconds
        )

        // Rebuild result with the latency record now that all timestamps are known.
        let resultWithLatency = TranscriptionResult(
            rawText: result.rawText,
            cleanedText: result.cleanedText,
            duration: result.duration,
            engineId: result.engineId,
            createdAt: result.createdAt,
            latency: latency
        )

        state = .done
        partialsContinuation?.finish()
        partialsContinuation = nil
        streamTask = nil

        SpeakLog.engine.info("""
            CaptureSession: done. rawChars=\(resultWithLatency.rawText.count, privacy: .public) \
            cleanedChars=\(resultWithLatency.cleanedText?.count ?? -1, privacy: .public) \
            engineId=\(resultWithLatency.engineId, privacy: .public) \
            stopToPaste=\(String(format: "%.0f", latency.stopToPasteSeconds * 1000), privacy: .public)ms \
            cleanup=\(String(format: "%.0f", latency.cleanupSeconds * 1000), privacy: .public)ms
            """)
        return resultWithLatency
    }

    /// Hard cancel — stop the STT immediately and move the session to `.error`.
    /// Used by the hotkey on cancel, or by the app on quit. Safe to call from
    /// any non-terminal state.
    public func cancel() async {
        // Guard both terminal states: .error (already cancelled or failed) and
        // .done (session completed). Re-entering either would double-call
        // transcriber.stop() and needlessly re-finish the partials continuation.
        switch state {
        case .error, .done:
            return
        default:
            break
        }
        SpeakLog.engine.info("CaptureSession: cancelling.")
        await transcriber.stop()
        streamTask?.cancel()
        streamTask = nil
        state = .error(.sessionCancelled)
        partialsContinuation?.finish()
        partialsContinuation = nil
    }

    // MARK: - Internal

    /// Store a chunk from the STT stream. Actor-isolated; safe under concurrent
    /// calls from the stream task.
    ///
    /// Two paths:
    /// - volatile (isFinal == false): update latestChunk for the overlay HUD
    ///   (newest-non-empty rule, matches OverlayTextAccumulator semantics).
    /// - final   (isFinal == true):  append to finalizedText so multi-window
    ///   sessions accumulate the full utterance rather than only the last window.
    ///   latestChunk is also updated so stop() can fall back to it when
    ///   finalizedText ends up empty (e.g. single-segment or very short speech
    ///   where only a volatile arrived before the session was stopped).
    ///
    /// NOTE: `.processing` is NOT guarded here. transcriber.stop() triggers
    /// finalization and the final isFinal chunk arrives while state==.processing
    /// (during stop()'s drain). Guarding against .processing would silently drop
    /// the final segment and produce a truncated/empty transcript. Only terminal
    /// states (.done, .error) are guarded.
    private func ingest(_ chunk: TranscriptChunk) {
        // Late-ingest guard: a chunk arriving after the session is terminal
        // (cancel() during the stream drain, or a duplicate drain path) must
        // not mutate state or the partials continuation.
        switch state {
        case .done, .error:
            return
        default:
            break
        }
        latestChunk = chunk
        if chunk.isFinal {
            // Append this window's final text. Separator " " is added between
            // segments; the first segment gets no leading space. [decision: separator]
            if finalizedText.isEmpty {
                finalizedText = chunk.text
            } else {
                finalizedText += " " + chunk.text
            }
        }
        partialsContinuation?.yield(chunk)
    }

    /// Called when the STT stream throws (transcriber failure). The session
    /// moves to `.error`; `stop()` will then re-throw the error.
    private func failStream(_ error: Error) {
        // Late-failStream guard: if cancel() already set .error, do not
        // overwrite it (would change the error reason) and do not re-finish
        // the partials continuation.
        switch state {
        case .done, .error:
            return
        default:
            break
        }
        let speakError: SpeakError
        if let speakErrorCast = error as? SpeakError {
            speakError = speakErrorCast
        } else {
            speakError = .transcriberUnavailable(error.localizedDescription)
        }
        SpeakLog.engine.error(
            "CaptureSession: stream failed: \(speakError.recoverySuggestion, privacy: .public)"
        )
        state = .error(speakError)
        partialsContinuation?.finish()
        partialsContinuation = nil
    }

    /// Run the cleanup pass per the architecture's P3.5 contract.
    ///
    /// - `cleaner == nil` (cleanup off): `cleanedText = nil`, `engineId = STT id`.
    /// - `cleaner.isAvailable == false` (engine unavailable):
    ///   `cleanedText = nil`, **no error** — graceful fallback. The session
    ///   reaches `.done` and the caller pastes the raw transcript.
    /// - `cleaner.clean()` times out or throws:
    ///   `cleanedText = nil`, **no error** — graceful fallback with logged reason.
    ///   [decision: cleanup failure ≡ cleanup unavailability — both fall back to raw
    ///    transcript and reach `.done`. This honors the hard rule "cleanup unavailability
    ///    ≠ error" and ensures the overlay ALWAYS reaches a terminal hidden state after
    ///    stop, even when Foundation Models hangs or returns a GenerationError.
    ///    Previously, a thrown SpeakError.llmCleanupFailed was rethrown and surfaced as
    ///    an un-dismissable HUD error — that was a UX fault. Raw transcript is always
    ///    available and is the correct degradation target.]
    ///
    /// **Timeout (T_cleanup — benchmark.md §7):** `clean()` is wrapped in an
    /// unstructured `Task` raced against a deadline via a `CheckedContinuation`
    /// that resumes exactly once (double-resume guard via `didResume` flag).
    /// On timeout the cleanup task is cancelled (best-effort — if the on-device
    /// model does not honor cooperative cancellation, the task finishes in the
    /// background; the continuation has already resumed and the session proceeds
    /// without awaiting it). This guarantees the overlay always hides within
    /// `T_cleanup` of stop, regardless of the cleaner's implementation.
    ///
    /// Does NOT throw. All outcomes — off, unavailable, timeout, error — produce
    /// `(nil, transcriber.id)`. Only a successful clean produces `(cleaned, combinedId)`.
    /// Run the optional cleanup pass and measure how long it took.
    ///
    /// Returns a triple `(cleanedText, engineId, cleanupSeconds)` where:
    /// - `cleanupSeconds == 0.0` (exact) when cleanup did NOT run (cleaner nil or unavailable).
    ///   This is a **sentinel** — not a clock measurement — so `LatencyStats` can partition
    ///   entries as "raw" vs "cleanup" by testing `cleanupSeconds == 0`.
    /// - `cleanupSeconds > 0` when the cleaner's `clean()` was actually called, whether it
    ///   succeeded, failed, or timed out. The value is the wall-clock time spent inside the
    ///   timeout race, converted to seconds. [decision P13: timed-out runs fall into the
    ///   cleanup population — their longer elapsed time is the real user-experienced latency.]
    ///
    /// [decision P13: timing goes inside runCleanup so the sentinel `0.0` can never be produced
    ///  by a live clock read between two DispatchTime.now() calls on the no-cleanup paths.
    ///  This is the discriminator for LatencyStats population partitioning.]
    private func runCleanup(rawText: String) async -> (cleanedText: String?, engineId: String, cleanupSeconds: Double) {
        guard let cleaner = cleaner else {
            // Cleanup off — raw transcript, STT engine id only.
            // cleanupSeconds = 0.0 (sentinel: cleanup did not run).
            return (nil, transcriber.id, 0.0)
        }
        let available = await cleaner.isAvailable
        if !available {
            // Engine unavailable — graceful fallback, NOT an error.
            // cleanupSeconds = 0.0 (sentinel: cleanup did not run).
            SpeakLog.engine.info(
                "CaptureSession: cleaner '\(cleaner.id, privacy: .public)' unavailable; falling back to raw transcript."
            )
            return (nil, transcriber.id, 0.0)
        }

        // Bounded timeout: race the cleanup call against T_cleanup.
        // We cannot guarantee Foundation Models' respond() honors cooperative
        // cancellation, so we use an unstructured Task + CheckedContinuation
        // pattern that resumes the parent without awaiting the child.
        // [decision: T_cleanup = 10 s — see benchmark.md §7. Architecture §12
        //  budgets cleanup at < 1.5 s happy-path and < 2.5 s p95; 10 s sits
        //  4× above p95 so it only fires on genuine hangs, not slow-but-valid runs.]
        let cleanupTimeoutNanoseconds: UInt64 = 10_000_000_000  // 10 s [decision T_cleanup benchmark.md §7]
        let cleanerId = cleaner.id
        let mode = cleanupMode
        let sttId = transcriber.id

        // t_cleanupStart: monotonic instant just before entering the continuation.
        // Placed AFTER the early-return guards above so it is only set when cleanup
        // actually runs; cleanupSeconds > 0 is guaranteed for this path.
        let tCleanupStart = DispatchTime.now().uptimeNanoseconds

        enum CleanupOutcome {
            case success(String)
            case failure(String)   // logged reason; caller falls back to raw
            case timedOut
        }

        let outcome: CleanupOutcome = await withCheckedContinuation { continuation in
            // `resumeOnce` guards the continuation against double-resume: both the
            // cleanup task and the timeout task race to resume it; only the first
            // wins. `OSAllocatedUnfairLock<Bool>` gives a data-race-free
            // test-and-set across the two unstructured Tasks running off-actor.
            // [verified: OSAllocatedUnfairLock is available from macOS 13+;
            //  this project targets macOS 26. `withLockIfAvailable` is the
            //  recommended tryLock alternative; `withLock` is the blocking form
            //  used here — the critical section is a single Bool flip, so
            //  contention is essentially zero.]
            let resumeOnce = OSAllocatedUnfairLock<Bool>(initialState: false)

            // Unstructured task: runs the actual clean() call. Not awaited —
            // if it times out, the continuation is already resumed and this task
            // finishes (or hangs) in the background without blocking the session.
            let cleanTask = Task {
                do {
                    let cleaned = try await cleaner.clean(rawText, mode: mode)
                    resumeOnce.withLock { alreadyResumed in
                        guard !alreadyResumed else { return }
                        alreadyResumed = true
                        continuation.resume(returning: .success(cleaned))
                    }
                } catch {
                    let detail = error.localizedDescription
                    resumeOnce.withLock { alreadyResumed in
                        guard !alreadyResumed else { return }
                        alreadyResumed = true
                        continuation.resume(returning: .failure(detail))
                    }
                }
            }

            // Timeout task: resumes the continuation with .timedOut after T_cleanup.
            Task {
                try? await Task.sleep(nanoseconds: cleanupTimeoutNanoseconds)
                resumeOnce.withLock { alreadyResumed in
                    guard !alreadyResumed else { return }
                    alreadyResumed = true
                    cleanTask.cancel()   // best-effort — non-cooperative cleaners ignore this
                    continuation.resume(returning: .timedOut)
                }
            }
        }

        // t_cleanupEnd: captured immediately after the continuation resumes (whether by
        // success, failure, or timeout). The delta is the real user-experienced latency
        // for this cleanup pass, including model cold-start and timeout wait if triggered.
        let tCleanupEnd = DispatchTime.now().uptimeNanoseconds
        // [A4] Floor: when tCleanupEnd == tCleanupStart (fast machine or mocked cleaner,
        // both reads return the same nanosecond), the computed delta would be exactly 0.0
        // — colliding with the "cleanup did not run" sentinel used by LatencyStats to
        // partition raw vs cleanup entries. Apply a 1 ns floor so any path that actually
        // called clean() produces cleanupSeconds > 0, preserving the partition invariant.
        // 1 ns is chosen because it is the smallest representable DispatchTime unit and
        // is far below any real measurement (≥ 1 µs in practice). [decision A4]
        let rawDeltaNs: UInt64 = tCleanupEnd > tCleanupStart ? tCleanupEnd - tCleanupStart : 1
        let cleanupSeconds: Double = Double(rawDeltaNs) / 1_000_000_000

        switch outcome {
        case .success(let cleaned):
            SpeakLog.engine.info("""
                CaptureSession: cleanup produced \(cleaned.count, privacy: .public) chars \
                from \(rawText.count, privacy: .public) raw chars
                """)
            return (cleaned, "\(sttId)+\(cleanerId)", cleanupSeconds)
        case .failure(let detail):
            // [decision: cleanup error → graceful fallback to raw transcript, NOT .error.
            //  See runCleanup() doc comment above for the full rationale.]
            SpeakLog.engine.error(
                "CaptureSession: cleanup failed — falling back to raw transcript. Detail: \(detail, privacy: .public)"
            )
            return (nil, sttId, cleanupSeconds)
        case .timedOut:
            // [decision: cleanup timeout → graceful fallback to raw transcript.
            //  The cleanup task was cancelled (best-effort). The overlay must hide.]
            SpeakLog.engine.error(
                "CaptureSession: cleanup timed out after T_cleanup — falling back to raw transcript."
            )
            return (nil, sttId, cleanupSeconds)
        }
    }
}
