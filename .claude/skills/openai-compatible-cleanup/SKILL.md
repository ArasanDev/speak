---
name: openai-compatible-cleanup
description: Use when implementing the universal OpenAI-compatible LLM cleanup engine (v0.1 task V01-2) — covers Ollama (local), Sarvam-30B, OpenAI, Groq, OpenRouter, and any custom endpoint with one URLSession client. Zero new Swift package dependencies.
---

# OpenAI-Compatible LLM Cleanup — Implementation Pointer

## Architectural Seam

Protocol: `LLMCleaning` — lives at `SpeakCore/Cleanup/Cleaner.swift`

```swift
public protocol LLMCleaning: Sendable {
    var id: String { get }
    func clean(_ transcript: String, mode: CleanupMode, context: CleanupContext) async throws -> String
}
```

**Target**: Rename `SpeakCore/Cleanup/OllamaModelCleaner.swift` → `OpenAICompatibleCleaner.swift`.
Generalize the existing stub into a single type with configurable `baseURL`, `apiKey?`, `model`, `authStyle`.
Engine id: `"openai-compatible"` `[decision]`

Wire via `EngineFactories.swift` → `cleanupEngine` setting key. The existing stub entry should already be there.

## Core Design

```swift
// `[inferred]` — adapt to actual protocol constraints at implementation time
public struct OpenAICompatibleCleaner: LLMCleaning {
    public let id = "openai-compatible"
    let baseURL: URL          // e.g. http://127.0.0.1:11434/v1
    let apiKey: String?       // nil for local providers (Ollama)
    let model: String         // e.g. "qwen2.5:3b", "sarvam-30b"
    let authStyle: AuthStyle  // .bearer or .subscriptionKey

    public enum AuthStyle {
        case bearer            // Authorization: Bearer <key>  — OpenAI, Groq, OpenRouter
        case subscriptionKey   // api-subscription-key: <key> — Sarvam AI
    }
}
```

## Provider Presets

Encode as a `ProviderPreset` enum in `SettingsStore`; each preset populates the four fields above:

| Preset | baseURL | authStyle | Default model | Key required? |
|--------|---------|-----------|---------------|--------------|
| `.ollama` | `http://127.0.0.1:11434/v1` | `.bearer` (key = `""`) | `qwen2.5:3b` | No |
| `.sarvamLLM` | `https://api.sarvam.ai/v1` | `.subscriptionKey` | `sarvam-30b` | Yes |
| `.openAI` | `https://api.openai.com/v1` | `.bearer` | `gpt-4o-mini` | Yes |
| `.groq` | `https://api.groq.com/openai/v1` | `.bearer` | `llama3-8b-8192` | Yes |
| `.openRouter` | `https://openrouter.ai/api/v1` | `.bearer` | (user sets) | Yes |
| `.custom(url, style, model)` | user-entered | user-sets | user-sets | Optional |

## REST API Shape `[inferred — OpenAI chat completions is the industry standard; Sarvam LLM verified from official docs June 2026]`

```swift
// POST <baseURL>/chat/completions
// Headers:
//   Content-Type: application/json
//   Authorization: Bearer <key>          ← for .bearer style
//   api-subscription-key: <key>          ← for .subscriptionKey style (Sarvam)
//
// Body:
let body: [String: Any] = [
    "model": model,
    "messages": [
        ["role": "system", "content": systemPromptFor(mode, context)],
        ["role": "user", "content": transcript]
    ],
    "stream": false,
    "max_tokens": 1024
]
//
// Response:
// {"choices": [{"message": {"content": "<cleaned text>"}}], ...}
// Extract: choices[0].message.content
```

## Availability Check

```swift
// Ollama only: GET http://127.0.0.1:11434/api/tags → {"models": [...]}
// Cloud providers: no pre-check; `isAvailable` returns true when API key is non-empty.
// Timeout: 1 s for availability check, 30 s for cleanup request.
```

## Recommended Models per Preset

| Preset | Model | Size / Cost | Notes |
|--------|-------|-------------|-------|
| Ollama | `qwen2.5:3b` | ~1.9 GB | Best cleanup/speed balance `[inferred]` |
| Ollama | `phi4-mini` | ~2.5 GB | More nuanced tone `[inferred]` |
| Ollama | `gemma3:4b` | ~2.6 GB | Alternative `[inferred]` |
| Sarvam | `sarvam-30b` | 64K ctx | ₹2.5/1M in tokens `[verified]` |
| Sarvam | `sarvam-105b` | 128K ctx | ₹4/1M in; higher quality `[verified]` |
| OpenAI | `gpt-4o-mini` | — | Fast, cheap, excellent cleanup |
| Groq | `llama3-8b-8192` | — | Very fast inference |

## Error Handling

```swift
enum OpenAICompatibleError: Error {
    case notRunning              // Ollama: connection refused on /api/tags
    case modelNotInstalled(String) // Ollama: model absent from /api/tags
    case unauthorized            // 401 — bad API key
    case rateLimited             // 429 — slow down
    case requestFailed(Int)      // other non-200
    case invalidResponse         // JSON decode failure
}
```

- `notRunning` → show `LocalServerSetupHUD`: "Ollama is not running. Install from ollama.com, then run `ollama serve`." (copy, no auto-open browser)
- `modelNotInstalled` → HUD: "Run `ollama pull <model>` in Terminal." (copy command)
- `unauthorized` → HUD: "Check your API key in Settings → AI Cleanup."
- `rateLimited` → silent retry after 1 s, then fall back to FoundationModelsCleaner
- All non-fatal errors fall back to `FoundationModelsCleaner`; user sees "Used built-in AI" note

## Hard Constraints

- **Ollama preset: loopback only** — base URL is pinned to `http://127.0.0.1:11434`. Never let the user enter a remote hostname for the Ollama preset. The moat audit checks for egress — this must stay 7/7. `[decision]`
- **Cloud presets require explicit user configuration** — no cloud call is ever made without the user entering a base URL and API key. Default engine is always `FoundationModelsCleaner`. `[decision]`
- **NEVER send audio to any endpoint** — this cleaner sends only the transcribed text string. Audio stays local always.
- **Keychain for API keys** — store `apiKey` in Keychain (`kSecClassGenericPassword`), not `UserDefaults`.
- No `print`. No force-unwrap. `os.Logger` only. No new SPM dependencies.

## Settings UI

Settings → AI Cleanup tab:
- Cleanup engine: segmented picker `[On-device | Local server | Cloud]`
- Local server: preset dropdown (Ollama / Custom) + URL field (disabled for Ollama) + model field
- Cloud: preset dropdown (Sarvam / OpenAI / Groq / OpenRouter / Custom) + base URL (hidden for presets) + API key `SecureField` + model field
- Availability indicator: green dot (last check OK) / red dot (unavailable / no key)

## Verify at Implementation Time

```sh
# Ollama availability + chat (if Ollama is running):
curl http://127.0.0.1:11434/api/tags
curl -X POST http://127.0.0.1:11434/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"model":"qwen2.5:3b","messages":[{"role":"user","content":"Clean: um so yeah the meeting is friday"}],"stream":false}'

# Sarvam LLM (with key):
curl -X POST https://api.sarvam.ai/v1/chat/completions \
  -H "api-subscription-key: YOUR_KEY" \
  -H "Content-Type: application/json" \
  -d '{"model":"sarvam-30b","messages":[{"role":"user","content":"Clean: um so yeah the meeting is friday"}],"stream":false}'

# Official refs:
# Ollama: https://github.com/ollama/ollama/blob/main/docs/api.md
# Sarvam: https://docs.sarvam.ai/api-reference-docs/chat/chat-completions
```

Tag all verified shapes `[verified]` after testing; update this skill with findings.
