// SpeakCore/Cleanup/ProviderPreset.swift
//
// Pure-data provider settings for the opt-in OpenAI-compatible cleanup
// engines (roadmap V01-2). Everything in this file is networking-free —
// no `import SpeakLLM`, no URL/Keychain symbols — so it can live in
// `SpeakCore` and be persisted directly by `SettingsStore` inside the
// `CleanupEngine.openAICompatible(preset:model:)` case.
//
// LAYERING [decision]:
//   `ProviderPreset` is settings *data* (which endpoint family, which auth
//   style, which default model). The `LLMCleaning` conformer that acts on it
//   (`OpenAICompatibleCleaner`) and the `CleanupEngine → cleaner` factory
//   (`defaultCleaner(for:)`) live in the App target — above the `LLMCleaning`
//   protocol seam — because they construct `SpeakLLM` types
//   (`OpenAICompatibleClient`, `LLMKeychainStore`). `SpeakCore` itself links
//   zero SpeakLLM code, which keeps `verify-moat`'s "no networking symbols in
//   SpeakCore" claim honest at the link-graph level, not just the grep level.
//
//   `LLMAuthStyle` moved here from `SpeakLLM/OpenAICompatibleClient.swift`:
//   it is the Codable payload of `ProviderPreset.custom`, so it must live at
//   or below the persisting module. `SpeakLLM` now links `SpeakCore` for it —
//   the reverse of the old (violating) edge.

import Foundation

// MARK: - Auth style

/// How the API key (if any) is attached to an OpenAI-compatible request.
/// Persisted inside `ProviderPreset.custom` — raw values are wire-stable.
/// `SpeakLLM.OpenAICompatibleClient` consumes this same type when building
/// the actual HTTP request.
public enum LLMAuthStyle: String, Codable, Sendable, Equatable {
    /// No credential sent (Ollama — loopback, no account).
    case none
    /// `Authorization: Bearer <key>` — OpenAI, Groq, OpenRouter.
    case bearer
    /// `api-subscription-key: <key>` — Sarvam AI.
    case subscriptionKey
}

// MARK: - Provider preset

/// The six built-in `OpenAICompatibleCleaner` configurations (roadmap V01-2).
/// Pure data — no networking symbols — so this type can live in `SpeakCore`
/// and be persisted directly by `SettingsStore`.
public enum ProviderPreset: Codable, Sendable, Equatable, Hashable {
    /// Local Ollama server. Loopback-only; no API key. **v0.1 default alternative.**
    case ollama
    /// Sarvam AI's hosted LLM (`api-subscription-key` auth).
    case sarvamLLM
    /// OpenAI hosted API (`Authorization: Bearer` auth).
    case openAI
    /// Groq hosted API (`Authorization: Bearer` auth).
    case groq
    /// OpenRouter hosted API (`Authorization: Bearer` auth).
    case openRouter
    /// A fully user-entered endpoint: base URL + auth style are user choices.
    case custom(baseURL: URL, authStyle: LLMAuthStyle)

    /// Loopback-pinned Ollama base URL. Never derived from user input — this is
    /// the moat's "no egress for the local preset" guarantee. [decision V01-2]
    private static let ollamaBaseURL = URL(string: "http://127.0.0.1:11434/v1")
    private static let sarvamBaseURL = URL(string: "https://api.sarvam.ai/v1")
    private static let openAIBaseURL = URL(string: "https://api.openai.com/v1")
    private static let groqBaseURL = URL(string: "https://api.groq.com/openai/v1")
    private static let openRouterBaseURL = URL(string: "https://openrouter.ai/api/v1")

    /// `nil` only for a malformed `.custom` URL (the Settings UI validates
    /// before saving; the built-in presets' literals always parse).
    public var baseURL: URL? {
        switch self {
        case .ollama:      return Self.ollamaBaseURL
        case .sarvamLLM:   return Self.sarvamBaseURL
        case .openAI:      return Self.openAIBaseURL
        case .groq:        return Self.groqBaseURL
        case .openRouter:  return Self.openRouterBaseURL
        case .custom(let baseURL, _): return baseURL
        }
    }

    public var authStyle: LLMAuthStyle {
        switch self {
        case .ollama:                    return .none
        case .sarvamLLM:                 return .subscriptionKey
        case .openAI, .groq, .openRouter: return .bearer
        case .custom(_, let authStyle):  return authStyle
        }
    }

    /// The preset's recommended default model tag. Empty for `.openRouter`/`.custom`,
    /// where the user must choose (roadmap V01-2 table).
    public var defaultModel: String {
        switch self {
        case .ollama:     return "qwen2.5:3b"
        case .sarvamLLM:  return "sarvam-30b"
        case .openAI:     return "gpt-4o-mini"
        case .groq:       return "llama3-8b-8192"
        case .openRouter: return ""
        case .custom:     return ""
        }
    }

    /// Whether this preset needs a user-supplied API key before it can run.
    public var requiresAPIKey: Bool {
        switch self {
        case .ollama:                    return false
        case .sarvamLLM, .openAI, .groq, .openRouter: return true
        case .custom(_, let authStyle):  return authStyle != .none
        }
    }

    /// Stable identifier: used in `LLMCleaning.id`, the Keychain account name,
    /// and Settings persistence.
    public var id: String {
        switch self {
        case .ollama:      return "ollama"
        case .sarvamLLM:   return "sarvam"
        case .openAI:      return "openai"
        case .groq:        return "groq"
        case .openRouter:  return "openrouter"
        case .custom(let baseURL, _): return "custom:\(baseURL.absoluteString)"
        }
    }

    /// The user-facing label for the Settings preset picker.
    public var displayName: String {
        switch self {
        case .ollama:      return "Ollama (local server)"
        case .sarvamLLM:   return "Sarvam AI"
        case .openAI:      return "OpenAI"
        case .groq:        return "Groq"
        case .openRouter:  return "OpenRouter"
        case .custom:      return "Custom endpoint"
        }
    }
}
