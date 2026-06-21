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
    /// Throws `SpeakError` if the session is not in `.listening`, or if the
    /// cleanup engine raises a genuine API failure (`SpeakError.llmCleanupFailed`).
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
        let duration = Date().timeIntervalSince(sessionStartTime ?? Date())
        let sessionEndedAt = Date()

        // Run cleanup. Throws on genuine API failure (caller handles).
        let (cleanedText, engineId) = try await runCleanup(rawText: rawText)

        let result = TranscriptionResult(
            rawText: rawText,
            cleanedText: cleanedText,
            duration: duration,
            engineId: engineId,
            createdAt: sessionEndedAt
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

        state = .done
        partialsContinuation?.finish()
        partialsContinuation = nil
        streamTask = nil

        SpeakLog.engine.info("""
            CaptureSession: done. rawChars=\(result.rawText.count, privacy: .public) \
            cleanedChars=\(result.cleanedText?.count ?? -1, privacy: .public) \
            engineId=\(result.engineId, privacy: .public)
            """)
        return result
    }

    /// Hard cancel — stop the STT immediately and move the session to `.error`.
    /// Used by the hotkey on cancel, or by the app on quit. Safe to call from
    /// any non-terminal state.
    public func cancel() async {
        if case .error = state {
            // Already terminal — nothing to do.
            return
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
    private func ingest(_ chunk: TranscriptChunk) {
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
    /// - `cleaner.clean()` throws: rethrown to the caller. On a genuine
    ///   API failure the caller decides whether to surface `.error` or
    ///   recover; unavailability is **never** an error.
    private func runCleanup(rawText: String) async throws -> (cleanedText: String?, engineId: String) {
        guard let cleaner = cleaner else {
            // Cleanup off — raw transcript, STT engine id only.
            return (nil, transcriber.id)
        }
        let available = await cleaner.isAvailable
        if !available {
            // Engine unavailable — graceful fallback, NOT an error.
            SpeakLog.engine.info(
                "CaptureSession: cleaner '\(cleaner.id, privacy: .public)' unavailable; falling back to raw transcript."
            )
            return (nil, transcriber.id)
        }
        do {
            let cleaned = try await cleaner.clean(rawText, mode: cleanupMode)
            SpeakLog.engine.info("""
                CaptureSession: cleanup produced \(cleaned.count, privacy: .public) chars \
                from \(rawText.count, privacy: .public) raw chars
                """)
            return (cleaned, "\(transcriber.id)+\(cleaner.id)")
        } catch let speakError as SpeakError {
            // Already a SpeakError — propagate unchanged.
            SpeakLog.engine.error(
                "CaptureSession: cleanup SpeakError — \(speakError.recoverySuggestion, privacy: .public)"
            )
            throw speakError
        } catch {
            // Map any other error to the canonical cleanup-failed type.
            let detail = error.localizedDescription
            SpeakLog.engine.error(
                "CaptureSession: cleanup failed — \(detail, privacy: .public)"
            )
            throw SpeakError.llmCleanupFailed(detail)
        }
    }
}
