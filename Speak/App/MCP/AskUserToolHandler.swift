// Speak/App/MCP/AskUserToolHandler.swift
//
// Layer 4 of the Bidirectional Voice Architecture: Ask User Tool Handler.
//
// Responsibilities:
//   - Implements MCP tool `speak_ask_user(prompt: String, mode: String)` which triggers
//     the floating overlay in Magenta conversation mode.
//   - Connects user responses directly back to the calling agent via async continuation
//     (bypassing NSPasteboard completely per AGENTS.md §2.6 and §2.27).
//   - Manages turn lifecycle with `ConversationLoopManager` and `OverlayController`.
//   - Owns the Layer 1 primitives (`VoiceActivityDetector`, `SpeechSynthesizerStream`),
//     which were never previously constructed anywhere in the app (specs/output-
//     conversation-reconnect.md). This handler is the only place that instantiates
//     them, feeds the VAD's buffer-derived events into the three existing
//     `ConversationLoopManager` handlers, and routes agent speech through the
//     synthesizer so a VAD-detected barge-in can `stopImmediately()`.

import Foundation
import os
import SpeakCore

/// Custom error types for `AskUserToolHandler`.
enum AskUserError: Error, Sendable, CustomStringConvertible, Equatable {
    case alreadyInFlight
    case cancelled
    case invalidPrompt
    case micUnavailable
    case timeout

    var description: String {
        switch self {
        case .alreadyInFlight:
            return "Another ask_user request is already active."
        case .cancelled:
            return "User cancelled or interrupted the prompt."
        case .invalidPrompt:
            return "Prompt text cannot be empty."
        case .micUnavailable:
            return "Microphone unavailable — another capture is in flight, or the mic is muted/denied."
        case .timeout:
            return "ask_user request timed out waiting for user response."
        }
    }
}

/// `@MainActor` handler for the `speak_ask_user` tool execution.
@MainActor
final class AskUserToolHandler {

    // MARK: - State

    private var activeContinuation: CheckedContinuation<String, Error>?
    private var currentLoopManager: ConversationLoopManager?

    // Layer 1 primitives — constructed and owned here (output-conversation-reconnect
    // §3: "AskUserToolHandler constructs both primitives ... and tears them down on
    // every exit path"). Both are `nil` whenever no request is in flight.
    private var currentVAD: VoiceActivityDetector?
    private var currentSynth: SpeechSynthesizerStream?
    private weak var currentDictationController: DictationController?

    /// Periodic ~250ms ping while the VAD reports active user speech, feeding the
    /// growing transcript into `handleVADTranscriptUpdated`. The VAD itself only
    /// emits one-shot transition events (speechStarted/speechEnded/bargeIn) — it
    /// has no periodic "still speaking" signal — so this is what keeps
    /// `ConversationLoopManager`'s `.listening(userText:)` state (and its silence
    /// timer resets) in sync with STT partials while the user is actually talking.
    private var transcriptPingTask: Task<Void, Never>?

    // MARK: - Init

    init() {}

    // MARK: - Ask User Execution

    /// Execute `speak_ask_user` tool call.
    ///
    /// - Parameters:
    ///   - prompt: Spoken and displayed prompt text for the user.
    ///   - modeString: Optional raw mode string ("fullDuplex", "pushToTalk", "gatedTurn").
    ///   - overlayController: Main app `OverlayController`.
    ///   - voiceOut: Legacy TTS synthesizer parameter, kept for call-site/test source
    ///     compatibility. Prompt readback now goes through the locally-owned
    ///     `SpeechSynthesizerStream` instead (see class doc) so that barge-in can
    ///     `stopImmediately()` it — `voiceOut` is no longer used for playback here.
    ///   - settingsStore: App settings store.
    /// - Returns: The user's spoken or typed response string.
    func askUser(
        prompt: String,
        modeString: String?,
        dictationController: DictationController? = nil,
        overlayController: OverlayController,
        voiceOut: any SpeechSynthesizing,
        settingsStore: SettingsStore
    ) async throws -> String {
        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPrompt.isEmpty else {
            SpeakLog.agentBridge.error("AskUserToolHandler: prompt is empty.")
            throw AskUserError.invalidPrompt
        }

        guard activeContinuation == nil else {
            SpeakLog.agentBridge.error("AskUserToolHandler: another ask_user call is already in flight.")
            throw AskUserError.alreadyInFlight
        }

        // Map mode string to ConversationMode (default: .fullDuplex)
        let mode = parseMode(modeString)

        SpeakLog.agentBridge.info(
            "AskUserToolHandler: ask_user starting with mode=\(mode.rawValue, privacy: .public), prompt length=\(trimmedPrompt.count, privacy: .public)."
        )

        // Construct ConversationLoopManager for Magenta overlay mode
        let loopManager = ConversationLoopManager(initialMode: mode)
        self.currentLoopManager = loopManager

        // Construct the two Layer 1 orphans (output-conversation-reconnect §3).
        let vad = VoiceActivityDetector()
        let synth = SpeechSynthesizerStream()
        self.currentVAD = vad
        self.currentSynth = synth
        self.currentDictationController = dictationController

        // Attach loopManager to OverlayViewModel so OverlayRootView renders ConversationOverlayView
        overlayController.overlayModel.conversationLoopManager = loopManager

        // Begin dictation to open mic hardware & start SpeechAnalyzer STT stream, and
        // attach the VAD to the same live AudioCapture the transcriber is using.
        try await beginCaptureOrFallback(
            dictationController: dictationController, overlayController: overlayController, vad: vad
        )
        overlayController.overlayModel.overlayState = .listening

        return try await withCheckedThrowingContinuation { continuation in
            self.activeContinuation = continuation

            // Setup 120-second timeout task to guarantee continuation never hangs indefinitely.
            // This is the backstop, not the primary path — a normal turn now commits on
            // VAD silence in well under a second (§3.1).
            let timeoutTask = Task { @MainActor [weak self, weak overlayController] in
                do {
                    try await Task.sleep(for: .seconds(120))
                } catch {
                    return // Task was cancelled (user committed or interrupted) — exit cleanly
                }
                guard let self = self, self.activeContinuation != nil else { return }
                SpeakLog.agentBridge.warning("AskUserToolHandler: request timed out after 120 seconds.")
                Task { @MainActor in
                    await self.finish(with: .failure(AskUserError.timeout), overlayController: overlayController)
                }
            }

            wireLoopManagerCallbacks(
                loopManager: loopManager, overlayController: overlayController, timeoutTask: timeoutTask
            )
            wireVADCallbacks(vad: vad, synth: synth, loopManager: loopManager, dictationController: dictationController)

            // Begin prompt speech readback & transition overlay state
            Task { @MainActor [weak self] in
                await self?.speakPromptAndBootstrapListening(
                    trimmedPrompt: trimmedPrompt, loopManager: loopManager, vad: vad, synth: synth,
                    settingsStore: settingsStore
                )
            }
        }
    }

    /// Opens mic hardware for a live `DictationController` (checking the real
    /// `DictationStartOutcome` rather than assuming success) and attaches the VAD
    /// to it, or falls back to the no-mic overlay-only path for callers that don't
    /// supply one (e.g. some existing tests).
    private func beginCaptureOrFallback(
        dictationController: DictationController?,
        overlayController: OverlayController,
        vad: VoiceActivityDetector
    ) async throws {
        guard let dictationController else {
            overlayController.start(partialsProvider: { nil }, levelsProvider: { nil }, isCleaningUp: false)
            return
        }
        let outcome = await dictationController.beginDictation()
        guard outcome == .started else {
            SpeakLog.agentBridge.error(
                "AskUserToolHandler: beginDictation did not start (\(String(describing: outcome), privacy: .public)) — refusing."
            )
            await teardown(overlayController: overlayController)
            throw AskUserError.micUnavailable
        }
        // The answer belongs to the requesting agent, never the focused app.
        await dictationController.engine.suppressPasteForAgentResponse()
        let attached = await dictationController.engine.attachVoiceActivityDetector(vad)
        if !attached {
            SpeakLog.agentBridge.warning(
                "AskUserToolHandler: VAD attach failed (no live AudioCapture) — falling back to the 120s timeout backstop only."
            )
        }
    }

    /// Wires the two `ConversationLoopManager` completion callbacks (turn committed,
    /// interrupted) to resolve `activeContinuation` via `finish(with:overlayController:)`.
    private func wireLoopManagerCallbacks(
        loopManager: ConversationLoopManager,
        overlayController: OverlayController?,
        timeoutTask: Task<Void, Never>
    ) {
        loopManager.onUserTurnCommitted = { [weak self, weak overlayController] userText in
            Task { @MainActor [weak self, weak overlayController] in
                guard let self = self else { return }
                timeoutTask.cancel()
                SpeakLog.agentBridge.info(
                    "AskUserToolHandler: user response committed via continuation (bypassing pasteboard)."
                )
                await self.finish(with: .success(userText), overlayController: overlayController)
            }
        }
        loopManager.onInterrupt = { [weak self, weak overlayController] _ in
            Task { @MainActor [weak self, weak overlayController] in
                guard let self = self else { return }
                timeoutTask.cancel()
                SpeakLog.agentBridge.info("AskUserToolHandler: user interrupted prompt.")
                await self.finish(with: .failure(AskUserError.cancelled), overlayController: overlayController)
            }
        }
    }

    /// Wires the VAD's one-shot transition events into the three existing,
    /// already-tested ConversationLoopManager entry points (§3.1). VAD callbacks
    /// fire on the audio tap's real-time thread, so `onSpeechStart`/`onSpeechEnd`
    /// hop to MainActor before touching `loopManager` (which is @MainActor).
    /// `onBargeIn` deliberately does NOT hop — it calls `stopImmediately()`
    /// directly and synchronously so barge-in latency stays sub-10ms (§6).
    private func wireVADCallbacks(
        vad: VoiceActivityDetector,
        synth: SpeechSynthesizerStream,
        loopManager: ConversationLoopManager,
        dictationController: DictationController?
    ) {
        vad.onSpeechStart = { [weak self, weak loopManager, weak dictationController] in
            Task { @MainActor [weak self, weak loopManager, weak dictationController] in
                guard let self, let loopManager else { return }
                loopManager.handleVADSpeechStarted()
                self.startTranscriptPing(dictationController: dictationController, loopManager: loopManager)
            }
        }
        vad.onSpeechEnd = { [weak self, weak loopManager, weak dictationController] _ in
            Task { @MainActor [weak self, weak loopManager, weak dictationController] in
                guard let self, let loopManager else { return }
                self.stopTranscriptPing()
                // One last transcript push before the commit check, so a fast
                // talker's final words aren't lost to ping-interval granularity.
                if let dictationController {
                    loopManager.handleVADTranscriptUpdated(dictationController.partialText)
                }
                loopManager.handleVADSilenceDetected()
            }
        }
        vad.onBargeIn = { [synth] in
            synth.stopImmediately()
        }
    }

    /// Speaks the prompt through the owned `SpeechSynthesizerStream` (arming
    /// barge-in for its duration), then bootstraps `ConversationLoopManager` into
    /// `.listening` once readback finishes — unless the request has already been
    /// resolved (e.g. the user barged in and committed before readback ended).
    private func speakPromptAndBootstrapListening(
        trimmedPrompt: String,
        loopManager: ConversationLoopManager,
        vad: VoiceActivityDetector,
        synth: SpeechSynthesizerStream,
        settingsStore: SettingsStore
    ) async {
        loopManager.handleAgentSpeakingStarted(speechText: trimmedPrompt)

        var synthConfig = synth.configuration
        synthConfig.voiceIdentifier = settingsStore.ttsVoiceIdentifier
        synthConfig.rate = settingsStore.ttsSpeechRate
        synthConfig.pitch = settingsStore.ttsPitchMultiplier
        synthConfig.volume = settingsStore.ttsVolume
        synthConfig.locale = settingsStore.language
        synth.configuration = synthConfig

        // Arm barge-in: the VAD only emits `.bargeIn` while `isTTSPlaying` is true.
        vad.isTTSPlaying = true
        synth.speak(trimmedPrompt)

        // Non-blocking `speak()` enqueues; wait for playback to actually finish
        // (or be cut short by barge-in / teardown) via the state stream.
        for await state in synth.stateStream {
            if case .idle = state { break }
            if case .stopped = state { break }
        }
        vad.isTTSPlaying = false

        if activeContinuation != nil {
            loopManager.handleAgentSpeakingFinished()
            // Bootstrap the transition into `.listening` — CLM has no public
            // "start listening" entry point other than this one, and calling it
            // from `.idle` is exactly what `startListening` requires. When the
            // user's *real* speech is later detected, `vad.onSpeechStart` calls
            // this again; CLM is already `.listening` by then, so it just resets
            // the silence timer (see `handleVADSpeechStarted`'s `.listening` case).
            loopManager.handleVADSpeechStarted()
        }
    }

    /// Cancel active in-flight request if any.
    func cancel(overlayController: OverlayController?) {
        guard activeContinuation != nil else { return }
        SpeakLog.agentBridge.info("AskUserToolHandler: explicitly cancelling active request.")
        Task { @MainActor in
            await self.finish(with: .failure(AskUserError.cancelled), overlayController: overlayController)
        }
    }

    // MARK: - Private Helpers

    private func startTranscriptPing(
        dictationController: DictationController?,
        loopManager: ConversationLoopManager
    ) {
        guard let dictationController else { return }
        transcriptPingTask?.cancel()
        transcriptPingTask = Task { @MainActor [weak dictationController, weak loopManager] in
            while !Task.isCancelled {
                guard let dictationController, let loopManager else { return }
                loopManager.handleVADTranscriptUpdated(dictationController.partialText)
                do {
                    try await Task.sleep(for: .milliseconds(250))
                } catch {
                    return
                }
            }
        }
    }

    private func stopTranscriptPing() {
        transcriptPingTask?.cancel()
        transcriptPingTask = nil
    }

    /// Tears down everything this request constructed — VAD attachment, synthesizer,
    /// ping task, loop manager, overlay — and closes the mic on every exit path
    /// (normal completion, cancel, timeout, error, interrupt). Idempotent: safe to
    /// call after `activeContinuation` has already been cleared.
    private func teardown(overlayController: OverlayController?) async {
        stopTranscriptPing()
        currentSynth?.stopImmediately()
        currentSynth = nil
        currentVAD = nil

        if let dictationController = currentDictationController {
            await dictationController.engine.attachVoiceActivityDetector(nil)
            // Mirrors `cliRequestInput`'s pattern (DictationController+CLI.swift):
            // only stop if this request's session is still the live one — an
            // out-of-band stop (hotkey, mute) may already be tearing it down.
            if dictationController.icon == .listening {
                await dictationController.endDictation()
            }
        }
        currentDictationController = nil

        if let loopManager = currentLoopManager {
            loopManager.resetToIdle()
            self.currentLoopManager = nil
        }

        if let overlayController = overlayController {
            overlayController.overlayModel.conversationLoopManager = nil
            overlayController.stop()
        }
    }

    private func finish(
        with result: Result<String, Error>,
        overlayController: OverlayController?
    ) async {
        guard let continuation = activeContinuation else { return }
        self.activeContinuation = nil

        await teardown(overlayController: overlayController)

        switch result {
        case .success(let text):
            continuation.resume(returning: text)
        case .failure(let error):
            continuation.resume(throwing: error)
        }
    }

    private func parseMode(_ raw: String?) -> ConversationMode {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return .fullDuplex
        }
        switch raw.lowercased() {
        case "pushtotalk", "push_to_talk":
            return .pushToTalk
        case "gatedturn", "gated_turn":
            return .gatedTurn
        default:
            return .fullDuplex
        }
    }
}
