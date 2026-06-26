---
name: ollama-http-cleanup
description: Use when implementing the Ollama HTTP cleanup engine behind the `LLMCleaning` protocol (v0.1 task V01-2). The stub `OllamaModelCleaner.swift` already exists — read it before writing.
---

# Ollama HTTP Cleanup — Implementation Pointer

## Architectural Seam

Protocol: `LLMCleaning` — lives at `SpeakCore/Cleanup/Cleaner.swift`

```swift
public protocol LLMCleaning: Sendable {
    var id: String { get }
    func clean(_ transcript: String, mode: CleanupMode, context: CleanupContext) async throws -> String
}
```

Target file: `SpeakCore/Cleanup/OllamaModelCleaner.swift` — **read the existing stub first** before writing. Engine id: `"ollama"` `[decision]`

Plug in via `EngineFactories.swift` behind a `cleanupEngine` setting key; the stub entry already exists there.

## Hard Constraints

- **Loopback only**: base URL is always `http://127.0.0.1:11434`. Never resolve to an external host. Never let the user enter a remote hostname in v0.1. The moat audit checks for egress — this must stay 7/7. `[decision]`
- **Availability check before any request**: `GET /api/tags` must succeed before attempting cleanup. If it fails → `OllamaUnavailableError`; the engine falls back to `FoundationModelsCleaner` transparently (same fallback path as when FM is unavailable).
- **No new entitlements**: `com.apple.security.network.client` is already present in v0 for CLI communication. Confirm it covers `127.0.0.1` HTTP — it does for non-sandboxed apps `[inferred]`.
- **Not sandboxed in v0** — loopback HTTP is fine. If sandboxing is added later, revisit.
- No `print`. No force-unwrap. `os.Logger` only.

## REST API `[inferred — Ollama API is stable and well-documented; verify endpoint shapes]`

```swift
// Base URL — never allow external
let base = URL(string: "http://127.0.0.1:11434")!

// 1. Availability check
// GET /api/tags → {"models": [{"name": "qwen2.5:3b", "size": 1900000000, ...}]}
// HTTP 200 = running; connection refused = not running

// 2. Chat completion (preferred — preserves conversation structure)
// POST /api/chat
// Body:
let body: [String: Any] = [
    "model": "qwen2.5:3b",          // [decision] default model
    "messages": [
        ["role": "system", "content": systemPrompt],
        ["role": "user", "content": transcript]
    ],
    "stream": false                  // single response, not SSE
]
// Response: {"message": {"role": "assistant", "content": "<cleaned text>"}, "done": true}
// [inferred — verify against https://github.com/ollama/ollama/blob/main/docs/api.md]

// 3. Timeout: 30s per request (cleanup of 200 words should be <3s on M3+)
```

## Recommended Models (in Settings picker)

| Model | Size | Speed (M3) | Best for |
|-------|------|-----------|---------|
| `qwen2.5:3b` | ~1.9GB | ~45 tok/s | **Default** — best cleanup/speed balance |
| `phi4-mini` | ~2.5GB | ~40 tok/s | Slightly more nuanced tone |
| `gemma3:4b` | ~2.6GB | ~35 tok/s | Alternative, good quality |
| `llama3.2:3b` | ~2.0GB | ~45 tok/s | Familiar model for power users |

All `[inferred from research]` — actual performance depends on hardware.

## Error Handling

```swift
enum OllamaError: Error {
    case notRunning           // connection refused on /api/tags
    case modelNotInstalled(String)  // model absent from /api/tags response
    case requestFailed(Int)   // non-200 HTTP status
    case invalidResponse      // JSON decode failure
}
```

- `notRunning` → show `OllamaSetupHUD` with: "Ollama is not running. Install from ollama.com, then run `ollama serve` in Terminal." — copy-only, do not auto-open browser.
- `modelNotInstalled` → show HUD with: "Run `ollama pull qwen2.5:3b` in Terminal." — copy command to clipboard on tap.
- Both fall back to `FoundationModelsCleaner` automatically; user sees a subtle "Used built-in AI" note in overlay.

## Verify at Implementation Time

```sh
# If Ollama is installed locally:
curl http://127.0.0.1:11434/api/tags
curl -X POST http://127.0.0.1:11434/api/chat \
  -H "Content-Type: application/json" \
  -d '{"model":"qwen2.5:3b","messages":[{"role":"user","content":"Clean this: um so yeah the meeting is friday"}],"stream":false}'

# Official API docs (authoritative): https://github.com/ollama/ollama/blob/main/docs/api.md
# Verify response shape matches what's coded before marking [verified]
```

## URLSession Pattern

Use `URLSession.shared` with a 30-second timeout `URLRequest`. No third-party networking library. Parse JSON with `JSONSerialization` or `Codable` structs. The response must be decoded off the main thread (already guaranteed by `async`/`await`).
