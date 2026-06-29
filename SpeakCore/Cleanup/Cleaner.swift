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
    /// (`CleanupStyle`) crossed with a polish *intensity* (`CleanupLevel`), plus
    /// an optional list of proper nouns / specialist spellings the model must
    /// preserve verbatim (`customVocabulary`). `SpeakEngine.newSession()` derives
    /// all three from `SettingsStore` at call time (the H1 pattern), so any
    /// pane change applies on the next dictation with no engine restart. The
    /// legacy single-axis cases above remain for direct callers and tests.
    ///
    /// `customVocabulary` is `[]` by default so callers that do not supply it
    /// (unit tests, legacy call sites) produce the same prompt as before.
    case styled(CleanupStyle, CleanupLevel, customVocabulary: [String] = [])

    /// Command Mode (Wave D): apply a spoken `instruction` to the text passed to
    /// `clean(_:mode:)`. The text is the user's highlighted selection; the instruction
    /// is what they said (e.g. "make this more concise", "translate to Polish"). The LLM
    /// returns the transformed selection. The live read/replace of the selection happens
    /// via the Accessibility API at the app layer — this case is the AI-transform core,
    /// reused from the same on-device cleaner.
    case command(instruction: String)

    /// Profile Engine (PT-1 wiring): run a resolved `Profile`'s system prompt over
    /// the transcript. `level` is the cross-profile rewrite-intensity modifier
    /// (carried from the user's cleanup level); `category` is an optional Agent-specific
    /// sub-category that appends a fragment (applies only to Agent destination);
    /// `customVocabulary` preserves the user's proper-noun spellings. The cleaner
    /// renders this via `PromptBuilder`. `SpeakEngine.newSession()` builds this when
    /// the frontmost app matches a profile's `targetApps`; the global default stays
    /// on `.styled` for now.
    case profile(Profile, level: CleanupLevel, category: AgentCategory = .task, customVocabulary: [String] = [])
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

/// The neat-writing *intensity* — how aggressively the transcript is rewritten.
///
/// **W4.1 transparency moat** — 4-level intensity ladder matching the market
/// pattern (Wispr Auto Cleanup, competitor-research finding #4):
///   - `.none`   → raw passthrough; no model call. `SpeakEngine.newSession()` skips
///                 the cleaner entirely when this is selected, exactly as if
///                 `cleanupEnabled == false`. [decision: "no cleanup" is a level,
///                 not a boolean toggle, so the user chooses all-or-nothing vs.
///                 a specific intensity from one picker.]
///   - `.light`  → filler-word removal + punctuation only.
///   - `.medium` → + sentence tightening (the v0 balanced baseline).
///   - `.high`   → + restructuring and paragraph breaks.
///
/// **rawValue migration note:** the previous cases (basic/balanced/thorough) are
/// replaced by (light/medium/high). Stored rawValues from an earlier build will not
/// decode, and SettingsStore falls back to the new default `.medium`. This is
/// acceptable pre-release. [decision: clean break, no migration shim in v0]
///
/// **Persistence:** stored as `rawValue` String in `UserDefaults`. Default: `.medium`.
/// **CaseIterable order == picker order** (None first, High last).
public enum CleanupLevel: String, Codable, Sendable, CaseIterable, Equatable {
    /// No AI cleanup — raw transcript is pasted. No model call is made.
    case none
    /// Light: filler-word removal and punctuation only. Minimal rewriting.
    case light
    /// Medium: filler removal + punctuation + sentence tightening. The balanced baseline.
    case medium
    /// High: filler removal + punctuation + tightening + restructuring + paragraphs.
    case high

    /// The user-facing picker label. [decision: plain English, not "Basic/Thorough"]
    public var displayName: String {
        switch self {
        case .none:   return "None"
        case .light:  return "Light"
        case .medium: return "Medium"
        case .high:   return "High"
        }
    }

    /// One-line description shown below the picker label in Settings. [decision]
    public var levelDescription: String {
        switch self {
        case .none:   return "Paste raw transcript, no AI changes"
        case .light:  return "Remove filler words and add punctuation"
        case .medium: return "Tighten sentences and fix grammar"
        case .high:   return "Restructure and add paragraph breaks"
        }
    }
}
