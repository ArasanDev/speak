// SpeakCore/Conversation/ConversationLoopManager.swift
//
// Layer 2 Bidirectional Voice State Machine and Loop Manager.
//
// Responsibilities:
//   - `@MainActor` state machine managing `ConversationState` transitions.
//   - Manages mode (`.fullDuplex`, `.pushToTalk`, `.gatedTurn`).
//   - Turn-taking timers (silence detection timeout, max listening duration, processing timeout).
//   - VAD signal responses (speech start, transcript stream updates, silence detection).
//   - Manual override handling (Space for Mute, Escape for Interrupt, Mode switching).
//   - AsyncStreams for thread-safe UI observation.

import Combine
import Foundation
import os

/// Discrete events emitted by the conversation loop for UI or integration observation.
public enum ConversationEvent: Sendable, Equatable {
    /// State machine transitioned to a new state.
    case stateChanged(ConversationState)
    /// Conversation mode changed.
    case modeChanged(ConversationMode)
    /// User turn committed with prompt text.
    case userTurnCommitted(prompt: String)
    /// Agent response or TTS was interrupted.
    case agentInterrupted(partialUserText: String)
    /// VAD silence timeout triggered turn commitment.
    case silenceTimeoutTriggered
    /// Max listening duration reached, forcing turn commitment.
    case maxListeningDurationReached
    /// Hardware/software mute state changed.
    case mutedStateChanged(isMuted: Bool)
}

/// `@MainActor` state machine for bidirectional voice conversation lifecycle.
@MainActor
public final class ConversationLoopManager: ObservableObject {

    // MARK: - Published State

    /// Current conversation state.
    @Published public private(set) var state: ConversationState {
        didSet {
            guard state != oldValue else { return }
            SpeakLog.conversation.info("Conversation state transitioned: \(String(describing: oldValue), privacy: .public) -> \(String(describing: self.state), privacy: .public)")
            notifyStateChanged(state)
        }
    }

    /// Current conversation mode.
    @Published public private(set) var mode: ConversationMode {
        didSet {
            guard mode != oldValue else { return }
            SpeakLog.conversation.info("Conversation mode changed to: \(self.mode.rawValue, privacy: .public)")
            notifyModeChanged(mode)
        }
    }

    /// Mute override state (Space key / hardware mute).
    @Published public private(set) var isMuted: Bool {
        didSet {
            guard isMuted != oldValue else { return }
            SpeakLog.conversation.info("Mute state set to: \(self.isMuted, privacy: .public)")
            notifyEvent(.mutedStateChanged(isMuted: isMuted))
        }
    }

    // MARK: - Configuration Parameters

    /// Silence timeout in seconds for `.fullDuplex` VAD auto-commit.
    public var silenceTimeoutDuration: TimeInterval

    /// Maximum duration user can speak before turn auto-commits.
    public var maxListeningDuration: TimeInterval

    /// Maximum processing timeout before falling back to idle.
    public var processingTimeoutDuration: TimeInterval

    // MARK: - Callbacks / Delegate Injection

    /// Optional handler invoked when user turn is committed into a prompt.
    public var onUserTurnCommitted: ((String) -> Void)?

    /// Optional handler invoked when agent speech or processing is interrupted.
    public var onInterrupt: ((String) -> Void)?

    // MARK: - Timer Tasks

    private var silenceTimerTask: Task<Void, Never>?
    private var listeningTimeoutTask: Task<Void, Never>?
    private var processingTimeoutTask: Task<Void, Never>?

    // MARK: - Observation Continuations

    private var stateContinuations: [UUID: AsyncStream<ConversationState>.Continuation] = [:]
    private var modeContinuations: [UUID: AsyncStream<ConversationMode>.Continuation] = [:]
    private var eventContinuations: [UUID: AsyncStream<ConversationEvent>.Continuation] = [:]

    // MARK: - Initialization

    /// Initialize the Conversation Loop Manager.
    ///
    /// - Parameters:
    ///   - initialMode: Initial conversation mode (default: `.fullDuplex`).
    ///   - initialMuted: Initial mute status (default: `false`).
    ///   - silenceTimeoutDuration: Silence duration (seconds) before committing turn in `.fullDuplex` (default: 1.5s).
    ///   - maxListeningDuration: Max user turn duration (seconds) (default: 30.0s).
    ///   - processingTimeoutDuration: Max agent processing duration (seconds) (default: 60.0s).
    public init(
        initialMode: ConversationMode = .fullDuplex,
        initialMuted: Bool = false,
        silenceTimeoutDuration: TimeInterval = 1.5,
        maxListeningDuration: TimeInterval = 30.0,
        processingTimeoutDuration: TimeInterval = 60.0
    ) {
        self.mode = initialMode
        self.isMuted = initialMuted
        self.silenceTimeoutDuration = silenceTimeoutDuration
        self.maxListeningDuration = maxListeningDuration
        self.processingTimeoutDuration = processingTimeoutDuration
        self.state = initialMuted ? .paused : .idle

        SpeakLog.conversation.info("ConversationLoopManager initialized with mode=\(initialMode.rawValue, privacy: .public), muted=\(initialMuted, privacy: .public)")
    }

    deinit {
        silenceTimerTask?.cancel()
        listeningTimeoutTask?.cancel()
        processingTimeoutTask?.cancel()
        for continuation in stateContinuations.values { continuation.finish() }
        for continuation in modeContinuations.values { continuation.finish() }
        for continuation in eventContinuations.values { continuation.finish() }
    }

    // MARK: - Streams for UI Observation

    /// Thread-safe stream emitting state updates.
    public var stateStream: AsyncStream<ConversationState> {
        AsyncStream { continuation in
            let id = UUID()
            stateContinuations[id] = continuation
            continuation.yield(state)
            continuation.onTermination = { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.stateContinuations.removeValue(forKey: id)
                }
            }
        }
    }

    /// Thread-safe stream emitting mode updates.
    public var modeStream: AsyncStream<ConversationMode> {
        AsyncStream { continuation in
            let id = UUID()
            modeContinuations[id] = continuation
            continuation.yield(mode)
            continuation.onTermination = { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.modeContinuations.removeValue(forKey: id)
                }
            }
        }
    }

    /// Thread-safe stream emitting discrete conversation events.
    public var eventStream: AsyncStream<ConversationEvent> {
        AsyncStream { continuation in
            let id = UUID()
            eventContinuations[id] = continuation
            continuation.onTermination = { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.eventContinuations.removeValue(forKey: id)
                }
            }
        }
    }

    // MARK: - VAD & Speech Signal Handling

    /// Called when Voice Activity Detection detects the user started speaking.
    public func handleVADSpeechStarted() {
        guard !isMuted, state != .paused else {
            SpeakLog.conversation.debug("VAD speech start ignored: muted or paused.")
            return
        }

        switch state {
        case .agentSpeaking(let speechText, _):
            // User speech interrupts agent speaking!
            SpeakLog.conversation.info("User speech started during agentSpeaking — triggering interrupt.")
            let partialText = speechText
            state = .interrupted(partialUserText: "")
            notifyEvent(.agentInterrupted(partialUserText: partialText))
            onInterrupt?(partialText)
            startListening(initialText: "")

        case .processing(let prompt):
            if mode == .fullDuplex {
                SpeakLog.conversation.info("User speech started during processing in fullDuplex — triggering interrupt.")
                state = .interrupted(partialUserText: "")
                notifyEvent(.agentInterrupted(partialUserText: prompt))
                onInterrupt?(prompt)
                startListening(initialText: "")
            }

        case .idle, .interrupted:
            startListening(initialText: "")

        case .listening:
            // Already listening — reset silence timer.
            if mode == .fullDuplex {
                resetSilenceTimer()
            }
        case .paused:
            break
        }
    }

    /// Called when streaming transcript is updated from STT.
    /// - Parameter text: Updated user transcript.
    public func handleVADTranscriptUpdated(_ text: String) {
        guard !isMuted, state != .paused else { return }

        switch state {
        case .listening, .interrupted, .idle:
            state = .listening(userText: text)
            if mode == .fullDuplex {
                resetSilenceTimer()
            }
        case .processing, .agentSpeaking, .paused:
            break
        }
    }

    /// Called when VAD detects silence or user finishes utterance.
    public func handleVADSilenceDetected() {
        guard !isMuted, state != .paused else { return }

        guard case .listening(let userText) = state else { return }

        let trimmed = userText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            SpeakLog.conversation.info("VAD silence detected with empty text -> returning to idle.")
            cancelListeningTimers()
            state = .idle
        } else {
            SpeakLog.conversation.info("VAD silence detected -> committing user turn.")
            notifyEvent(.silenceTimeoutTriggered)
            commitUserTurn(prompt: trimmed)
        }
    }

    /// Explicitly commit user turn (for Push-To-Talk release or gated turn submit).
    public func commitUserTurn(prompt: String? = nil) {
        cancelListeningTimers()

        let finalPrompt: String
        if let explicitPrompt = prompt {
            finalPrompt = explicitPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        } else if case .listening(let text) = state {
            finalPrompt = text.trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            finalPrompt = ""
        }

        guard !finalPrompt.isEmpty else {
            SpeakLog.conversation.info("commitUserTurn called with empty text -> returning to idle.")
            state = .idle
            return
        }

        state = .processing(prompt: finalPrompt)
        notifyEvent(.userTurnCommitted(prompt: finalPrompt))
        onUserTurnCommitted?(finalPrompt)
        startProcessingTimeoutTimer()
    }

    // MARK: - Agent State Transitions

    /// Transition to processing state with an explicit prompt.
    /// - Parameter prompt: The prompt being processed.
    public func transitionToProcessing(prompt: String) {
        cancelListeningTimers()
        state = .processing(prompt: prompt)
        startProcessingTimeoutTimer()
    }

    /// Called when agent speech readback begins.
    /// - Parameter speechText: Text being spoken by agent.
    public func handleAgentSpeakingStarted(speechText: String) {
        cancelProcessingTimeoutTimer()
        state = .agentSpeaking(speechText: speechText, progress: 0.0)
    }

    /// Called to update agent speech progress.
    /// - Parameters:
    ///   - speechText: Text being spoken.
    ///   - progress: Progress value between 0.0 and 1.0.
    public func handleAgentSpeakingProgress(speechText: String, progress: Double) {
        guard case .agentSpeaking = state else { return }
        let clampedProgress = min(max(progress, 0.0), 1.0)
        state = .agentSpeaking(speechText: speechText, progress: clampedProgress)
    }

    /// Called when agent speech readback finishes normally.
    public func handleAgentSpeakingFinished() {
        guard case .agentSpeaking = state else { return }
        SpeakLog.conversation.info("Agent speaking finished -> returning to idle.")
        state = .idle
    }

    // MARK: - Manual Overrides (Mute, Interrupt, Mode Switch)

    /// Toggle software/hardware mute override (Space key).
    /// - Returns: Updated mute state.
    @discardableResult
    public func toggleMute() -> Bool {
        setMuted(!isMuted)
        return isMuted
    }

    /// Set mute status explicitly.
    /// - Parameter muted: Target mute state.
    public func setMuted(_ muted: Bool) {
        guard isMuted != muted else { return }
        isMuted = muted

        if muted {
            SpeakLog.conversation.info("Manual override: Mute enabled -> transition to .paused")
            cancelAllTimers()

            if case .agentSpeaking(let speechText, _) = state {
                onInterrupt?(speechText)
            } else if case .listening(let userText) = state {
                onInterrupt?(userText)
            }

            state = .paused
        } else {
            SpeakLog.conversation.info("Manual override: Mute disabled -> transition to .idle")
            if state == .paused {
                state = .idle
            }
        }
    }

    /// Manual interrupt override (Escape key / user action).
    /// Immediately interrupts agent speaking, processing, or active turn.
    public func handleInterrupt() {
        SpeakLog.conversation.info("Manual override: Interrupt requested.")

        switch state {
        case .agentSpeaking(let speechText, _):
            cancelAllTimers()
            state = .interrupted(partialUserText: "")
            notifyEvent(.agentInterrupted(partialUserText: speechText))
            onInterrupt?(speechText)

        case .processing(let prompt):
            cancelAllTimers()
            state = .interrupted(partialUserText: "")
            notifyEvent(.agentInterrupted(partialUserText: prompt))
            onInterrupt?(prompt)

        case .listening(let userText):
            cancelListeningTimers()
            state = .interrupted(partialUserText: userText)
            notifyEvent(.agentInterrupted(partialUserText: userText))
            onInterrupt?(userText)

        case .idle, .interrupted, .paused:
            break
        }
    }

    /// Switch conversation mode (`.fullDuplex`, `.pushToTalk`, `.gatedTurn`).
    /// - Parameter newMode: Target mode.
    public func setMode(_ newMode: ConversationMode) {
        guard mode != newMode else { return }
        mode = newMode

        if newMode != .fullDuplex {
            silenceTimerTask?.cancel()
            silenceTimerTask = nil
        } else if case .listening = state {
            resetSilenceTimer()
        }
    }

    /// Reset state to idle explicitly.
    public func resetToIdle() {
        cancelAllTimers()
        if !isMuted {
            state = .idle
        } else {
            state = .paused
        }
    }

    // MARK: - Private Timer Helpers

    private func startListening(initialText: String) {
        cancelAllTimers()
        state = .listening(userText: initialText)

        if mode == .fullDuplex {
            resetSilenceTimer()
        }

        listeningTimeoutTask = Task { @MainActor [weak self] in
            guard let self = self else { return }
            do {
                try await Task.sleep(nanoseconds: UInt64(self.maxListeningDuration * 1_000_000_000))
                guard !Task.isCancelled, case .listening = self.state else { return }
                SpeakLog.conversation.info("Max listening duration reached -> auto-committing turn.")
                self.notifyEvent(.maxListeningDurationReached)
                self.handleVADSilenceDetected()
            } catch {
                // Task cancelled
            }
        }
    }

    private func resetSilenceTimer() {
        silenceTimerTask?.cancel()
        guard mode == .fullDuplex else { return }

        silenceTimerTask = Task { @MainActor [weak self] in
            guard let self = self else { return }
            do {
                try await Task.sleep(nanoseconds: UInt64(self.silenceTimeoutDuration * 1_000_000_000))
                guard !Task.isCancelled, case .listening = self.state else { return }
                SpeakLog.conversation.info("Silence timeout reached -> auto-committing turn.")
                self.handleVADSilenceDetected()
            } catch {
                // Task cancelled
            }
        }
    }

    private func startProcessingTimeoutTimer() {
        processingTimeoutTask?.cancel()

        processingTimeoutTask = Task { @MainActor [weak self] in
            guard let self = self else { return }
            do {
                try await Task.sleep(nanoseconds: UInt64(self.processingTimeoutDuration * 1_000_000_000))
                guard !Task.isCancelled, case .processing = self.state else { return }
                SpeakLog.conversation.error("Processing timeout reached (\(self.processingTimeoutDuration)s) -> resetting to idle.")
                self.state = .idle
            } catch {
                // Task cancelled
            }
        }
    }

    private func cancelListeningTimers() {
        silenceTimerTask?.cancel()
        silenceTimerTask = nil
        listeningTimeoutTask?.cancel()
        listeningTimeoutTask = nil
    }

    private func cancelProcessingTimeoutTimer() {
        processingTimeoutTask?.cancel()
        processingTimeoutTask = nil
    }

    private func cancelAllTimers() {
        cancelListeningTimers()
        cancelProcessingTimeoutTimer()
    }

    // MARK: - Event Notification Helpers

    private func notifyStateChanged(_ newState: ConversationState) {
        notifyEvent(.stateChanged(newState))
        for continuation in stateContinuations.values {
            continuation.yield(newState)
        }
    }

    private func notifyModeChanged(_ newMode: ConversationMode) {
        notifyEvent(.modeChanged(newMode))
        for continuation in modeContinuations.values {
            continuation.yield(newMode)
        }
    }

    private func notifyEvent(_ event: ConversationEvent) {
        for continuation in eventContinuations.values {
            continuation.yield(event)
        }
    }
}
