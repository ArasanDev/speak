// SpeakCore/Engine/EngineFactories.swift
//
// Runtime factory functions for selecting transcriber + cleaner from settings
// (architecture.md §10.1 and §10a.1).
//
// Pattern: switch on the settings enum; for unbuilt v0.1/v1 engines, log via
// `SpeakLog` and fall back to the v0 default — never `fatalError`.
//
// WHY FREE FUNCTIONS (not static methods on SettingsStore):
//   The factories depend on concrete types (`AppleSpeechTranscriber`,
//   `FoundationModelsCleaner`) that live at the same layer as `SpeakEngine`.
//   Putting them in `SettingsStore` would create a layering inversion
//   (Storage layer referencing Engine/STT/Cleanup types). Free functions in the
//   Engine group are the right seam.

import Foundation

// MARK: - STT factory

/// Select the STT engine dictated by `settings.sttEngine`.
///
/// - `appleSpeech` → `AppleSpeechTranscriber()` (the v0 default)
/// - `whisperKit` / `whisperCpp` → v0.1/v1 stubs: log + fall back to `AppleSpeechTranscriber`
///
/// No `fatalError` on unbuilt cases. Future versions wire in the real types here.
public func defaultTranscriber(for settings: SettingsStore) -> any Transcribing {
    switch settings.sttEngine {
    case .appleSpeech:
        return AppleSpeechTranscriber()

    case .whisperKit:
        // [decision] WhisperKit is v0.1 — not built in v0. Falls back to Apple Speech.
        // When WhisperKit is added, replace this branch with `return WhisperKitTranscriber()`.
        SpeakLog.stt.error(
            "defaultTranscriber: .whisperKit requested but not built in v0 — using AppleSpeechTranscriber."
        )
        return AppleSpeechTranscriber()

    case .whisperCpp:
        // [decision] whisper.cpp is v1 — not built in v0. Falls back to Apple Speech.
        SpeakLog.stt.error(
            "defaultTranscriber: .whisperCpp requested but not built in v0 — using AppleSpeechTranscriber."
        )
        return AppleSpeechTranscriber()
    }
}

// MARK: - Cleanup factory

/// Select the cleanup engine dictated by `settings.cleanupEngine`, or return `nil`
/// when cleanup is disabled.
///
/// - `cleanupEnabled == false` → `nil` (raw transcript; fast path — no LLM pass)
/// - `cleanupEnabled == true` and `.foundationModels` → `FoundationModelsCleaner()`
/// - `cleanupEnabled == true` and `.ollama` → v0.1 stub: log + fall back to
///   `FoundationModelsCleaner()` so cleanup still runs with the available engine.
///
/// If `FoundationModelsCleaner.isAvailable` is `false` at runtime, `CaptureSession`
/// gracefully falls back to raw transcript (never `.error`) — see §10a.3.
public func defaultCleaner(for settings: SettingsStore) -> (any LLMCleaning)? {
    guard settings.cleanupEnabled else {
        // Toggle is off — caller receives nil; CaptureSession delivers raw transcript.
        return nil
    }
    switch settings.cleanupEngine {
    case .foundationModels:
        return FoundationModelsCleaner()

    case .ollama(let model):
        // Wave 2.1: OllamaCleaner stub exists now. Returns `isAvailable == false` always —
        // networking code that would do the real localhost check cannot live in SpeakCore/
        // (moat audit greps for it). CaptureSession.runCleanup sees `false` and falls
        // back to raw transcript gracefully, without error.
        // Replace with a real impl in the SpeakLLM module (v0.1).
        SpeakLog.cleanup.warning(
            "defaultCleaner: .ollama(model: \(model, privacy: .public)) — using v0.1 stub (isAvailable=false)."
        )
        return OllamaCleaner(model: model)

    case .mlx(let model):
        // Wave 2.1: MLXCleaner stub. MLX requires third-party Swift packages — forbidden
        // in v0 (AGENTS.md §2.9). Stub returns `isAvailable == false`; graceful fallback.
        // Replace when MLX dep is approved and added to project.yml (v0.1+).
        SpeakLog.cleanup.warning(
            "defaultCleaner: .mlx(model: \(model, privacy: .public)) — using v0.1+ stub (isAvailable=false)."
        )
        return MLXCleaner(model: model)
    }
}
