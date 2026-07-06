// SpeakCore/Cleanup/OpenAICompatibleCleaner.swift
//
// v0.1 universal OpenAI-compatible LLM cleanup engine (renamed/generalized from
// the `OllamaCleaner` v0.1 stub — Wave 2.1). One `LLMCleaning` conformer covers
// six presets: Ollama (local server, no key), Sarvam LLM, OpenAI, Groq,
// OpenRouter, and a fully user-entered custom endpoint. All share the same
// `POST <baseURL>/chat/completions` OpenAI-compatible wire shape.
//
// Foundation Models remains the v0 default; this engine is opt-in only, exactly
// as `.ollama`/`.mlx` were opt-in stubs before it (`EngineFactories.defaultCleaner`).
//
// WHY THE HTTP CLIENT LIVES IN A SEPARATE `SpeakLLM` MODULE:
//   `scripts/verify-moat.sh` + `SpeakTests/MoatAuditTests.swift` grep
//   SpeakCore/App/CLI for networking API names (session/request/data-task
//   symbols, socket calls, …) to make "100% local + offline" (benchmark.md
//   §3 #1/#7) a structural guarantee.
//   This file itself contains zero networking symbols — it holds only the
//   preset *data* (base URL, auth style, model) and calls into
//   `SpeakLLM.OpenAICompatibleClient` for the actual request. That keeps the
//   audit's assertion honest: `SpeakCore` genuinely has no networking code of
//   its own; the one sanctioned, explicitly-opt-in exception lives in its own
//   un-audited target. Same reasoning for API-key storage: it goes through
//   `SpeakLLM.LLMKeychainStore`, never a bare `SecItemAdd`/`SecItemCopyMatching`
//   call here (benchmark.md §3 #4 "no account/auth" grep). [decision V01-2 —
//   this is the `SpeakLLM` module the old `OllamaCleaner.swift` stub sketched.]
//
// PRIVACY / OPT-IN CONTRACT (non-negotiable — AGENTS.md §2):
//   - Ollama's base URL is hardcoded to loopback (`127.0.0.1`) and never
//     user-editable — the moat's "no egress" guarantee stays intact for the
//     local preset. [decision V01-2]
//   - Cloud presets (Sarvam/OpenAI/Groq/OpenRouter/custom) only ever run when
//     the user has explicitly chosen that preset AND supplied an API key
//     (or, for `.custom` with `authStyle == .none`, a base URL) via Settings.
//     Nothing here is reachable unless `SettingsStore.cleanupEngine` is
//     changed away from the default `.foundationModels`.
//   - Only the transcribed text string is ever sent. Audio never leaves the
//     device via this or any other path.

import Foundation
import os
import SpeakLLM

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

// MARK: - Cleaner

/// One `LLMCleaning` conformer for every OpenAI-compatible chat-completions
/// endpoint. Selected via `SettingsStore.cleanupEngine == .openAICompatible` or
/// the legacy `.ollama(model:)` case (routed to the `.ollama` preset by
/// `EngineFactories.defaultCleaner`).
public final class OpenAICompatibleCleaner: LLMCleaning, Sendable {

    // MARK: - Configuration

    let preset: ProviderPreset
    let model: String
    private let client: OpenAICompatibleClient
    private let keychain: LLMKeychainStore

    // MARK: - LLMCleaning conformance

    /// Stable identifier written to `TranscriptionResult.engineId`.
    public let id: String

    /// - Ollama: pings `/api/tags` (1s timeout) — `true` only when the local
    ///   server is actually running.
    /// - Cloud presets: `true` iff an API key is stored in the Keychain for
    ///   this preset (no live network check — matches roadmap V01-2's
    ///   "cloud presets return true when API key is non-empty").
    /// - `.custom` with `authStyle == .none`: always `true` (no key required,
    ///   e.g. a local non-Ollama server the user pointed at).
    public var isAvailable: Bool {
        get async {
            guard let baseURL = preset.baseURL else {
                SpeakLog.cleanup.error(
                    "OpenAICompatibleCleaner: preset \(self.preset.id, privacy: .public) has no valid base URL."
                )
                return false
            }
            if case .ollama = preset {
                let reachable = await client.pingOllama(baseURL: baseURL)
                SpeakLog.cleanup.debug(
                    "OpenAICompatibleCleaner: ollama reachable=\(reachable, privacy: .public)"
                )
                return reachable
            }
            guard preset.requiresAPIKey else {
                return true
            }
            let hasKey = (try? keychain.readKey(account: preset.id))?.isEmpty == false
            return hasKey
        }
    }

    /// Sends `text` to the configured endpoint and returns the cleaned result.
    ///
    /// - Throws: `SpeakError.llmCleanupFailed` on any failure — missing key,
    ///   connection failure, non-2xx response, or malformed response body.
    ///   Callers must check `isAvailable` first for the graceful (non-error)
    ///   fallback path; this method assumes the caller already decided to try.
    public func clean(_ text: String, mode: CleanupMode) async throws -> String {
        guard let baseURL = preset.baseURL else {
            throw SpeakError.llmCleanupFailed(
                "OpenAICompatibleCleaner: preset \(preset.id) has no valid base URL."
            )
        }

        var apiKey: String?
        if preset.requiresAPIKey {
            guard let storedKey = try? keychain.readKey(account: preset.id), !storedKey.isEmpty else {
                SpeakLog.cleanup.error(
                    "OpenAICompatibleCleaner: missing API key for \(self.preset.id, privacy: .public)."
                )
                throw SpeakError.llmCleanupFailed(
                    "No API key configured for \(preset.displayName). Add one in Settings → AI Cleanup."
                )
            }
            apiKey = storedKey
        }

        let systemPrompt = Self.instructions(for: mode)
        let charCount = text.count
        SpeakLog.cleanup.debug(
            "OpenAICompatibleCleaner: cleaning \(charCount, privacy: .public) chars via \(self.preset.id, privacy: .public)"
        )

        do {
            return try await client.chatCompletion(
                baseURL: baseURL,
                apiKey: apiKey,
                authStyle: preset.authStyle,
                model: model,
                systemPrompt: systemPrompt,
                userText: text
            )
        } catch let clientError as OpenAICompatibleClientError {
            let detail = Self.describe(clientError, preset: preset)
            SpeakLog.cleanup.error("OpenAICompatibleCleaner: \(detail, privacy: .public)")
            throw SpeakError.llmCleanupFailed(detail)
        } catch {
            let detail = error.localizedDescription
            SpeakLog.cleanup.error("OpenAICompatibleCleaner: unexpected error — \(detail, privacy: .public)")
            throw SpeakError.llmCleanupFailed(detail)
        }
    }

    // MARK: - Error mapping

    /// User-facing detail strings — mirror the HUD copy in the
    /// `openai-compatible-cleanup` skill's "Error Handling" table.
    static func describe(_ error: OpenAICompatibleClientError, preset: ProviderPreset) -> String {
        switch error {
        case .notRunning:
            if case .ollama = preset {
                return "Ollama is not running. Install from ollama.com, then run `ollama serve`."
            }
            return "Could not reach \(preset.displayName). Check the endpoint and your network connection."

        case .modelNotInstalled(let model):
            if case .ollama = preset {
                return "Run `ollama pull \(model)` in Terminal."
            }
            return "Model \(model) is not available on \(preset.displayName)."

        case .unauthorized:
            return "Check your API key in Settings → AI Cleanup."

        case .rateLimited:
            return "\(preset.displayName) rate-limited this request."

        case .requestFailed(let status):
            return "\(preset.displayName) request failed (HTTP \(status))."

        case .invalidResponse:
            return "\(preset.displayName) returned an unexpected response."
        }
    }

    // MARK: - Prompt construction

    /// System prompt for a given `CleanupMode`. Duplicated (not shared) from
    /// `FoundationModelsCleaner.modeInstructions(for:)` deliberately — see that
    /// file's note: `SpeakLLM`/cross-module sharing is a `SpeakCore`-side
    /// concern (this file already imports `SpeakLLM`) but the prompt text
    /// itself has no reason to route through the networking module, and each
    /// cleaner's copy can evolve independently of the other's prompt tuning
    /// without cross-engine regressions. [decision V01-2]
    static func instructions(for mode: CleanupMode) -> String {
        FoundationModelsCleaner.instructions(for: mode)
    }

    // MARK: - Init

    /// Creates a cleaner for `preset`, using `model` or the preset's
    /// `defaultModel` when `model` is `nil`/empty.
    ///
    /// - Parameters:
    ///   - client: injected for testing (stub-protocol-backed session in `SpeakLLM`).
    ///   - keychain: injected for testing (unique service namespace per test run).
    public init(
        preset: ProviderPreset,
        model: String? = nil,
        client: OpenAICompatibleClient = OpenAICompatibleClient(),
        keychain: LLMKeychainStore = LLMKeychainStore()
    ) {
        self.preset = preset
        let resolvedModel: String
        if let model, !model.isEmpty {
            resolvedModel = model
        } else {
            resolvedModel = preset.defaultModel
        }
        self.model = resolvedModel
        self.client = client
        self.keychain = keychain
        self.id = "openai-compatible:\(preset.id):\(resolvedModel)"
    }
}
