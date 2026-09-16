// App/Cleanup/CleanupFactories.swift
//
// Runtime factory for selecting the cleanup engine from settings
// (architecture.md §10a.1).
//
// WHY THIS LIVES IN THE APP TARGET (not SpeakCore/Engine/EngineFactories.swift):
//   The `.ollama` and `.openAICompatible` cases construct
//   `OpenAICompatibleCleaner`, which is backed by the `SpeakLLM` module
//   (`OpenAICompatibleClient` + `LLMKeychainStore`). SpeakCore links zero
//   SpeakLLM code — concrete alternative providers are composed above the
//   `LLMCleaning` protocol seam, in this target. [decision: layering fix —
//   `defaultCleaner` moved here from `EngineFactories` when the
//   SpeakCore → SpeakLLM link edge was severed.]
//
// Nothing inside SpeakCore calls this factory: `SpeakEngine`/`CaptureSession`
// take an injected cleaner. All call sites are App-side (DictationController,
// DebugLaunchDispatcher, IntelligenceSettingsView) or tests.

import Foundation
import SpeakCore

// MARK: - Cleanup factory

/// Select the cleanup engine dictated by `settings.cleanupEngine`, or return `nil`
/// when cleanup is disabled.
///
/// - `cleanupEnabled == false` → `nil` (raw transcript; fast path — no LLM pass)
/// - `cleanupEnabled == true` and `.foundationModels` → `FoundationModelsCleaner()`
/// - `cleanupEnabled == true` and `.ollama` → `OpenAICompatibleCleaner(preset: .ollama)`
///   (V01-2 — real implementation, backed by the `SpeakLLM` module)
/// - `cleanupEnabled == true` and `.openAICompatible` → `OpenAICompatibleCleaner`
///   for the chosen cloud/custom preset (V01-2)
///
/// If the returned cleaner's `isAvailable` is `false` at runtime, `CaptureSession`
/// gracefully falls back to raw transcript (never `.error`) — see §10a.3. This is
/// true for Ollama-not-running and for a cloud preset with no API key configured,
/// exactly as it is for Foundation Models being unavailable.
func defaultCleaner(for settings: SettingsStore) -> (any LLMCleaning)? {
    guard settings.cleanupEnabled else {
        // Toggle is off — caller receives nil; CaptureSession delivers raw transcript.
        return nil
    }
    switch settings.cleanupEngine {
    case .foundationModels:
        return FoundationModelsCleaner()

    case .ollama(let model):
        // V01-2: real implementation. Loopback-only base URL, no API key —
        // `isAvailable` pings http://127.0.0.1:11434/api/tags (1s timeout).
        return OpenAICompatibleCleaner(preset: .ollama, model: model)

    case .openAICompatible(let preset, let model):
        // V01-2: cloud/custom presets. Strictly opt-in — only reachable when the
        // user has picked this case in Settings. `isAvailable` checks Keychain for
        // a stored API key (no live network probe for cloud presets).
        return OpenAICompatibleCleaner(preset: preset, model: model)

    case .mlx(let model):
        // MLX requires third-party Swift packages — forbidden in v0 (AGENTS.md §2.3).
        // Returns nil; graceful fallback to raw transcript.
        SpeakLog.cleanup.warning(
            "defaultCleaner: .mlx(model: \(model, privacy: .public)) — using v0.1+ fallback."
        )
        return nil
    }
}
