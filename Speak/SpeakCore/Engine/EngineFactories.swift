// SpeakCore/Engine/EngineFactories.swift
//
// Runtime factory functions for selecting transcriber + transcript expander
// from settings (architecture.md §10.1).
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
//
// NOTE — the cleanup-engine factory `defaultCleaner(for:)` moved to the App
//   target (`App/Cleanup/CleanupFactories.swift`): its `.ollama` /
//   `.openAICompatible` cases construct `SpeakLLM`-backed types, and SpeakCore
//   links zero SpeakLLM code. `defaultTranscriber`/`defaultExpander` stay here
//   because every engine they build is provider-neutral SpeakCore code.

import Foundation

// MARK: - STT factory

/// Select the STT engine dictated by `settings.sttEngine`.
///
/// - `appleSpeech` → `AppleSpeechTranscriber()` (the v0 default)
/// - `whisperKit` / `whisperCpp` → v0.1/v1 stubs: log + fall back to `AppleSpeechTranscriber`
///
/// No `fatalError` on unbuilt cases. Future versions wire in the real types here.
public func defaultTranscriber(for settings: SettingsStore) -> any Transcribing {
    // effectiveVocabulary = customVocabulary + acoustic-correction targets, so a
    // correction's ground-truth term also reaches contextualStrings. Note the
    // transcriber captures this list at init — the engine's transcriber is built
    // once, so STT-side biasing applies on the next app/engine rebuild, while
    // the prompt-side vocabulary applies on the next dictation. [inferred]
    switch settings.sttEngine {
    case .appleSpeech:
        return AppleSpeechTranscriber(vocabulary: settings.effectiveVocabulary)

    case .whisperKit:
        // [decision] WhisperKit is v0.1 — not built in v0. Falls back to Apple Speech.
        // When WhisperKit is added, replace this branch with `return WhisperKitTranscriber()`.
        SpeakLog.stt.error(
            "defaultTranscriber: .whisperKit requested but not built in v0 — using AppleSpeechTranscriber."
        )
        return AppleSpeechTranscriber(vocabulary: settings.effectiveVocabulary)

    case .whisperCpp:
        // [decision] whisper.cpp is v1 — not built in v0. Falls back to Apple Speech.
        SpeakLog.stt.error(
            "defaultTranscriber: .whisperCpp requested but not built in v0 — using AppleSpeechTranscriber."
        )
        return AppleSpeechTranscriber(vocabulary: settings.effectiveVocabulary)
    }
}

// MARK: - Transcript expander factory

/// Compose the raw-transcript expansion chain read from settings at call time:
/// acoustic corrections (STT mishearing → ground truth) FIRST, then snippet
/// triggers — so a trigger the user actually said still matches even when the
/// recognizer mangled it. `nil` when neither stage has any entries.
///
/// [decision: corrections-before-snippets ordering]
public func defaultExpander(
    for settings: SettingsStore,
    snippetStore: SnippetStore?
) -> (any SnippetExpanding)? {
    var stages: [any SnippetExpanding] = []
    // User corrections first — on a `heard` collision the first replacement
    // consumes the trigger, so user entries (incl. an identity row meant to
    // disable a built-in) always win over the seeded table.
    // [decision: built-in slips merge under user entries]
    let userCorrections = settings.acousticCorrections
    let userHeard = Set(userCorrections.map { $0.heard.lowercased() })
    let corrections = userCorrections + AcousticCorrections.builtIn.filter {
        !userHeard.contains($0.heard.lowercased())
    }
    if !corrections.isEmpty {
        stages.append(AcousticCorrectionExpander(corrections: corrections))
    }
    if let snippetStore, !snippetStore.snippets.isEmpty {
        stages.append(snippetStore.makeExpander())
    }
    switch stages.count {
    case 0: return nil
    case 1: return stages[0]
    default: return CompositeExpander(stages)
    }
}
