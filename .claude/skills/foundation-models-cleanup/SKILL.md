---
name: foundation-models-cleanup
description: Use when implementing or modifying the Apple Foundation Models AI cleanup layer in SpeakCore — specifically FoundationModelsCleaner, the LLMCleaning protocol, CleanupMode handling, or graceful fallback to raw transcript.
---

# Foundation Models Cleanup — Implementation Pointer

## Architectural Seam

Protocol: `LLMCleaning` — lives at `SpeakCore/Cleanup/Cleaner.swift`

```swift
protocol LLMCleaning {
    var id: String { get }
    var isAvailable: Bool { get async }
    func clean(_ text: String, mode: CleanupMode) async throws -> String
}

enum CleanupMode {
    case fillersOnly
    case punctuation
    case codeAware
    case toneAdjust
    case translate(Locale)
}
```

The v0 concrete implementation is `FoundationModelsCleaner`, backed by Apple's **Foundation Models** framework (on-device LLM, macOS 26). This is an Apple framework — it does NOT violate the no-third-party-dependency rule.

`TranscriptionResult.cleanedText` is `String?` — `nil` when cleanup is off or unavailable.

## Hard Constraints — Read Before Touching This Layer

- **AI neat-writing is v0 CORE, not optional.** Do not make it a feature flag or defer it.
- **Graceful unavailability is mandatory.** When Foundation Models is unavailable (e.g., model not downloaded, hardware limit), the session MUST fall back to the raw transcript and reach state `done` — NOT `error`. Unavailability is not an error.
- **`SpeakError.llmCleanupFailed` is surfaced ONLY on genuine API failure**, never on mere unavailability. Distinguish the two cases explicitly.
- `isAvailable` must be checked asynchronously before every call; never cache it across sessions without re-checking.
- 100% on-device. No text leaves the device for cleanup. No cloud LLM.
- Use `os.Logger`. No `print`. No force-unwrap. No `try!`.

## Roadmap P3.5 Done-When

- `FoundationModelsCleaner.isAvailable` correctly reflects whether the on-device model is ready.
- `clean(_:mode:)` produces cleaned text for each `CleanupMode` case.
- When `isAvailable` is `false`, `TranscriptionResult.cleanedText` is `nil` and session state reaches `done` (not `error`).
- `SpeakError.llmCleanupFailed` is thrown only on genuine API errors, not on unavailability.
- Unit tests cover: available path produces non-nil cleanedText, unavailable path produces nil cleanedText + done state, API failure path produces `llmCleanupFailed`.

## Verify at Implementation Time

**Do not recall the Foundation Models API surface from training data.** The exact types for session creation, availability checking (`LanguageModelSession` or equivalent), and prompt submission must be ground-truthed against current Apple documentation before writing any code.

Use the `apple-docs-mcp` MCP server (if available in this session) to look up `FoundationModels` or `LanguageModelSession`. Otherwise, fetch from `https://developer.apple.com/documentation/foundationmodels`. Tag every API claim `[verified]`, `[inferred]`, or `[unverified]`. Surface any conflict with prior claims before continuing.
