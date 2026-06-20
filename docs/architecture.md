# `speak` — Architecture (HOW)

> **Status**: The build blueprint. Implement from this. Types and signatures
> below are **verbatim Swift** — implement them as written unless you find a
> compile-error or primary-source contradiction (then surface it).

> **Depends on**: `product.md`. **Depended on by**: `roadmap.md`, `quality.md`.

---

## 0. TL;DR

Single Swift codebase. SwiftUI app + `SpeakCore.framework`. Apple
`SpeechAnalyzer` behind a pluggable `Transcribing` protocol. Apple
`Foundation Models` framework behind a pluggable `LLMCleaning` protocol for
on-device AI neat-writing (cleanup) — both engines are v0 defaults, both are
Apple frameworks, zero third-party dependencies. `AVAudioEngine` for mic.
`CGEventTap` for hotkeys. `NSPasteboard` write + `Cmd+V` simulate for paste.
SQLite for history. `os.Logger` for logging. No FFI, no Rust, no third-party
deps in v0.

---

## 1. The settled language decision (do not relitigate)

> **v0 = a single Swift codebase. No Rust. No FFI. No cross-platform layer.**

The earlier research docs debated a "Rust core + Swift shell + uniffi" split.
That debate is **over**. Reasons, in brief (full evidence in
`research/SPEAK_DICTATION_STACKS.md` and `research/TECH_STACK_JUDGMENT.md`):

1. **All 8 shipping Mac dictation apps are Swift-native** (Wispr, Willow,
   Superwhisper, Aiko, MacWhisper, VoiceInk, FluidVoice, TypeWhisper).
   `[verified]`
2. The macOS APIs that define the product (`SpeechAnalyzer`, `CGEventTap`,
   `NSPasteboard`, `AVAudioEngine`, Apple Intelligence) are Swift-first.
3. The Rust recommendation came from studying the **wrong category**
   (cross-platform desktop frameworks like Firefox/Deno/Tauri), not Mac-first
   dictation apps. `[verified]` in `research/TECH_STACK_JUDGMENT.md`.
4. The factual claim that "Anthropic rewrote Claude Code to Rust" was wrong —
   Claude Code is TypeScript + Bun. `[verified]` in
   `research/SPEAK_LANGUAGE_CORRECTION.md`.

### The portability seam (preserve, don't build)

If Windows becomes a real target in v1+, the engine logic gets **extracted**
into a portable module (Rust or TS+Bun) and the Mac shell stays Swift. For v0,
we preserve this seam by keeping engine logic in **`SpeakCore.framework`** with
clean protocol boundaries — so extraction is possible later without a rewrite.

```
v0 (now):    Speak.app (SwiftUI) ──► SpeakCore.framework (Swift)
v1+ (maybe): Speak.app (SwiftUI) ──► SpeakCore (Swift) ──ffi──► portable engine (Rust/TS)
```

**Build the seam, not the second layer.**

---

## 2. Tech stack

| Layer | Choice | Rationale |
|---|---|---|
| Language | **Swift 5.9+** | `[verified]` dominant pattern for Mac dictation |
| UI | **SwiftUI** (`MenuBarExtra`, `Settings`) | macOS 13+ native |
| Mic capture | **`AVAudioEngine`** | standard real-time audio API |
| STT (default) | **Apple `SpeechAnalyzer`** (`Speech` framework) | `[verified]` macOS 26+, on-device, free |
| STT (protocol) | **pluggable `Transcribing` protocol** | FluidVoice pattern |
| Cleanup (default) | **Apple `Foundation Models`** framework | `[verified]` macOS 26+, on-device LLM, AS+NE; Apple framework — no third-party dep |
| Cleanup (protocol) | **pluggable `LLMCleaning` protocol** | same pattern as STT; skippable via settings toggle |
| Cleanup (v0.1 alt) | **Ollama MLX** (Qwen 2.5 3B / Gemma 3 4B / Phi-4-mini) | local, user-swappable; requires Ollama installed |
| Hotkey | **`CGEventTap`** (Accessibility + Input Monitoring) | only way to detect Fn globally |
| Paste | **`NSPasteboard` write + `CGEvent` Cmd+V** | write-never-read; avoids read prompt `[verified]`; bypass itself `[unverified]` — test empirically at P6 |
| Menubar | **`NSStatusItem` / `MenuBarExtra`** | native surface |
| Persistence | **SQLite** (history) + **`UserDefaults`** (settings) | standard |
| Logging | **`os.Logger` (OSLog)** | native, performant, no `print` |
| Distribution | **Homebrew Cask + `.dmg`** (v0); MAS (v1+) | discovery vs. sandbox tradeoff |
| License | **MIT** | community moat |
| Code signing | **Developer ID + notarization** | required for Gatekeeper on macOS 26 |
| Sandbox | **NOT sandboxed in v0** | sandbox blocks global hotkeys + Cmd+V |

---

## 3. System context (C4 L1)

```
        ┌──────────┐   keyboard (Fn)    ┌─────────────────────┐
        │  User    │──────────────────► │      speak.app       │
        └──────────┘   audio (mic)      │  (menubar, macOS 26) │
            ▲                              └──────────┬──────────┘
            │ pasted text (Cmd+V)                    │ Apple frameworks
            │                                         ▼
        ┌──────────┐                      ┌─────────────────────┐
        │ Focused  │ ◄──────────────────  │ SpeechAnalyzer (STT)│
        │   app    │                      │ AVAudioEngine (mic) │
        └──────────┘                      │ CGEvent (keys/paste)│
                                          │ NSPasteboard        │
                                          └─────────────────────┘
```

---

## 4. Containers (C4 L2)

Two deployable units in v0:
- **`speak.app`** — the SwiftUI menubar app the user runs.
- **`SpeakCore.framework`** — the headless dictation engine, embedded in the
  app. (Separated so a future CLI shim / iOS app / extracted portable engine
  can reuse it — the §1.1 seam.)

```
┌─────────────────────────────────────────────┐
│  speak.app  (SwiftUI)                       │
│   MenuBarExtra · Onboarding · Settings      │
│              │  embeds                      │
│              ▼                              │
│  ┌────────────────────────────────────────┐ │
│  │  SpeakCore.framework  (Swift)          │ │
│  │   AudioCapture · HotkeyMonitor         │ │
│  │   SpeechTranscriber · PasteboardWriter │ │
│  │   LLMCleaner (v0) · PermissionManager  │ │
│  │   HistoryStore · SettingsStore         │ │
│  └────────────────────────────────────────┘ │
└─────────────────────────────────────────────┘
```

---

## 5. Module layout

```
speak/
├── App/                          # SwiftUI app target
│   ├── SpeakApp.swift            # @main, MenuBarExtra, state injection
│   ├── MenuBar/                  # icon, status, quick toggles
│   ├── Onboarding/               # 3-permission flow, hotkey picker
│   ├── Settings/                 # hotkey, language, LLM, history, paste mode
│   └── Overlay/                  # floating capture dot + partial transcript
├── SpeakCore/                    # Framework: headless dictation engine
│   ├── Engine/
│   │   ├── SpeakEngine.swift     # owns the session lifecycle (actor)
│   │   ├── CaptureSession.swift  # idle → listening → processing → done | error
│   │   └── SpeakError.swift      # error enum + recovery suggestions
│   ├── Audio/
│   │   └── AudioCapture.swift    # AVAudioEngine wrapper, 16kHz mono PCM
│   ├── Hotkey/
│   │   └── HotkeyMonitor.swift   # CGEventTap, double-tap detection, rebind
│   ├── STT/
│   │   ├── Transcriber.swift     # protocol `Transcribing`
│   │   └── AppleSpeechTranscriber.swift   # SpeechAnalyzer impl (v0 default)
│   │   # WhisperKitTranscriber.swift      (v0.1)
│   │   # WhisperCppTranscriber.swift      (v1, Intel)
│   ├── Cleanup/                  # AI neat-writing (v0 CORE — not optional)
│   │   ├── Cleaner.swift         # protocol `LLMCleaning` + CleanupMode enum
│   │   └── FoundationModelsCleaner.swift  # Apple Foundation Models impl (v0 default)
│   │   # (OllamaCleaner.swift lives in SpeakLLM/ as v0.1 alternative)
│   ├── Paste/
│   │   └── PasteboardWriter.swift # NSPasteboard write + Cmd+V simulate
│   ├── Permissions/
│   │   └── PermissionManager.swift # mic/accessibility/input-monitoring state machine
│   ├── Storage/
│   │   ├── HistoryStore.swift     # SQLite, last N dictations, searchable
│   │   └── SettingsStore.swift    # typed UserDefaults wrapper
│   └── Logging/
│       └── SpeakLog.swift         # OSLog categories
├── SpeakLLM/                     # (v0.1) Ollama alternative cleanup engine
│   ├── OllamaClient.swift        # HTTP client for Ollama local server
│   ├── OllamaCleaner.swift       # `LLMCleaning` impl via Ollama (v0.1 alt)
│   └── CleanupPrompt.swift       # shared prompt templates
├── SpeakCLI/                     # (v0.1, optional) `speak --start` shim
│   └── SpeakCLI.swift
├── SpeakTests/                   # XCTest unit + XCUITest UI
└── Resources/
    ├── Info.plist                # usage descriptions
    ├── Assets.xcassets           # app icon, menubar icons
    └── speak.cask.rb             # Homebrew Cask formula (in dist/)
```

---

## 6. Key types (Swift signatures — implement verbatim)

```swift
// SpeakCore/STT/Transcriber.swift
public protocol Transcribing: Sendable {
    var id: String { get }
    func startStream(locale: Locale) -> AsyncThrowingStream<TranscriptChunk, Error>
    func stop() async
}

public struct TranscriptChunk: Sendable {
    public let text: String
    public let isFinal: Bool
    public let timestamp: Date
}

// SpeakCore/Engine/CaptureSession.swift
public actor CaptureSession {
    public enum State: Sendable {
        case idle, listening, processing, done, error(SpeakError)
    }
    public func start() async throws
    public func stop() async throws -> TranscriptionResult
    public func cancel() async
}

public struct TranscriptionResult: Sendable {
    public let rawText: String
    public let cleanedText: String?   // nil if LLM cleanup off
    public let duration: TimeInterval
    public let engineId: String
    public let createdAt: Date
}

// SpeakCore/Hotkey/HotkeyMonitor.swift
public enum HotkeyEvent: Sendable { case startCapture, stopCapture }

public struct HotkeyBinding: Codable, Sendable {
    public enum Trigger: Codable, Sendable {
        case doubleTap, singleTapToggle, hold
    }
    public let keyCode: Int
    public let modifiers: CGEventFlags
    public let trigger: Trigger
    public let doubleTapWindow: TimeInterval  // default 0.4
}

// SpeakCore/Permissions/PermissionManager.swift
public enum PermissionState: Sendable {
    case notDetermined, requesting, granted, denied, restricted
}

public enum PermissionKind: Sendable, CaseIterable {
    case microphone, accessibility, inputMonitoring
}

// SpeakCore/Storage/HistoryStore.swift
public struct HistoryEntry: Sendable, Identifiable {
    public let id: UUID
    public let rawText: String
    public let cleanedText: String?
    public let createdAt: Date
    public let engineId: String
}

// SpeakCore/Engine/SpeakEngine.swift — the top-level facade
public final class SpeakEngine: @unchecked Sendable {
    public init(transcriber: any Transcribing,
                cleaner: (any LLMCleaning)? = nil,
                history: HistoryStoring,
                settings: SettingsStore) throws
    public func newSession() -> CaptureSession
}

// SpeakCore/Cleanup/Cleaner.swift (protocol — v0 CORE)
public protocol LLMCleaning: Sendable {
    var id: String { get }
    var isAvailable: Bool { get async }
    func clean(_ text: String, mode: CleanupMode) async throws -> String
}

public enum CleanupMode: Sendable {
    case fillersOnly, punctuation, codeAware, toneAdjust, translate(Locale)
}

// SpeakCore/Cleanup/FoundationModelsCleaner.swift (v0 default)
// Uses Apple's Foundation Models framework (macOS 26, Apple Silicon + Neural Engine).
// Apple framework — does NOT violate the "no third-party deps in v0" rule.
import FoundationModels

public final class FoundationModelsCleaner: LLMCleaning, @unchecked Sendable {
    public let id = "foundation-models"
    private let session: LanguageModelSession

    public init() {
        self.session = LanguageModelSession()
    }

    public var isAvailable: Bool {
        // [verified via swiftc against the macOS 26 SDK] The real symbol is
        // `SystemLanguageModel` (NOT `LanguageModel`, which does not resolve).
        // Use `.availability` (an enum) — it reports WHY the model is unavailable
        // (Apple Intelligence off, model downloading, unsupported device), which
        // the P3.5 graceful raw-text fallback needs. Do NOT use `!= nil`:
        // `.default` is non-optional, so that comparison is always true.
        get async {
            if case .available = SystemLanguageModel.default.availability { return true }
            return false
        }
    }

    public func clean(_ text: String, mode: CleanupMode) async throws -> String {
        let prompt = CleanupPrompt.system(for: mode) + "\n\nTranscript:\n" + text
        let response = try await session.respond(to: Prompt(prompt))
        return response.content.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// SpeakCore/Engine/SpeakError.swift
public enum SpeakError: Error, Sendable {
    case microphoneDenied
    case accessibilityDenied
    case inputMonitoringDenied
    case transcriberUnavailable(String)
    case pasteboardBusy
    case llmCleanupFailed(String)
    case sessionCancelled
    case unknown(String)

    public var recoverySuggestion: String {
        switch self {
        case .microphoneDenied:      return "Open System Settings → Privacy → Microphone and enable speak."
        case .accessibilityDenied:   return "Open System Settings → Privacy → Accessibility and enable speak."
        case .inputMonitoringDenied: return "Open System Settings → Privacy → Input Monitoring and enable speak."
        case .transcriberUnavailable(let m): return "Speech engine unavailable: \(m). Try a fallback engine in Settings."
        case .pasteboardBusy:        return "Pasteboard busy. Retry in a moment."
        case .llmCleanupFailed(let m): return "LLM cleanup failed: \(m). Showing raw transcript."
        case .sessionCancelled:      return "Session cancelled."
        case .unknown(let m):        return "Unknown error: \(m)."
        }
    }
}
```

---

## 7. State machines

### 7.1 CaptureSession

```
idle ──start()──► listening ──stop()──► processing ──paste ok──► done
  ▲                  │                     │
  │                  │ hotkey/err          │ paste/llm err
  └──────────────────┴─────────────────────┴──► error → idle (reset)
```

The `processing` state executes in sequence:
1. **Finalize transcript** — collect the last finalized `TranscriptChunk`(s) from the STT stream.
2. **Cleanup pass** (if enabled) — call `cleaner.clean(rawText, mode: .punctuation)` via `FoundationModelsCleaner` (v0 default). If the engine is unavailable (`isAvailable == false`) or returns an error, fall back to `rawText` and set `cleanedText = nil`. Cleanup is skippable via the settings toggle — when off, always use `rawText`.
3. **Paste** — write `cleanedText ?? rawText` to `NSPasteboard` and simulate `Cmd+V`.

Budget for the full `processing` sequence: ~1.5–2 s including on-device cleanup (see §12).

| From | Event | To |
|---|---|---|
| idle | `start()` | listening |
| listening | `stop()` | processing |
| listening | error / cancel | error → idle |
| processing | finalize → cleanup (if on) → paste success | done → idle |
| processing | cleanup unavailable | fallback to raw → paste → done → idle |
| processing | paste/llm failure (hard) | error → idle |

### 7.2 PermissionState (per `PermissionKind`)

```
notDetermined ──request()──► requesting ──granted──► granted
                                  │              └──denied──► denied
                                  │
                          (user changes System Settings)
                                  ▼
                        granted ↔ denied (observed via polling / notifications)
```

---

## 8. Concurrency model

- **`SpeakEngine` and `CaptureSession` are `actor`s.** All session mutation is
  serialized through the actor.
- **`@MainActor` boundary**: all UI (menubar, overlay, settings) and the
  `HotkeyMonitor` callbacks that drive UI run on `@MainActor`.
- **Partial results stream** from the transcriber (background task) to the
  overlay (MainActor) via `AsyncStream` + `MainActor.run { ... }`.
- **Cancellation**: `CaptureSession.cancel()` propagates via structured
  concurrency (`Task.cancel()`); the transcriber's stream closes cooperatively.
- **Never block the main thread.** Audio capture uses `AVAudioEngine`
  install-tap callbacks (background queue); transcription is async.

---

## 9. Apple framework integration map

| Framework | Symbol used | Role |
|---|---|---|
| `AVFoundation` | `AVAudioEngine`, `AVAudioInputNode` | mic capture, 16kHz mono PCM |
| `Speech` | `SpeechAnalyzer`, `SpeechTranscriber`, `AudioInput` | `[verified]` on-device STT, macOS 26+ |
| `ApplicationServices` | `CGEventTap`, `CGEvent`, `CGEventSource` | global Fn detection + Cmd+V simulation |
| `AppKit` | `NSPasteboard`, `NSStatusItem`, `NSWorkspace` | paste write, menubar, focused-app detection |
| `SwiftUI` | `MenuBarExtra`, `Settings`, `@AppStorage` | UI shell, settings persistence |
| `FoundationModels` | `LanguageModelSession`, `LanguageModel` | `[verified]` on-device LLM for cleanup; macOS 26, Apple Silicon + Neural Engine |
| `os` | `Logger` | structured logging (no `print`) |
| `Security` | Hardened Runtime, notarization | Gatekeeper compliance |
| `Accessibility` | `AXUIElement` (v1) | per-app paste fallback |

---

## 10. STT strategy (pluggable, Apple-first)

### 10.1 The `Transcribing` protocol

Engines are selected at runtime from settings. The default factory:

```swift
func defaultTranscriber(for settings: SettingsStore) -> any Transcribing {
    switch settings.sttEngine {
    case .appleSpeech: return AppleSpeechTranscriber()     // v0 default
    case .whisperKit:  return WhisperKitTranscriber()      // v0.1
    case .whisperCpp:  return WhisperCppTranscriber()      // v1
    }
}
```

This is the **FluidVoice pattern** (`[verified]` — FluidVoice ships Nemotron,
Parakeet, Cohere, Apple Speech, Whisper as pluggable engines). It is the
architectural role model for `SpeakCore`.

### 10.2 v0 engine: Apple `SpeechAnalyzer`

- **API shape**: `SpeechAnalyzer` → `SpeechTranscriber` → `AudioInput` →
  `AnalysisResult`. Supports final + partial results, custom vocabulary,
  multiple locales. `[verified]`
- **Constraint**: macOS 26+, Apple Silicon.
- **Why default**: zero cost, zero cloud, zero model download, lowest latency.

### 10.3 STT fallback ladder

| Version | Engine | Use case |
|---|---|---|
| **v0** | Apple SpeechAnalyzer | default, en-US |
| v0.1 | WhisperKit (Argmax) | better accuracy, 99 languages |
| v1 | whisper.cpp | Intel Mac support |
| v1+ | NVIDIA Parakeet / cloud Whisper | opt-in cloud accuracy |

---

## 10a. Cleanup strategy (pluggable, Apple-first)

Mirrors the STT design exactly: a `LLMCleaning` protocol, a default factory,
and a fallback ladder. Cleanup is a **v0 CORE concern**, not an add-on.

### 10a.1 The `LLMCleaning` protocol

Engines are selected at runtime from settings. The default factory:

```swift
func defaultCleaner(for settings: SettingsStore) -> (any LLMCleaning)? {
    guard settings.cleanupEnabled else { return nil }   // toggle: off → raw transcript
    switch settings.cleanupEngine {
    case .foundationModels: return FoundationModelsCleaner()  // v0 default
    case .ollama(let model): return OllamaCleaner(model: model) // v0.1
    }
}
```

If `defaultCleaner` returns `nil` (toggle off) or the engine's `isAvailable`
returns `false` at runtime, `CaptureSession` falls back to raw transcript
(`cleanedText = nil`) without error — the paste still succeeds.

### 10a.2 v0 engine: Apple `Foundation Models`

- **Framework**: `FoundationModels` (macOS 26, Apple Silicon + Neural Engine).
  `[verified]` Apple framework — does NOT count as a third-party dependency.
- **Key type**: `LanguageModelSession` (stateful session; reuse across
  dictations). The underlying model is the same one powering Writing Tools.
- **Constraint**: macOS 26+, Apple Silicon.
- **Why default**: zero third-party dep, no model download, on-device, free,
  improves with the OS. Latency target: ~1–1.5 s for a typical 30-word chunk.

### 10a.3 Cleanup fallback ladder

| Version | Engine | Notes |
|---|---|---|
| **v0** | `FoundationModelsCleaner` (Apple `Foundation Models`) | default; Apple framework; zero deps |
| v0.1 | `OllamaCleaner` (Qwen 2.5 3B / Gemma 3 4B / Phi-4-mini via Ollama) | user-swappable; requires Ollama installed |
| v0.1 | MLX models | power-user local models via MLX |
| v1 | richer modes (tone/style/per-app/custom vocabulary) | `CleanupMode` extensions |
| fallback | raw transcript | always available; cleanup skippable via toggle |

---

## 11. Paste flow (the macOS 26.4 wrinkle)

macOS 26.4 introduced **Paste Protection** — apps that programmatically
*read* the pasteboard trigger a user permission prompt. `[verified]`

**The fix (do exactly this — WRITE, never READ):**

```swift
final class PasteboardWriter {
    func paste(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)  // WRITE, never read
        simulateCmdV()
    }

    private func simulateCmdV() {
        let source = CGEventSource(stateID: .hidSystemState)
        let vDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true) // kVK_ANSI_V
        vDown?.flags = .maskCommand
        vDown?.post(tap: .cghidEventTap)
        let vUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false)
        vUp?.flags = .maskCommand
        vUp?.post(tap: .cghidEventTap)
    }
}
```

Works in ~95% of apps. Document edge cases: Terminal/iTerm (different paste
handling), password fields, some Electron apps. Per-app accessibility API
(`AXUIElement`) paste is a **v1** enhancement.

---

## 12. Performance budgets (hot paths)

| Path | Target p50 | Target p95 |
|---|---|---|
| Hotkey press → listening state | **< 50 ms** | < 100 ms |
| First partial result → overlay | **< 100 ms** | < 200 ms |
| Stop → text pasted (no LLM) | **< 500 ms** | < 800 ms |
| Stop → text pasted (LLM cleanup) | < 1500 ms | < 2500 ms |
| Full round-trip, 30s speech | **< 2 s** | < 3 s |
| CPU during capture | < 5% | < 12% |
| Memory (idle / listening) | < 60 MB | < 120 MB |
| Battery drain over 1h continuous | < 8% | < 15% |

These are opinionated targets — measure with XCTest performance tests in v0
and tune. `[inferred]` from Whisper/SpeechAnalyzer latency profiles.

---

## 13. Anti-patterns (do not do these)

- No global mutable state.
- No third-party dependencies in v0.
- No `print` for logging — use `os.Logger`.
- No blocking the main thread.
- No force-unwraps / `try!` / `as!` outside test code.
- No `[weak self]` omissions in long-lived closures.
- No cloud calls by default.
- No reading the pasteboard — only write.
- No invented Apple APIs. If unsure an API exists, search the docs; if you
  can't find it, mark it `[inferred]` and explain.

---

## 14. Claims to verify on day 0 (load-bearing)

Before coding, the agent should re-confirm these against primary sources. All
are `[verified]` as of 2026-06-18; re-check on first build.

1. **Apple `SpeechAnalyzer`** exists, on-device, macOS 26+, Apple Silicon.
   `[verified]`
   — [developer.apple.com/documentation/speech/speechanalyzer](https://developer.apple.com/documentation/speech/speechanalyzer),
   [WWDC25 session 277](https://developer.apple.com/videos/play/wwdc2025/277/)
2. **Apple `Foundation Models` framework** exists, on-device LLM, macOS 26+,
   Apple Silicon + Neural Engine. `[verified]` (WWDC25; same model as Writing
   Tools; confirmed in `specs/verification-ledger.md` §1.)
   — Verify `LanguageModelSession` API shape against current Xcode 26 headers.
3. **`NSPasteboard` write-only (never read)** avoids the macOS 26.4 pasteboard
   read-prompt. `[verified]` (general mechanism — the read prompt fires on
   *read*, not write.)
   **`NSPasteboard` write + simulated `Cmd+V` bypass** the paste-provenance
   check in Terminal/iTerm. `[unverified]` — macOS 26.4 added a
   paste-provenance check (`_sourceSigningIdentifier`, ~74-app list) that fires
   at paste time. No primary source confirms the write+Cmd+V path bypasses it.
   **Empirically test at P6, especially Terminal and iTerm, before relying on
   it.** Reference: Michael Tsai blog, 2026-04-03.
4. **`CGEventTap`** requires Accessibility + Input Monitoring on macOS 26.
   `[verified]`
5. **`WhisperKit`** (Argmax) current version, MIT license, Apple Silicon.
   `[verified]`
   — [github.com/argmaxinc/argmax-oss-swift](https://github.com/argmaxinc/argmax-oss-swift)
6. **Ollama MLX** backend + model list (Qwen 2.5 3B, Gemma 3 4B, Phi-4-mini).
   `[verified]`
7. **Homebrew Cask** submission + review SLA.
   — [brew.sh Cask Cookbook](https://docs.brew.sh/Cask-Cookbook)

If any contradicts a primary source, **stop and surface it** before coding.
