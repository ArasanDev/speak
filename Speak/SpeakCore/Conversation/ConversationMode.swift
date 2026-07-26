// SpeakCore/Conversation/ConversationMode.swift
//
// Defines modes for the Bidirectional Voice Architecture (Layer 2).
//
// Modes:
//   - `.fullDuplex`: Hands-free Voice Activity Detection (VAD). Continuous listen/speak loop with automated turn detection.
//   - `.pushToTalk`: Manual trigger loop. User explicitly starts and ends dictation/speech turns.
//   - `.gatedTurn`: Strict turn-taking loop. System requires explicit turn release or threshold trigger before processing.

import Foundation

/// Modes controlling turn-taking and voice interaction behavior in the conversation loop.
public enum ConversationMode: String, Sendable, Codable, Equatable, Hashable, CaseIterable {
    /// Hands-free Voice Activity Detection (VAD).
    /// Continuous audio processing with automatic silence detection driving turn transitions.
    case fullDuplex

    /// Push-To-Talk interaction.
    /// User manually starts and stops input capture (e.g., press-and-hold or toggle key).
    case pushToTalk

    /// Gated turn-taking interaction.
    /// Turns are strictly sequential; system waits for explicit turn-completion signals.
    case gatedTurn

    /// Human-readable display label for UI representation.
    public var label: String {
        switch self {
        case .fullDuplex:
            return "Full Duplex (Hands-Free)"
        case .pushToTalk:
            return "Push to Talk"
        case .gatedTurn:
            return "Gated Turn"
        }
    }
}
