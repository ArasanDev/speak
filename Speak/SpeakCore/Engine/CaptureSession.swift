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
//   • cleaner == nil (cleanup off)        → cleanedText = nil, engineId = STT id,
//                                            cleanupStatus = .skipped
//   • cleaner.isAvailable == false        → cleanedText = nil, NO error (fallback),
//                                            cleanupStatus = .fallbackRaw(.cleanerUnavailable)
//   • cleaner.clean() throws or times out → cleanedText = nil, NO error (fallback),
//                                            cleanupStatus = .fallbackRaw(reason)
//   `runCleanup` NEVER throws — every cleanup failure degrades to the raw
//   transcript and the session reaches `.done` (see CaptureSession+Cleanup.swift).
//   `.llmCleanupFailed` still exists but only inside cleaner implementations and
//   the streaming coordinator; it is caught at the runCleanup boundary.
//   [fix: audit — header previously claimed clean() throws surfaced; they never do]
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
    let expander: (any SnippetExpanding)?

    /// [PE-3.1] Optional voice-command preprocessor applied AFTER snippet expansion
    /// and BEFORE cleanup. Takes the raw transcript, returns a (stripped transcript,
    /// optional mode override) pair — or nil when no trigger is present. Injected
    /// from `SpeakEngine.newSession()` following the same pattern as `expander`.
    /// `nil` (default) = no voice-command detection; all existing call-sites unchanged.
    public typealias VoiceCommandPreprocessor = @Sendable (String) -> (transcript: String, modeOverride: CleanupMode?)?
    private let voiceCommandPreprocessor: VoiceCommandPreprocessor?

    /// [H-1] Optional Voice Actions router (specs/horizon-voice-os.md, Pillar 1).
    /// Consulted in `stop()` on the raw transcript (prefix intact), AFTER snippet
    /// expansion / the empty-transcript guard but BEFORE cleanup + paste — the one
    /// seam where an executed action/command can suppress the dictation paste.
    ///
    /// `nil` (default, and whenever `SettingsStore.voiceActionsEnabled == false`)
    /// means the whole routing block in `stop()` is skipped and the delivery path
    /// is byte-identical to pre-H-1 dictation. Assembled in `SpeakEngine.newSession()`
    /// (it captures the coordinator + fetches the action catalog), following the
    /// same inject-a-closure pattern as `voiceCommandPreprocessor`.
    public typealias VoiceActionsHandler = @Sendable (String) async -> VoiceActionOutcome
    private let voiceActionsHandler: VoiceActionsHandler?

    /// [V01-W] Cleanup warm-up state (`WarmUpState`); nil when cleanup will not
    /// run — no warm-up task is ever spawned and the session path is
    /// byte-identical to pre-V01-W. See `CaptureSession+WarmUp.swift`.
    var warmUp: WarmUpState?

    /// [fix: audit — C2/H1 cancellation] "cancel() was called" readable OFF the
    /// actor. `cancel()` sets this before its first `await` so the in-flight
    /// paste path (`runPaste` → `PasteboardWriter`'s `shouldContinue` predicate)
    /// and the bounded voice-actions wait can observe cancellation without
    /// actor-hopping back onto a suspended `stop()`. `nonisolated let` is safe:
    /// `OSAllocatedUnfairLock` is itself a lock — reads/writes are data-race-free.
    nonisolated let cancelRequestedFlag = OSAllocatedUnfairLock<Bool>(initialState: false)

    /// [fix: audit — C2 unbounded await] Upper bound on a voice-actions handler
    /// call inside `stop()`. Matched to `T_cleanup` (benchmark.md §7): an action/
    /// command transform is the same class of model work as cleanup, so it gets
    /// the same 10 s bound. Injectable (init is internal) so tests can shrink it.
    let voiceActionsTimeoutNanoseconds: UInt64

    // MARK: - Mutable session state (actor-isolated)

    var state: State = .idle

    /// PE-3 (live panel): a per-dictation cleanup-mode override set AFTER the session
    /// was created — e.g. the user tapped a destination/category chip in the live panel.
    /// When non-nil it takes precedence over the latched `cleanupMode` at cleanup time
    /// (see `effectiveCleanupMode`). Because `runCleanup` reads the effective mode at the
    /// `.processing` step (after `stop()`), a chip tap during listening reshapes THIS
    /// dictation's output. Race-free by design: set exactly once, on the actor, before
    /// `stop()` triggers cleanup (specs/live-panel-prompt-shaper.md §"State plumbing").
    private var overrideCleanupMode: CleanupMode?

    /// PE-3 (live panel): the user picked `Raw` for THIS dictation → skip cleanup and paste
    /// the raw transcript, even though a cleaner is wired. Set once at stop, like the override
    /// mode; `runCleanup` checks it first. Distinct from `overrideCleanupMode` because Raw means
    /// "no AI", not "a different prompt". [decision PE-3.]
    /// `private(set)`: read by the sibling `+Cleanup` extension; set only via the method below.
    private(set) var forcedRaw = false
    /// Agent Bridge input is a return value to the requesting MCP client, not text
    /// intended for the frontmost application. Set before stop so the normal STT +
    /// cleanup path runs but paste delivery is skipped. [decision: Agent Voice Bridge]
    private var suppressPasteDelivery = false
    var streamTask: Task<Void, Never>?
    /// Set by the stream consumer task as its final actor action — after the
    /// `for try await` loop exits (clean finish, thrown error, or cancel).
    /// `awaitStreamDrainWithWatchdog` polls this instead of awaiting
    /// `streamTask.value` inside a task group, because `Task.value` is NOT
    /// cancellation-responsive: a stalled consumer wedged the group itself and
    /// the watchdog's cancel path was unreachable. [fix: audit — watchdog]
    private var streamDrained = true
    private var latestChunk: TranscriptChunk?
    /// Progressive chunk-by-chunk cleanup coordinator for live speech.
    var streamingCoordinator: StreamingChunkCoordinator?
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
    var finalizedText: String = ""
    /// [fix: audit — unordered streaming ingestion] Monotonically increasing
    /// sequence number stamped onto each finalized chunk handed to
    /// `StreamingChunkCoordinator`. Assigned inside `ingest` on the actor, then
    /// carried through the unstructured `Task` hop so the coordinator can stitch
    /// results in emission order even when the tasks arrive reordered.
    private var ingestSequence = 0
    private var sessionStartTime: Date?
    var partialsContinuation: AsyncStream<TranscriptChunk>.Continuation?

    /// Optional prefix prepended to delivered text (e.g. "[speak] " or "[voice] ")
    /// to signal coding agents that the prompt originated from speech-to-text.
    public private(set) var agentPrefix: String = ""
    public private(set) var agentPrefixStyle: AgentPrefixStyle = .none
    public private(set) var agentPrefixIncludeState: Bool = false

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
    ///   - agentPrefix: Optional prompt prefix for coding agents. Default: "" (none).
    ///   - agentPrefixStyle: Structured STT origin tag style. Default: .none.
    ///   - agentPrefixIncludeState: Whether to append :clean or :raw to the tag. Default: false.
    ///   - voiceActionsTimeoutNanoseconds: Bound on the voice-actions handler call
    ///     inside `stop()` [fix: audit — unbounded await]. Defaults to T_cleanup
    ///     (10 s, benchmark.md §7); tests inject a smaller value.
    ///
    /// `internal` — engine-minted only. No code outside the `SpeakCore` module
    /// can construct a session: `SpeakEngine.beginDictation` /
    /// `beginAuxiliarySession` are the sole mint points and the only paths that
    /// enforce the mute, mic-permission, and single-capture gates. Tests use
    /// `@testable`, which sees internal symbols. [fix: audit — gate bypass]
    init(transcriber: any Transcribing,
         cleaner: (any LLMCleaning)? = nil,
         inserter: (any TextInserting)? = nil,
         streamingInserter: (any StreamingRawTextInserting)? = nil,
         locale: Locale = Locale(identifier: "en-US"),
         cleanupMode: CleanupMode = .punctuation,
         expander: (any SnippetExpanding)? = nil,
         voiceCommandPreprocessor: VoiceCommandPreprocessor? = nil,
         voiceActionsHandler: VoiceActionsHandler? = nil,
         warmUpHandler: WarmUpHandler? = nil,
         agentPrefix: String = "",
         agentPrefixStyle: AgentPrefixStyle = .none,
         agentPrefixIncludeState: Bool = false,
         voiceActionsTimeoutNanoseconds: UInt64 = 10_000_000_000) {
        self.transcriber = transcriber
        self.cleaner = cleaner
        self.inserter = inserter
        self.streamingInserter = streamingInserter
        self.locale = locale
        self.cleanupMode = cleanupMode
        self.expander = expander
        self.voiceCommandPreprocessor = voiceCommandPreprocessor
        self.voiceActionsHandler = voiceActionsHandler
        self.warmUp = warmUpHandler.map { WarmUpState(handler: $0) }
        self.agentPrefix = agentPrefix
        self.agentPrefixStyle = agentPrefixStyle
        self.agentPrefixIncludeState = agentPrefixIncludeState
        self.voiceActionsTimeoutNanoseconds = voiceActionsTimeoutNanoseconds
    }

    /// Set or update the agent prefix prepended to delivered text at paste time.
    public func setAgentPrefix(_ prefix: String) {
        self.agentPrefix = prefix
    }

    /// Set or update the agent prefix style and state inclusion at paste time.
    public func setAgentPrefix(style: AgentPrefixStyle, includeState: Bool) {
        self.agentPrefixStyle = style
        self.agentPrefixIncludeState = includeState
    }

    // MARK: - PE-3 per-dictation cleanup override (live panel)

    /// The cleanup mode actually used by the cleanup pass: the live-panel override if
    /// one was set, else the mode latched at init. Internal so unit tests can assert the
    /// override took effect without exposing the private backing store.
    var effectiveCleanupMode: CleanupMode { overrideCleanupMode ?? cleanupMode }

    /// Override the cleanup mode for THIS session, chosen by the user in the live panel
    /// (a destination/category chip tap). Effective only if set BEFORE the session reaches
    /// `.processing` — `runCleanup` reads `effectiveCleanupMode` at that step. The app layer
    /// applies this once, at stop, before `endDictation()` triggers the cleanup pass.
    /// [decision PE-3: set-once at stop on the actor → no per-tap race.]
    public func setOverrideCleanupMode(_ mode: CleanupMode) {
        overrideCleanupMode = mode
    }

    /// Force raw passthrough for THIS session (the user picked `Raw` in the live panel):
    /// `runCleanup` skips the cleaner and the raw transcript is pasted. Set once at stop.
    public func forceRawForThisSession() {
        forcedRaw = true
    }

    /// Return this session's transcript to an agent without injecting it into the
    /// focused application. Effective only when set before `stop()` reaches delivery.
    public func suppressPasteForAgentResponse() {
        suppressPasteDelivery = true
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
        ingestSequence = 0

        if let cleaner, !forcedRaw {
            if await cleaner.isAvailable {
                streamingCoordinator = StreamingChunkCoordinator(cleaner: cleaner, mode: effectiveCleanupMode)
            }
        }

        // [fix: audit — cancel-during-start] A cancel() can enter the actor
        // during the `isAvailable` suspension above, setting
        // `.error(.sessionCancelled)`. Without this re-check, start() would
        // proceed to startStream() and open the mic on a session that is
        // already dead — the cancelled session's stream then runs until some
        // later stop() happens to clean it up. Throw the stored cancel error
        // so the engine releases the session instead of orphaning a live mic.
        if case .error(let startErr) = state {
            throw startErr
        }

        let stream = transcriber.startStream(locale: locale)

        // Background task consumes the STT stream. Each chunk is awaited into
        // the actor before the next is consumed, so `latestChunk` is
        // consistent at stop time. `await self?.ingest(...)` is the
        // synchronization point.
        //
        // [fix: wedge — former TODO resolved] A stream that ends while the
        // session is `.listening` no longer wedges it: real capture teardown
        // (unrecoverable route/device change) now finishes the producer's
        // stream THROWING (`SpeakError.captureInterrupted`), which lands in
        // `failStream` → `.error` → the engine's self-healing A3 guard
        // releases the session on the next begin. Clean finishes still mean
        // "stopped normally / fixture EOF" and stay legal — the positive
        // throwing signal is what distinguishes teardown from normal end,
        // which is why mock streams finishing early remain valid.
        self.streamDrained = false
        let task = Task { [weak self] in
            do {
                for try await chunk in stream {
                    await self?.ingest(chunk)
                }
            } catch {
                await self?.failStream(error)
            }
            // Final actor action: flag the drain watchdog. Runs on every exit
            // path — clean finish, thrown error, or task cancellation.
            await self?.markStreamDrained()
        }
        self.streamTask = task

        // [V01-W] Fire the cleanup warm-up concurrently with listening — never
        // blocks start(). See `CaptureSession+WarmUp.swift`.
        fireWarmUp()
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

        // [V01-W] Cancel any in-flight warm-up WITHOUT awaiting it — warm-up
        // must never sit on the stop→clean critical path. The real clean()
        // below uses its own fresh session, so a still-running warm-up task
        // finishing in the background cannot affect it.
        cancelWarmUp()

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

        // Wait for the stream task to complete (all chunks drained).
        // Protected by a 5-second watchdog so a stalled audio stream cannot hang stop().
        await awaitStreamDrainWithWatchdog()

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

        // [PE-3.1] Voice-command detection: if a trigger phrase is at the start of the
        // transcript AND no manual override is already set (chip tap / Raw pick wins),
        // strip the phrase and latch the resolved cleanup mode for this dictation.
        // `cleanupInputText` is what the LLM receives; `rawText` (original) is preserved
        // in the history entry and TranscriptionResult so the full utterance is recorded.
        var cleanupInputText = rawText
        if overrideCleanupMode == nil, !forcedRaw,
           let vcResult = voiceCommandPreprocessor?(rawText) {
            cleanupInputText = vcResult.transcript
            if let mode = vcResult.modeOverride {
                overrideCleanupMode = mode
            }
            SpeakLog.engine.info(
                "CaptureSession: voice command — cleanup input trimmed to \(cleanupInputText.count, privacy: .public) chars."
            )
        }

        // [A2] Empty-transcript guard: a silent start+stop (blocked mic, silence) must
        // never call inserter.insert("") — that wipes the user's clipboard — and must
        // never save a zero-char history entry. Reach .done cleanly and return early.
        // runCleanup is also skipped: sending "" to Foundation Models wastes up to T_cleanup.
        // Guard on rawText (original) — the stripped text may be empty when the user
        // spoke only the trigger phrase, which is fine: a short empty paste is preferable
        // to treating the whole utterance as silence.
        if rawText.isEmpty {
            return try settleEmptyTranscript()
        }

        // [decision: single Date() call for both duration and createdAt so the two
        // fields are consistent — no sub-millisecond skew between them.]
        let sessionEndedAt = Date()
        let duration = sessionEndedAt.timeIntervalSince(sessionStartTime ?? sessionEndedAt)

        // [H-1] Voice Actions routing (specs/horizon-voice-os.md, Pillar 1). Consulted
        // on `rawText` (prefix intact, pre-cleanup) at the one seam where an executed
        // action/command can suppress the dictation paste. Returns a non-nil result to
        // settle terminally (paste suppressed); `nil` ⇒ proceed with the normal cleanup+
        // paste path below (feature off, plain dictation, or degrade — words preserved).
        if let executedResult = try await routeVoiceActions(
            rawText: rawText, duration: duration, createdAt: sessionEndedAt
        ) {
            return executedResult
        }

        // Run cleanup. Never throws — all failure/timeout paths return raw fallback.
        // `cleanupSeconds` is the measured time spent inside the cleanup pass:
        //   - Exactly 0.0 (sentinel) when cleanup was skipped (cleaner nil or Raw override).
        //   - > 0 when a cleanup pass was attempted (success OR any fallback).
        // `cleanupStatus` is the honest outcome discriminator — `.cleaned` vs
        // `.fallbackRaw(reason)` vs `.skipped` — persisted to history so
        // LatencyStats never counts a failed/timed-out pass as a success.
        // [PE-3.1] cleanupInputText is the snippet-expanded + voice-command-stripped text.
        // It equals rawText when no voice command was detected.
        let cleanup = await runCleanup(rawText: cleanupInputText)
        let cleanedText = cleanup.cleanedText
        let engineId = cleanup.engineId
        let cleanupSeconds = cleanup.cleanupSeconds
        let cleanupStatus = cleanup.status

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
            createdAt: sessionEndedAt,
            cleanupStatus: cleanupStatus
            // latency is set below after the paste step, once t_pasted is known.
        )

        if suppressPasteDelivery {
            return settleAgentResponse(result)
        }

        // Paste step (P6): deliver the final text via runPaste() (CaptureSession+Paste.swift).
        try await runPaste(result)

        // [A1-parallel, fix: audit — cancel-during-paste] `runPaste` suspends on
        // the inserter (clipboard write + settle + Cmd+V). A cancel() can land
        // during it; when the inserter returns without throwing, the state must
        // be re-checked so a cancelled session never settles `.done`.
        if case .error(let cancelErr) = state {
            SpeakLog.engine.info(
                "CaptureSession: cancel arrived during paste — refusing to settle .done."
            )
            throw cancelErr
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
            latency: latency,
            cleanupStatus: cleanupStatus
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

    /// [A2] Terminal settle for an empty transcript: never paste, never write
    /// history, never run cleanup. Re-checks `.error` first — a stream failure
    /// or cancel() can land during the stop()/drain awaits and must not be
    /// masked as a silent dictation. [fix: error masked by empty .done]
    private func settleEmptyTranscript() throws -> TranscriptionResult {
        if case .error(let drainErr) = state {
            throw drainErr
        }
        state = .done
        partialsContinuation?.finish()
        partialsContinuation = nil
        streamTask = nil
        let audioWasSilent = classifySilentInput()
        if !audioWasSilent {
            SpeakLog.engine.info("CaptureSession: empty transcript — skip paste + history, reach .done.")
        }
        // Single timestamp for both duration and createdAt — no sub-ms skew.
        let sessionEndedAt = Date()
        return TranscriptionResult(
            rawText: "",
            cleanedText: nil,
            duration: sessionEndedAt.timeIntervalSince(sessionStartTime ?? sessionEndedAt),
            engineId: transcriber.id,
            createdAt: sessionEndedAt,
            audioWasSilent: audioWasSilent
        )
    }

    private func settleAgentResponse(_ result: TranscriptionResult) -> TranscriptionResult {
        state = .done
        partialsContinuation?.finish()
        partialsContinuation = nil
        streamTask = nil
        SpeakLog.agentBridge.info("CaptureSession: agent response ready — paste delivery suppressed.")
        return result
    }

    /// [H-1] Run the Voice Actions router against `rawText` and map its outcome.
    ///
    /// - Returns: a terminal `TranscriptionResult` when an action/command executed
    ///   (the caller must return it immediately — the dictation paste is suppressed);
    ///   `nil` when the caller should proceed with the normal cleanup + paste path
    ///   (feature off, plain `.dictation`, or a `.degradedToDictation` — in which case
    ///   the ORIGINAL transcript is preserved and pasted, never lost).
    /// - Throws: the cancel error if a `cancel()` entered the actor while the (async)
    ///   action/command was in flight — a cancelled session must never settle `.done`.
    private func routeVoiceActions(
        rawText: String,
        duration: TimeInterval,
        createdAt: Date
    ) async throws -> TranscriptionResult? {
        guard let voiceActionsHandler else { return nil }
        // [fix: audit — C2 unbounded await] The handler awaits Shortcut/AX work
        // that can hang; run it under a bounded, cancel-responsive wait so a
        // hung action can never wedge `stop()` (or a cancel) forever.
        let outcome = await boundedVoiceActions(voiceActionsHandler, rawText: rawText)
        // [A1-parallel] `run(named:)` / `CommandModeService.run` are async — a cancel()
        // may have entered the actor while they were in flight. Re-check BEFORE settling
        // terminal state so a cancelled session never reports `.done`.
        if case .error(let cancelErr) = state {
            SpeakLog.engine.info("CaptureSession: cancel arrived during Voice Actions routing — aborting.")
            throw cancelErr
        }
        switch outcome {
        case .dictation:
            return nil  // proceed with normal cleanup + paste.
        case .degradedToDictation(_, let reason):
            // The words survive: proceed with normal cleanup + paste of rawText.
            SpeakLog.voiceActions.info(
                "CaptureSession: Voice Actions degraded to dictation — \(reason, privacy: .public)."
            )
            return nil
        case .actionExecuted(let name):
            SpeakLog.voiceActions.info(
                "CaptureSession: Voice Actions executed action '\(name, privacy: .public)' — suppressing dictation paste."
            )
            return settleVoiceActionExecuted(rawText: rawText, duration: duration, createdAt: createdAt)
        case .commandExecuted:
            SpeakLog.voiceActions.info(
                "CaptureSession: Voice Actions command executed (selection replaced) — suppressing dictation paste."
            )
            return settleVoiceActionExecuted(rawText: rawText, duration: duration, createdAt: createdAt)
        }
    }

    /// [fix: audit — C2 unbounded await] Run the voice-actions handler under a
    /// bounded wait. Two exits, both benign:
    ///
    ///   - **Deadline** (`voiceActionsTimeoutNanoseconds`, default T_cleanup = 10 s
    ///     [benchmark.md §7]): resumes `.degradedToDictation` so the user's words
    ///     are still delivered through the normal cleanup + paste path.
    ///   - **Cancel flag** (`cancelRequestedFlag`, polled at 10 ms): resumes
    ///     `.degradedToDictation` immediately; the `.error` re-check in
    ///     `routeVoiceActions` then throws `.sessionCancelled`. Without this, a
    ///     cancel() during a hung action would sit behind the full bound — or
    ///     forever, if the handler never returns.
    ///
    /// The continuation resumes exactly once (`resumeOnce` test-and-set); a
    /// hung handler that eventually completes finds the slot taken and its late
    /// outcome is discarded — its side effects (a Shortcut already run, an AX
    /// replacement already applied) may still have landed, which is logged via
    /// the timeout path. [unverified: a hung Shortcut cannot be un-run.]
    private func boundedVoiceActions(
        _ handler: @escaping VoiceActionsHandler,
        rawText: String
    ) async -> VoiceActionOutcome {
        await withCheckedContinuation { continuation in
            let resumeOnce = OSAllocatedUnfairLock<Bool>(initialState: false)
            let flag = cancelRequestedFlag

            let work = Task(priority: .userInitiated) {
                let outcome = await handler(rawText)
                resumeOnce.withLock { resumed in
                    guard !resumed else { return }
                    resumed = true
                    continuation.resume(returning: outcome)
                }
            }

            Task {
                let deadline = DispatchTime.now().uptimeNanoseconds + self.voiceActionsTimeoutNanoseconds
                while DispatchTime.now().uptimeNanoseconds < deadline {
                    if flag.withLock({ $0 }) {
                        resumeOnce.withLock { resumed in
                            guard !resumed else { return }
                            resumed = true
                            work.cancel()   // best-effort — a hung handler ignores this
                            continuation.resume(returning: .degradedToDictation(
                                text: rawText, reason: "cancelled during voice actions"))
                        }
                        return
                    }
                    try? await Task.sleep(nanoseconds: 10_000_000) // 10 ms poll
                }
                resumeOnce.withLock { resumed in
                    guard !resumed else { return }
                    resumed = true
                    work.cancel()
                    SpeakLog.voiceActions.error(
                        "CaptureSession: voice actions timed out — degrading to dictation."
                    )
                    continuation.resume(returning: .degradedToDictation(
                        text: rawText, reason: "voice actions timed out"))
                }
            }
        }
    }

    /// Silence check for the empty-transcript path: if the input never crossed
    /// the audible floor the mic delivered nothing (muted headset, wrong
    /// pinned device, dead input) — not "user didn't speak". Surface it so the
    /// caller can warn instead of a silent .done.
    /// [fix: silent-mic sessions surfaced as silent .done]
    /// 0.01 RMS ≈ well above the room-noise floor (~0.002 measured on this
    /// hardware) yet far below quiet speech (~0.05+). Transcribers with no
    /// live capture (fixtures, mocks) return nil → not silent.
    /// [inferred: measured floor on MacBook mic at gain 70]
    private func classifySilentInput() -> Bool {
        guard let peak = (transcriber as? AudioCaptureProviding)?.audioCapture?.peakInputLevel
        else { return false }
        if peak < 0.01 {
            SpeakLog.engine.warning(
                "CaptureSession: empty transcript with silent input (peak RMS \(peak, privacy: .public)) — mic muted, wrong pinned device, or dead input."
            )
            return true
        }
        return false
    }

    /// [H-1] Settle the session terminally after Voice Actions executed an action or a
    /// command — the paste is deliberately suppressed (the action/command already
    /// superseded the dictation). Mirrors the empty-transcript terminal settle: reach
    /// `.done`, finish the partials stream, and return a paste-free `TranscriptionResult`.
    ///
    /// No `latency` record is attached — no paste occurred, so `stopToPasteSeconds` would
    /// be meaningless. `cleanedText` is nil: cleanup was skipped. `rawText` carries the
    /// original utterance (prefix intact) so history/`lastTranscript` never see empty text.
    private func settleVoiceActionExecuted(
        rawText: String,
        duration: TimeInterval,
        createdAt: Date
    ) -> TranscriptionResult {
        state = .done
        partialsContinuation?.finish()
        partialsContinuation = nil
        streamTask = nil
        return TranscriptionResult(
            rawText: rawText,
            cleanedText: nil,
            duration: duration,
            engineId: transcriber.id,
            createdAt: createdAt
        )
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
        // [fix: audit — C2/H1] Set the off-actor flag BEFORE the first await so a
        // paste suspended inside `insert(_:shouldContinue:)` or a voice-actions
        // wait observes cancellation immediately — not only after the actor
        // resumes. This is the flag `runPaste`'s predicate reads.
        cancelRequestedFlag.withLock { $0 = true }
        await transcriber.stop()
        cancelWarmUp()
        if let coordinator = streamingCoordinator {
            Task { await coordinator.reset() }
            streamingCoordinator = nil
        }
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

            if let coordinator = streamingCoordinator {
                // [fix: audit — unordered ingestion] Stamp the chunk with an
                // actor-assigned sequence number BEFORE hopping off the actor.
                // The unstructured Task can deliver it to the coordinator out of
                // order; the coordinator sorts by `seq` at stitch time so the
                // final transcript always follows emission order. Cleanup itself
                // stays progressive/overlapped — only stitching is reordered.
                let seq = ingestSequence
                ingestSequence += 1
                let textToIngest = expander?.expand(chunk.text) ?? chunk.text
                Task(priority: .userInitiated) { await coordinator.ingestChunk(textToIngest, sequence: seq) }
            }

            // Stream finalized chunk if keystroke streaming is enabled.
            // [decision P11-c] Stream isFinal chunks only (volatile chunks are revised;
            // once-final chunks won't change). Non-blocking: errors are logged and
            // swallowed; streaming failure does not abort the session (raw paste at
            // stop is the fallback). AX-denied is expected and logged; no error
            // transition. [P11-c §4 error handling]
            // Keystroke streaming is DEFERRED to v0.1 (tasks #5–#11) — NOT shipped in v0.
            // Reason: correctness, not the permission-toggle freeze. That freeze was the
            // HotkeyMonitor's active (.defaultTap) CGEventTap, now fixed to .listenOnly
            // (see HotkeyMonitor.buildTap, 2026-06-29) — unrelated to this path.
            // The streaming gap here is ordering: fire-and-forget Tasks calling
            // CGEvent.post() for rapid finalized chunks have no cross-chunk ordering
            // guarantee → scrambled text. v0.1 must serialize on a dedicated serial
            // queue before re-enabling.
            // TODO: v0.1 — implement serial keystroke queue (DispatchQueue.serialQueue)
            if let streamingInserter, false {
                // DEFERRED (v0.1): see comment above — kept compiled (not deleted) so the
                // serialization work in v0.1 has the wiring in place.
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
        // Yield partial chunk to the overlay stream. Prepend `finalizedText` (excluding
        // the current final chunk's own addition if already appended) so the live HUD
        // displays the complete accumulated utterance without dropping earlier segments.
        if !finalizedText.isEmpty {
            let combinedText: String
            if chunk.isFinal {
                combinedText = finalizedText
            } else {
                combinedText = finalizedText + " " + chunk.text
            }
            let combinedChunk = TranscriptChunk(
                text: combinedText,
                isFinal: chunk.isFinal,
                timestamp: chunk.timestamp
            )
            partialsContinuation?.yield(combinedChunk)
        } else {
            partialsContinuation?.yield(chunk)
        }
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

extension CaptureSession {
    /// Wait for `streamTask` to finish, or give up after the watchdog so a stalled
    /// audio route cannot hang `stop()` indefinitely.
    /// [decision: 5 s — Loop #77 AirPods/route hang; short of the STT finalization
    ///  10 s window so stop() still returns; on fire we cancel the stream and log
    ///  loudly rather than pretending drain completed.]
    ///
    /// Polls the `streamDrained` flag (set by the consumer task's final actor
    /// action) instead of awaiting `streamTask.value` inside a `withTaskGroup`.
    /// `Task.value` is NOT cancellation-responsive: a truly stalled consumer
    /// kept that group child suspended forever, `withTaskGroup` waits for all
    /// children, and the watchdog's `task.cancel()` below the group was
    /// unreachable — a real stall deadlocked the watchdog branch itself.
    /// [fix: audit — unreachable watchdog]
    fileprivate func awaitStreamDrainWithWatchdog() async {
        guard streamTask != nil else { return }
        let deadline = DispatchTime.now().uptimeNanoseconds + 5_000_000_000
        while !streamDrained, DispatchTime.now().uptimeNanoseconds < deadline {
            try? await Task.sleep(nanoseconds: 10_000_000) // 10 ms poll
        }
        if !streamDrained {
            SpeakLog.engine.error(
                "CaptureSession: stream drain watchdog fired after 5s — canceling streamTask; transcript may be incomplete."
            )
            streamTask?.cancel()
        }
        streamTask = nil
    }

    /// Consumer task epilogue — marks the STT stream fully drained so
    /// `awaitStreamDrainWithWatchdog` can observe completion without awaiting
    /// `Task.value` (not cancellation-responsive).
    private func markStreamDrained() {
        streamDrained = true
    }
}
