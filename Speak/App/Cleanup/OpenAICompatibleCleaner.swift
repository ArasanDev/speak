// App/Cleanup/OpenAICompatibleCleaner.swift
//
// v0.1 universal OpenAI-compatible LLM cleanup engine (renamed/generalized from
// the `OllamaCleaner` v0.1 stub — Wave 2.1). One `LLMCleaning` conformer covers
// six presets: Ollama (local server, no key), Sarvam LLM, OpenAI, Groq,
// OpenRouter, and a fully user-entered custom endpoint. All share the same
// `POST <baseURL>/chat/completions` OpenAI-compatible wire shape.
//
// Foundation Models remains the v0 default; this engine is opt-in only, exactly
// as `.ollama`/`.mlx` were opt-in stubs before it (`CleanupFactories.defaultCleaner`).
//
// WHY THIS FILE LIVES IN THE APP TARGET (not SpeakCore):
//   `scripts/verify-moat.sh` + `SpeakTests/MoatAuditTests.swift` assert SpeakCore
//   is free of networking symbols — and, since the layering fix, SpeakCore also
//   links zero SpeakLLM code. Concrete alternative providers sit above the
//   `LLMCleaning` protocol seam (architecture.md): the preset *data*
//   (`ProviderPreset`, `LLMAuthStyle`) stays in SpeakCore so `SettingsStore` can
//   persist it, while this conformer — which constructs
//   `SpeakLLM.OpenAICompatibleClient` and `SpeakLLM.LLMKeychainStore` — lives up
//   here in the App target alongside the other SpeakLLM call sites. The file
//   itself still contains no networking symbols: the actual request is
//   delegated to `SpeakLLM`, and API-key storage goes through
//   `SpeakLLM.LLMKeychainStore`, never a bare `SecItemAdd`/`SecItemCopyMatching`
//   call (benchmark.md §3 #4 "no account/auth" grep). [decision V01-2 —
//   this is the `SpeakLLM`-backed engine the old `OllamaCleaner.swift` stub
//   sketched; moved SpeakCore → App when the link edge was severed.]
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
import SpeakCore
import SpeakLLM

/// One `LLMCleaning` conformer for every OpenAI-compatible chat-completions
/// endpoint. Selected via `SettingsStore.cleanupEngine == .openAICompatible` or
/// the legacy `.ollama(model:)` case (routed to the `.ollama` preset by
/// `CleanupFactories.defaultCleaner`).
final class OpenAICompatibleCleaner: LLMCleaning, Sendable {

    // MARK: - Configuration

    let preset: ProviderPreset
    let model: String
    private let client: OpenAICompatibleClient
    private let keychain: LLMKeychainStore

    // MARK: - LLMCleaning conformance

    /// Stable identifier written to `TranscriptionResult.engineId`.
    let id: String

    /// - Ollama: pings `/api/tags` (1s timeout) — `true` only when the local
    ///   server is actually running.
    /// - Cloud presets: `true` iff an API key is stored in the Keychain for
    ///   this preset (no live network check — matches roadmap V01-2's
    ///   "cloud presets return true when API key is non-empty").
    /// - `.custom` with `authStyle == .none`: always `true` (no key required,
    ///   e.g. a local non-Ollama server the user pointed at).
    var isAvailable: Bool {
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
    func clean(_ text: String, mode: CleanupMode) async throws -> String {
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

    /// System prompt for a given `CleanupMode`. Delegates to
    /// `FoundationModelsCleaner.instructions(for:)` — see that file's note on
    /// why the prompt text is a `SpeakCore`-side concern while this cleaner
    /// sits in the App target. [decision V01-2]
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
    init(
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
