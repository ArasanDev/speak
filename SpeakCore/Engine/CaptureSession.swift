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

    let transcriber: any Transcribing
    let cleaner: (any LLMCleaning)?
    let inserter: (any TextInserting)?
    /// Optional streaming raw-text inserter for keystroke injection during listening.
    /// When non-nil, finalized chunks are streamed character-by-character via keystroke
    /// injection (no final cleaned paste to avoid duplication). When nil, the final
    /// cleaned text is pasted normally. Injected from settings at session start (§5 Q5).
    let streamingInserter: (any StreamingRawTextInserting)?
    /// Optional snippet expander applied to the raw transcript BEFORE cleanup.
    /// `nil` (default) means no expansion — behavior is identical to pre-Wave-B.
    private let expander: (any SnippetExpanding)?

    // MARK: - Mutable session state (actor-isolated)

    var state: State = .idle
    var streamTask: Task<Void, Never>?
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
    var partialsContinuation: AsyncStream<TranscriptChunk>.Continuation?

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
    ///     When `streamingInserter` is non-nil, `inserter` is not called to avoid
    ///     duplication (raw text is streamed, not cleaned text).
    ///   - streamingInserter: `nil` (default) disables keystroke streaming.
    ///     Non-nil enables streaming of finalized chunks during listening. When
    ///     enabled, `inserter` is not called (raw is the in-document deliverable).
    ///     Injected from `SettingsStore.streamingMode` at session start. §5 (P11-c).
    ///   - locale: Locale passed to the transcriber. Default: en-US.
    ///   - cleanupMode: `CleanupMode` passed to the cleaner. Default: `.punctuation`.
    ///   - expander: Optional snippet expander applied to the raw transcript before
    ///     cleanup. `nil` (default) = no expansion.
    public init(transcriber: any Transcribing,
                cleaner: (any LLMCleaning)? = nil,
                inserter: (any TextInserting)? = nil,
                streamingInserter: (any StreamingRawTextInserting)? = nil,
                locale: Locale = Locale(identifier: "en-US"),
                cleanupMode: CleanupMode = .punctuation,
                expander: (any SnippetExpanding)? = nil) {
        self.transcriber = transcriber
        self.cleaner = cleaner
        self.inserter = inserter
        self.streamingInserter = streamingInserter
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

        // Paste step (P6): deliver the final text via runPaste() (CaptureSession+Paste.swift).
        try await runPaste(result)

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
    /// Three paths:
    /// - volatile (isFinal == false): update latestChunk for the overlay HUD
    ///   (newest-non-empty rule, matches OverlayTextAccumulator semantics).
    /// - final   (isFinal == true):  append to finalizedText so multi-window
    ///   sessions accumulate the full utterance rather than only the last window.
    ///   latestChunk is also updated so stop() can fall back to it when
    ///   finalizedText ends up empty (e.g. single-segment or very short speech
    ///   where only a volatile arrived before the session was stopped).
    /// - streaming (isFinal == true AND streamingInserter != nil): stream the finalized
    ///   chunk to the keystroke inserter. If streaming fails (e.g., AX denied),
    ///   log and continue (raw paste fallback is still available at stop time).
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

            // Stream finalized chunk if keystroke streaming is enabled.
            // [decision P11-c] Stream isFinal chunks only (volatile chunks are revised;
            // once-final chunks won't change). Non-blocking: errors are logged and
            // swallowed; streaming failure does not abort the session (raw paste at
            // stop is the fallback). AX-denied is expected and logged; no error
            // transition. [P11-c §4 error handling]
            // CRITICAL: Keystroke injection must be serialized (not fire-and-forget Tasks)
            // to prevent CGEvent.post() collisions. Skip streaming for now; will re-enable
            // in v0.1 with proper serial queue management.
            // TODO: v0.1 — implement serial keystroke queue (DispatchQueue.serialQueue)
            if let streamingInserter, false {
                // DISABLED: streaming causes system hangs due to unserialized CGEvent.post() calls.
                // Re-enable in v0.1 with proper serial queue.
                Task {
                    do {
                        try await streamingInserter.insertChunk(chunk.text)
                    } catch {
                        let speakError = (error as? SpeakError) ?? .pasteboardBusy
                        SpeakLog.engine.warning(
                            "CaptureSession: keystroke streaming failed (logged, continuing) — \(speakError.recoverySuggestion, privacy: .public)"
                        )
                    }
                }
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
}
