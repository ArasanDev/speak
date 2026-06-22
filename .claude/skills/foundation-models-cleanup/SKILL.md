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
    case styled(CleanupStyle, CleanupLevel, customVocabulary: [String] = [])
    case command(instruction: String)
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

## API Pattern (Ground-Truthed)

Foundation Models API uses a **two-step initialization pattern**:

```swift
// Step 1: Create the model with guardrails
let model = SystemLanguageModel(
    useCase: .general,
    guardrails: .permissiveContentTransformations
)

// Step 2: Create the session from the model + instructions
let session = LanguageModelSession(
    model: model,
    instructions: "Your system prompt here"
)

// Then use the session
let response = try await session.respond(to: userText)
```

Key points:
- `guardrails:` is a **parameter on `SystemLanguageModel`**, NOT on `LanguageModelSession` [verified]
- `LanguageModelSession.init(model:instructions:)` takes only two parameters [verified]
- `GenerationError` is **NOT `@frozen`** — exhaustive switches need `@unknown default` [verified]
- `UnavailableReason` is also non-`@frozen` [verified]

## Verify at Implementation Time

**Do not recall the Foundation Models API surface from training data.** The exact types for session creation, availability checking (`SystemLanguageModel` and `LanguageModelSession`), and prompt submission must be ground-truthed against current Apple documentation before writing any code.

Use the `apple-docs-mcp` MCP server (if available in this session) to look up `FoundationModels`, `SystemLanguageModel`, or `LanguageModelSession`. Otherwise, fetch from `https://developer.apple.com/documentation/foundationmodels`. Additionally, `swiftc -typecheck -sdk "$(xcrun --show-sdk-path)" -target arm64-apple-macosx26.0 <file>` is the strongest available local check for symbol resolution — use it to confirm any API symbol claim (note: it confirms symbol availability, not full method signatures). Tag every API claim `[verified]`, `[inferred]`, or `[unverified]`. Surface any conflict with prior claims before continuing.
