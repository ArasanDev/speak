// SpeakCore/Conversation/ConversationState.swift
//
// Defines states for the Bidirectional Voice Architecture (Layer 2).
//
// States:
//   - `.idle`: System is ready, waiting for user input.
//   - `.listening(userText:)`: System is capturing user speech, accumulating transcript.
//   - `.processing(prompt:)`: System is processing the prompt (LLM / Voice Actions / Agent).
//   - `.agentSpeaking(speechText:progress:)`: Agent is producing speech via TTS readback (progress 0.0...1.0).
//   - `.interrupted(partialUserText:)`: Turn was interrupted by user speech or manual override.
//   - `.paused`: Conversation loop is suspended (e.g., hardware/software mute).

import Foundation

/// Primary state machine states for the bidirectional voice conversation loop.
public enum ConversationState: Sendable, Equatable, Hashable {
    /// System idle, waiting for speech or trigger.
    case idle

    /// User is actively speaking or dictating.
    /// - Parameter userText: The accumulated partial transcript.
    case listening(userText: String)

    /// System is processing the committed prompt.
    /// - Parameter prompt: The finalized user prompt being processed.
    case processing(prompt: String)

    /// Agent is speaking audio response via TTS.
    /// - Parameters:
    ///   - speechText: The text being read back.
    ///   - progress: Playback progress normalized from 0.0 to 1.0.
    case agentSpeaking(speechText: String, progress: Double)

    /// Interrupted mid-speech or mid-processing.
    /// - Parameter partialUserText: Any partial speech detected during interruption.
    case interrupted(partialUserText: String)

    /// Conversation loop is paused (e.g. muted or deactivated).
    case paused

    // MARK: - Helper Properties

    /// Whether the state is `.idle`.
    public var isIdle: Bool {
        if case .idle = self { return true }
        return false
    }

    /// Whether the state is `.listening`.
    public var isListening: Bool {
        if case .listening = self { return true }
        return false
    }

    /// Whether the state is `.processing`.
    public var isProcessing: Bool {
        if case .processing = self { return true }
        return false
    }

    /// Whether the state is `.agentSpeaking`.
    public var isAgentSpeaking: Bool {
        if case .agentSpeaking = self { return true }
        return false
    }

    /// Whether the state is `.interrupted`.
    public var isInterrupted: Bool {
        if case .interrupted = self { return true }
        return false
    }

    /// Whether the state is `.paused`.
    public var isPaused: Bool {
        if case .paused = self { return true }
        return false
    }

    /// Extracted user text if in `.listening` or `.interrupted` state, else nil.
    public var currentText: String? {
        switch self {
        case .listening(let userText):
            return userText
        case .interrupted(let partialUserText):
            return partialUserText
        case .processing(let prompt):
            return prompt
        case .agentSpeaking(let speechText, _):
            return speechText
        case .idle, .paused:
            return nil
        }
    }
}
