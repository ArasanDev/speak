---
name: speechanalyzer-vocabulary
description: How to inject custom vocabulary terms into SpeechAnalyzer sessions — AnalysisContext.contextualStrings[.general]
metadata:
  type: reference
---

Custom vocabulary hints go through `AnalysisContext.contextualStrings[.general]`, NOT through `SpeechTranscriber` init params.

**Verified API** [verified: arm64e-apple-macos.swiftinterface, 2026-06-21]:
- `AnalysisContext` class at line 467 of Speech.swiftinterface
- `contextualStrings: [ContextualStringsTag: [String]]` — readable/writable property
- `ContextualStringsTag.general` — the tag for generic term hints
- `SpeechAnalyzer.setContext(_ newContext: AnalysisContext) async throws` — inject before `start(inputSequence:)`

**What was rejected and why:**
- `DictationTranscriber.ContentHint.customizedLanguage` — wrong class; we use `SpeechTranscriber`, not `DictationTranscriber`
- `SFCustomLanguageModelData.insert(term:)` — for authoring custom pronunciation data files, overkill for a string list

**Wiring pattern** (empty list = no-op, behavior-neutral default):
```swift
if !vocabulary.isEmpty {
    let ctx = AnalysisContext()
    ctx.contextualStrings = [.general: vocabulary]
    try await analyzer.setContext(ctx)   // before analyzer.start(inputSequence:)
}
```

`setContext` failure is non-fatal: log + continue without the vocabulary (do NOT throw up).

**SpeechTranscriber inits do not accept vocabulary** — the injection is always through `AnalysisContext` on `SpeechAnalyzer`.

Related: [[speechanalyzer-lifecycle]], [[p3-status]]
