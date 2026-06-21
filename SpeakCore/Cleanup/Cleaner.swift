// SpeakCore/Cleanup/Cleaner.swift
//
// The AI neat-writing seam (v0 CORE — not optional). Every cleanup engine
// (Apple Foundation Models in v0, Ollama/MLX later) conforms to `LLMCleaning`.
// Signatures are verbatim from `docs/architecture.md` §6.

import Foundation

public protocol LLMCleaning: Sendable {
    var id: String { get }
    var isAvailable: Bool { get async }
    func clean(_ text: String, mode: CleanupMode) async throws -> String
}

public enum CleanupMode: Sendable {
    case fillersOnly
    case punctuation
    case codeAware
    case toneAdjust
    case translate(Locale)
    /// The user-facing neat-writing mode (Wave B): a writing *voice*
    /// (`CleanupStyle`) crossed with a polish *intensity* (`CleanupLevel`).
    /// `SpeakEngine.newSession()` derives this from `SettingsStore` at call time
    /// (the H1 pattern), so a Style-pane change applies on the next dictation with
    /// no engine restart. The legacy single-axis cases above remain for direct
    /// callers and tests.
    case styled(CleanupStyle, CleanupLevel)
}

/// The neat-writing *voice* — how the cleaned text should read. User-facing in the
/// dashboard Style pane (acceleration-plan.md Wave B). `CaseIterable` order ==
/// the picker order; `.default` is the behavior-neutral baseline (≈ legacy
/// `.punctuation`).
public enum CleanupStyle: String, Codable, Sendable, CaseIterable, Equatable {
    case `default`
    case professional
    case casual
    case code
    case email

    /// The picker label.
    public var displayName: String {
        switch self {
        case .default:      return "Default"
        case .professional: return "Professional"
        case .casual:       return "Casual"
        case .code:         return "Code"
        case .email:        return "Email"
        }
    }
}

/// The neat-writing *intensity* — how aggressively the transcript is rewritten. A
/// friendly abstraction over prompt strength (acceleration-plan.md Wave B).
/// `.balanced` is the default.
public enum CleanupLevel: String, Codable, Sendable, CaseIterable, Equatable {
    case basic
    case balanced
    case thorough

    /// The picker label.
    public var displayName: String {
        switch self {
        case .basic:    return "Basic"
        case .balanced: return "Balanced"
        case .thorough: return "Thorough"
        }
    }
}
