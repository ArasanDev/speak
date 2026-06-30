# `speak` — Product & Build Specification (Single Source of Truth)

> **Status**: Authoritative spec v1.0. This document **supersedes** the conflicting
> recommendations across `SPEAK_PRODUCT_SPEC.md`, `SPEAK_PLATFORM_MODEL.md`,
> `SPEAK_ARCHITECTURE_VERIFICATION.md`, `SPEAK_LANGUAGE_CORRECTION.md`,
> `SPEAK_DICTATION_STACKS.md`, and `TECH_STACK_JUDGMENT.md`.
> Where those docs disagree, **this one wins.**
>
> **Date**: 2026-06-19
> **Working dir**: `/Users/tamil/Developers/deepvoice`
> **Convention**: every non-trivial technical claim is tagged
> `[verified]` (primary source) or `[inferred]` (indirect). Sources are
> linked inline and consolidated in §13.
>
> **How to use this file**: read it top to bottom once. Then implement
> strictly from §6–§12. Do **not** re-open the language debate
> (§4 explains why it is settled). Flag anything that contradicts
> primary sources you can verify, but pick a path and move on — the
> user wants a shipped product, not a survey.

---

## 0. TL;DR (read this first)

**`speak`** is a **macOS-native, local-first, free, open-source voice
dictation app** for developers and writers. It is the free, private
alternative to **Wispr Flow** ($15/mo, cloud-only).

- **One sentence**: *The Mac-native, free, local-first voice dictation
  app for people who don't want their audio in someone else's cloud.*
- **Stack (v0)**: **Swift + SwiftUI, single codebase, no FFI, no
  cross-platform framework.** `[verified]` — all 8 shipping Mac
  dictation apps (Wispr, Willow, Superwhisper, Aiko, MacWhisper,
  VoiceInk, FluidVoice, TypeWhisper) are Swift-native.
- **STT**: **Apple `SpeechAnalyzer`** (on-device, macOS 26+) as the
  default, with a **pluggable engine protocol** so WhisperKit /
  whisper.cpp / Parakeet drop in later. `[verified]`
- **UX**: double-tap **Fn** to start, single-tap **Fn** to stop & paste.
  Customizable from v0.
- **Paste**: write to `NSPasteboard`, simulate `Cmd+V`. Never read the
  pasteboard (macOS 26.4 paste protection). `[verified]`
- **Distribution**: Homebrew Cask + `.dmg`, MIT license, Apple Silicon
  only, macOS 26+. v0 ships in **2 weeks**.
- **Three durable differentiators**: (1) local + free + open source,
  (2) Apple SpeechAnalyzer first, (3) developer-first hotkey/UX.

---

## 1. Product definition

### 1.1 What `speak` is

A **menubar app** that sits idle until you tap a hotkey, captures your
microphone, transcribes speech on-device, optionally cleans it up with a
local LLM, and pastes the result at your cursor. It is a **sophisticated
typewriter** — no agentic loop, no chat, no cloud. The transcript is the
only artifact.

### 1.2 What `speak` is NOT (non-goals — do not build these in v0)

- **Not** an agentic coding tool. (That was the abandoned `deepvoice`
  Direction A. It lives in `ai_docs/sample-ideation.md` for reference
  only — do not build it.)
- **Not** a chatbot, not a voice assistant, not a meeting scribe.
- **Not** cross-platform in v0. Mac + Apple Silicon only.
- **Not** cloud. No accounts, no login, no telemetry, no audio leaves
  the device. Ever. (Cloud STT is a v1 *opt-in* escape hatch only.)
- **Not** a code-aware formatter in v0. (v2.)

### 1.3 Personas

| Persona | Primary pain with Wispr Flow |
|---|---|
| Developer on MacBook M-series | $15/mo, audio in cloud, no local option |
| Writer on MacBook | Same + wants offline (planes, trains) |
| Accessibility user (RSI) | Same + needs *free* vs $15/mo |
| Privacy-sensitive (lawyer, doctor, journalist) | **Cloud-only is a deal-breaker** |

### 1.4 Why now (the window is open)

- Apple shipped **`SpeechAnalyzer`** in macOS 26 (2025-Q4) — first-party
  on-device STT that didn't exist before. The technical barrier dropped.
  `[verified]`
- Wispr Flow is **polishing, not shipping features** (March 2026
  updates = notification UI + sleep recovery), and is **expanding to
  new platforms** (Windows/Linux) rather than deepening the Mac
  experience. `[verified]`

---

## 2. Positioning & differentiation

**Position**: the only 2026 Mac dictation app that is **simultaneously
local-only, free, and open source.**

### Differentiation matrix

| Feature | Wispr Flow | Willow | Superwhisper | Aiko | VoiceInk | FluidVoice | **speak** |
|---|---|---|---|---|---|---|---|
| Price | $15/mo | Paid | $9.99/mo | Free | Paid | Free | **Free** |
| Open source | No | No | No | Yes | Yes (GPL) | Yes (GPL) | **Yes (MIT)** |
| Local-only | No (cloud) | Hybrid | Hybrid | Yes | Opt-in | Yes | **Yes** |
| Apple SpeechAnalyzer default | No | No | No | No | No | Opt-in | **Yes** |
| Fn double-tap hotkey | No | No | No | No | No | No | **Yes** |
| Pluggable STT | No | No | No | No | Some | **Yes** | **Yes** |
| Local LLM cleanup | No | No | No | No | No | Some | **Yes (v0.1)** |

### The three durable moats (don't lose these)

1. **Local + free + open source** — community + trust. Wispr cannot copy
   this without abandoning its cloud revenue model.
2. **Apple SpeechAnalyzer first** — fastest on Apple Silicon, no model
   download, no licensing, gets better with OS updates for free.
3. **Developer-first UX** — Fn double-tap, customizable hotkeys,
   scriptable CLI shim, code-aware mode (v2).

---

## 3. Hard constraints (non-negotiable for v0)

These are locked. The agent must not trade them away without explicit
user approval.

1. **100% local by default.** No cloud audio. No telemetry to a server.
   No accounts. No login.
2. **Three OS permissions, no more**: Microphone, Accessibility, Input
   Monitoring. Onboarding must explain *why* each is needed and
   deep-link to System Settings.
3. **Swift 5.9+ / SwiftUI**, deployment target **macOS 26.0**,
   **Apple Silicon only** in v0.
4. **No third-party dependencies in v0.** Apple frameworks only.
   WhisperKit / Ollama arrive in v0.1+.
5. **Single Swift codebase.** No Rust core. No FFI layer. No
   cross-platform abstraction. (See §4 for why.)
6. **Never read the pasteboard** — only write to it. (macOS 26.4 paste
   protection.)
7. **Hardware mute impossible to bypass** — when muted, no audio is
   captured, period.
8. **v0 ships in 2 weeks (14 working days)**, single senior engineer.

---

## 4. The settled decision: Swift-native, single codebase (do not relitigate)

The earlier research documents disagreed on architecture. This section
records **why the debate is over** so a future agent doesn't reopen it.

### 4.1 The debate that happened

- `SPEAK_PLATFORM_MODEL.md` recommended a **Rust core + per-platform
  shells + uniffi FFI** ("portable-ready, Mac-first").
- `SPEAK_ARCHITECTURE_VERIFICATION.md` claimed this was "confirmed"
  because "both Anthropic and OpenAI rewrote to Rust."
- `SPEAK_LANGUAGE_CORRECTION.md` then proved the factual claim **wrong**:
  Claude Code is **TypeScript + Bun**, not Rust (`[verified]` via the
  local binary containing `---- Bun! ----` and the 2026-03-31 source
  leak of 512K lines of TypeScript).
- `SPEAK_DICTATION_STACKS.md` verified the actual dictation-app
  category: **all 8 shipping Mac dictation apps are Swift-native.**
  No Rust, no TypeScript, no Electron, no Tauri in this product
  category. `[verified]`
- `TECH_STACK_JUDGMENT.md` codified the root cause of the error: the
  Rust recommendation was based on the **wrong category**
  (cross-platform desktop frameworks like Firefox/Deno/Tauri), not the
  **right category** (Mac-first dictation apps).

### 4.2 The verdict (final)

> **v0 = a single Swift codebase. No Rust. No FFI. No cross-platform
> layer.**

**Why this is right (the evidence):**
- 8/8 production Mac dictation apps are Swift-native. `[verified]`
- The macOS-specific APIs that define the product
  (`SpeechAnalyzer`, `CGEventTap`, `NSPasteboard`, `NSStatusItem`,
  `AVAudioEngine`, Apple Intelligence) are Swift-first or Swift-only.
- The performance bar is high (sub-100ms partial-result latency) and
  Swift + native Apple frameworks deliver it with the smallest binary
  and lowest latency of any option.
- A "Rust core + Swift shell + uniffi" split adds two toolchains, FFI
  marshalling, and design overhead for **zero v0 benefit** — the engine
  logic (STT orchestration, history, settings) is trivially expressed
  in Swift.

**Why the Rust/TS debate was a category error:** that debate applies to
**cross-platform desktop frameworks** (VS Code, Discord, Zed, Deno). It
does **not** apply to Mac-first dictation menubar apps. Different
category, different correct answer.

### 4.3 The v1+ portability seam (preserve it, don't build it)

If Windows ever becomes a real target, the engine logic
(`SpeechTranscriber` orchestration, `HistoryStore`, `SettingsStore`)
should be **extracted** into a portable module (Rust or TypeScript+Bun,
both production-proven) and the Mac shell kept Swift. **But this is v1+
work.** For v0, we preserve the seam by keeping engine logic in a
**separate Swift framework (`SpeakCore`)** with clean protocol
boundaries — so extraction is possible later without a rewrite.

```
v0 (now):    Speak.app (SwiftUI) ──► SpeakCore.framework (Swift)
v1+ (maybe): Speak.app (SwiftUI) ──► SpeakCore.framework (Swift) ──ffi──► portable engine (Rust/TS)
```

**Build the seam, not the second layer.**

---

## 5. Tech stack (decisive)

| Layer | Choice | Rationale |
|---|---|---|
| Language | **Swift 5.9+** | `[verified]` dominant pattern for Mac dictation apps |
| UI | **SwiftUI** (`MenuBarExtra`, `Settings`) | macOS 13+ native; modern |
| Mic capture | **`AVAudioEngine`** | Standard real-time audio API |
| STT (default) | **Apple `SpeechAnalyzer`** (`Speech` framework) | `[verified]` macOS 26+, on-device, free |
| STT (protocol) | **pluggable `Transcribing` protocol** | FluidVoice pattern; allows WhisperKit/whisper.cpp/Parakeet later |
| Hotkey | **`CGEventTap`** (Accessibility + Input Monitoring) | `[verified]` only way to detect Fn globally |
| Paste | **`NSPasteboard` write + `CGEvent` Cmd+V** | `[verified]` avoids 26.4 paste prompt |
| Menubar | **`NSStatusItem` / `MenuBarExtra`** | native surface |
| Persistence | **SQLite** (history) + **`UserDefaults`** (settings) | standard |
| Logging | **`os.Logger` (OSLog)** | native, performant, no `print` |
| LLM cleanup (v0.1) | **Ollama MLX** (opt-in); Apple Intelligence (v1) | local, optional |
| Distribution | **Homebrew Cask + `.dmg`** (v0); Mac App Store (v1+) | discovery vs. sandbox tradeoff |
| License | **MIT** | community moat; matches Aiko; less restrictive than competitors' GPL |
| Code signing | **Developer ID + notarization** | required for Gatekeeper on macOS 26 |
| Sandbox | **NOT sandboxed in v0** | sandboxing blocks global hotkeys + Cmd+V simulation; MAS (sandboxed) deferred to v1+ |

---

## 6. Core UX & flows

### 6.1 The headline flow (must be perfect)

1. User **double-taps Fn** (400ms window).
2. Menubar icon turns **red**; optional floating overlay appears.
3. User speaks; **partial transcript streams** live in the overlay.
4. User **single-taps Fn**.
5. Status: **processing** (yellow, ~100–500ms; ~1–2s if LLM cleanup on).
6. Text is **pasted at cursor** via simulated `Cmd+V`.
7. Menubar returns to **idle**.

### 6.2 Hotkey spec (the Fn double-tap)

- **Default**: double-tap Fn = start, single-tap Fn = stop & paste.
- **Why Fn**: corner of every MacBook keyboard, easy reach, no holding
  required (good for RSI).
- **Fn sends a unique event**: `kVK_Function` (0x3F). It is *not* an
  F-key. `[inferred]` from macOS keyboard docs.
- **Double-tap is custom**: no macOS API emits a "double-tap Fn" event.
  We monitor the key, timestamp, count taps within a **400ms window**.
  `[verified]` pattern (Keyboard Maestro, `yulrizka/osx-push-to-talk`).
- **Tradeoffs** (documented for users): slower to start (two taps),
  first tap can be a false start, Fn behavior differs on external
  keyboards (may be "Globe"), users may have toggled "Use F-keys as
  standard."
- **Mitigation**: **customizable hotkey from v0.** Support F-keys,
  single-key toggle, modifier combos, double-tap-Cmd (familiar from
  Spotlight/Alfred). Persisted in `UserDefaults`.

### 6.3 Paste flow (the macOS 26.4 wrinkle)

macOS 26.4 introduced **Paste Protection** — apps that programmatically
*read* the pasteboard trigger a user permission prompt. `[verified]`

**The fix (do exactly this):**
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
Works in ~95% of apps. Document edge cases: Terminal/iTerm (different
paste handling), password fields, some Electron apps. Per-app
accessibility API (`AXUIElement`) paste is a **v1** enhancement.

### 6.4 First-run onboarding (3 permissions, < 90 seconds)

1. Welcome: what `speak` is, why it's local-first.
2. **Microphone** permission (with rationale).
3. **Accessibility** permission (deep-link to System Settings).
4. **Input Monitoring** permission (deep-link).
5. Hotkey picker (default double-tap Fn, with alternatives shown).
6. Test dictation: "say something to test your setup."
7. Done.

**Critical**: 3 prompts is a lot. The flow must explain *why* each is
needed with a screenshot of the System Settings pane. Dropping users
here is a top-3 risk (see §12).

### 6.5 Streaming UX states

| State | Menubar | Overlay |
|---|---|---|
| Idle | gray waveform | none |
| Listening | red dot | visible, streaming partial text |
| Processing | yellow spinner | frozen text + spinner |
| Done | green flash → gray | fades out, text pasted |
| Error | red X | error message + retry |

---

## 7. Architecture

### 7.1 System context (C4 L1)

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

### 7.2 Containers (C4 L2)

Two deployable units in v0:
- **`speak.app`** — the SwiftUI menubar app the user runs.
- **`SpeakCore.framework`** — the headless dictation engine, embedded in
  the app. (Separated so a future CLI shim / iOS app / extracted
  portable engine can reuse it.)

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
│  │   PermissionManager · HistoryStore     │ │
│  │   SettingsStore · (LLMCleanup v0.1)    │ │
│  └────────────────────────────────────────┘ │
└─────────────────────────────────────────────┘
```

### 7.3 Module layout

```
speak/
  App/                          # SwiftUI app target
    SpeakApp.swift              # @main, MenuBarExtra, state injection
    MenuBar/                    # icon, status, quick toggles
    Onboarding/                 # 3-permission flow, hotkey picker
    Settings/                   # hotkey, language, LLM, history, paste mode
    Overlay/                    # floating capture dot + partial transcript
  SpeakCore/                    # Framework: headless dictation engine
    Engine/
      SpeakEngine.swift         # owns the session lifecycle (actor)
      CaptureSession.swift      # idle → listening → processing → done | error
    Audio/
      AudioCapture.swift        # AVAudioEngine wrapper, 16kHz mono PCM
    Hotkey/
      HotkeyMonitor.swift       # CGEventTap, double-tap detection, rebind
    STT/
      Transcriber.swift         # protocol `Transcribing`
      AppleSpeechTranscriber.swift   # SpeechAnalyzer impl (v0 default)
      # WhisperKitTranscriber.swift  (v0.1)
      # WhisperCppTranscriber.swift  (v1, Intel)
    Paste/
      PasteboardWriter.swift    # NSPasteboard write + Cmd+V simulate
    Permissions/
      PermissionManager.swift   # mic/accessibility/input-monitoring state machine
    Storage/
      HistoryStore.swift        # SQLite, last N dictations, searchable
      SettingsStore.swift       # typed UserDefaults wrapper
    Logging/
      SpeakLog.swift            # OSLog categories
  SpeakLLM/                     # (v0.1) optional: Ollama client + prompts
    OllamaClient.swift
    CleanupPrompt.swift
  SpeakCLI/                     # (v0.1, optional) `speak --start` shim
    SpeakCLI.swift
  SpeakTests/                   # XCTest unit + XCUITest UI
  Resources/
    Info.plist                  # usage descriptions
    Assets.xcassets             # app icon, menubar icons
    speak.cask.rb               # Homebrew Cask formula (in dist/)
```

### 7.4 Key types (Swift signatures — implement verbatim)

```swift
// SpeakCore/STT/Transcriber.swift
public protocol Transcribing: Sendable {
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
    public enum Trigger: Codable, Sendable { case doubleTap, singleTapToggle, hold }
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
    public var recoverySuggestion: String { /* per-case guidance */ }
}
```

### 7.5 State machines

**CaptureSession**:
```
idle ──start()──► listening ──stop()──► processing ──paste ok──► done
  ▲                  │                     │
  │                  │ hotkey/err          │ paste/llm err
  └──────────────────┴─────────────────────┴──► error → idle (reset)
```

**PermissionState** (per permission kind):
```
notDetermined ──request()──► requesting ──granted──► granted
                                  │              └──denied──► denied
                                  │
                            (user changes System Settings)
                                  ▼
                        granted ↔ denied (observed via polling / notifications)
```

### 7.6 Concurrency model

- **`SpeakEngine` and `CaptureSession` are `actor`s.** All session
  mutation is serialized through the actor.
- **`MainActor` boundary**: all UI (menubar, overlay, settings) and the
  `HotkeyMonitor` callbacks that drive UI run on `MainActor`.
- **Partial results stream** from the transcriber (background task) to
  the overlay (MainActor) via `AsyncStream` + `MainActor.run { ... }`.
- **Cancellation**: `CaptureSession.cancel()` propagates via structured
  concurrency (`Task.cancel()`); the transcriber's stream closes
  cooperatively.
- **Never block the main thread.** Audio capture uses `AVAudioEngine`
  install-tap callbacks (background queue); transcription is async.

### 7.7 Apple framework integration map

| Framework | Symbol used | Role |
|---|---|---|
| `AVFoundation` | `AVAudioEngine`, `AVAudioInputNode` | mic capture, 16kHz mono PCM |
| `Speech` | `SpeechAnalyzer`, `SpeechTranscriber`, `AudioInput` | `[verified]` on-device STT, macOS 26+ |
| `ApplicationServices` | `CGEventTap`, `CGEvent`, `CGEventSource` | global Fn detection + Cmd+V simulation |
| `AppKit` | `NSPasteboard`, `NSStatusItem`, `NSWorkspace` | paste write, menubar, focused-app detection |
| `SwiftUI` | `MenuBarExtra`, `Settings`, `@AppStorage` | UI shell, settings persistence |
| `os` | `Logger` | structured logging (no `print`) |
| `Security` | Hardened Runtime, notarization | Gatekeeper compliance |
| `Accessibility` | `AXUIElement` (v1) | per-app paste fallback |

### 7.8 Performance budgets (hot paths)

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

These numbers are opinionated targets — measure with XCTest performance
tests in v0 and tune. `[inferred]` from Whisper/SpeechAnalyzer latency
profiles.

---

## 8. STT strategy (pluggable, Apple-first)

### 8.1 The `Transcribing` protocol

```swift
public protocol Transcribing: Sendable {
    func startStream(locale: Locale) -> AsyncThrowingStream<TranscriptChunk, Error>
    func stop() async
    var id: String { get }
}
```

Engines are selected at runtime from settings. The default factory:

```swift
func defaultTranscriber(for settings: SettingsStore) -> any Transcribing {
    switch settings.sttEngine {
    case .appleSpeech:   return AppleSpeechTranscriber()
    case .whisperKit:    return WhisperKitTranscriber()    // v0.1
    case .whisperCpp:    return WhisperCppTranscriber()    // v1
    }
}
```

This is the **FluidVoice pattern** (`[verified]` — FluidVoice ships
Nemotron, Parakeet, Cohere, Apple Speech, Whisper as pluggable engines).
It is the architectural role model for `SpeakCore`.

### 8.2 v0 engine: Apple `SpeechAnalyzer`

- **API shape**: `SpeechAnalyzer` → `SpeechTranscriber` → `AudioInput`
  → `AnalysisResult`. Supports final + partial results, custom
  vocabulary, multiple locales. `[verified]`
- **Constraint**: macOS 26+, Apple Silicon.
- **Why default**: zero cost, zero cloud, zero model download, lowest
  latency on Apple Silicon, improves with OS updates.

### 8.3 Fallback ladder

| Version | Engine | Use case |
|---|---|---|
| **v0** | Apple SpeechAnalyzer | default, en-US |
| v0.1 | WhisperKit (Argmax) | better accuracy, more languages (99) |
| v1 | whisper.cpp | Intel Mac support |
| v1 | Apple Intelligence Writing Tools | free cleanup, no Ollama dep |
| v1+ | NVIDIA Parakeet / cloud Whisper | opt-in cloud accuracy |

### 8.4 Custom vocabulary (v0.1+)

A `vocabulary.txt` of domain terms (API names, teammate names, jargon)
fed to `SpeechAnalyzer`. Critical for developer dictation accuracy.

---

## 9. LLM cleanup (optional, layered, off by default)

Pure STT is enough for v0. LLM cleanup is the **differentiator vs
Wispr's cloud cleanup** — done locally.

### 9.1 Cleanup transforms

- Filler removal ("um", "uh", "like") — on by default
- Punctuation & capitalization
- Number formatting ("twenty three thousand" → "23,000")
- Tone adjustment (conversational → email/Slack)
- Translation (dictate in X, paste in Y)
- Code-aware mode ("function add paren a comma b close paren" →
  `function add(a, b)`) — **v2**

### 9.2 Provider ladder

| Version | Provider | Latency | Setup |
|---|---|---|---|
| v0 | none | — | — |
| **v0.1** | **Ollama + MLX** (Qwen 2.5 3B / Gemma 3 4B / Phi-4-mini) | ~1–2s / 100 words | user installs Ollama |
| v1 | Apple Intelligence Writing Tools | < 1s | none (built into macOS 26) |
| v1+ | cloud LLM (opt-in) | varies | API key |

### 9.3 Streaming UX when cleanup is on

User sees the live partial transcript → brief pause (~1–2s) → cleaned
final text pastes. During the pause, offer an **"Original / Cleaned"
toggle** on the overlay. User can disable cleanup per-session.

---

## 10. Permissions & privacy

### 10.1 The three permissions

| Permission | `Info.plist` key / gate | Why needed |
|---|---|---|
| Microphone | `NSMicrophoneUsageDescription` | capture speech |
| Accessibility | TCC | monitor global keyboard (`CGEventTap`), simulate `Cmd+V` |
| Input Monitoring | TCC (macOS 10.15+) | receive keystrokes from other apps |

`NSSpeechRecognitionUsageDescription` is **not** needed (SpeechAnalyzer
supersedes the legacy `SFSpeechRecognizer`). `[inferred]`

### 10.2 Privacy guarantees (put these in the README)

1. **No audio leaves the device.** Ever. (Cloud is opt-in, v1+.)
2. **No accounts, no login, no telemetry.** v0 sends nothing anywhere.
3. **Transcripts stay local** in `~/Library/Application Support/speak/`.
4. **Hardware mute**: a configurable chord toggles capture; when muted,
   no audio is read from the mic at all.
5. **History is user-owned**: clearable, exportable, never synced.

---

## 11. Scope by version

### v0 (2 weeks — the critical path) — see §12

macOS 26+, Apple Silicon, Swift/SwiftUI, Apple SpeechAnalyzer (en-US),
double-tap/single-tap Fn + custom hotkeys, Cmd+V paste, menubar UI,
3-permission onboarding, history (last 50, SQLite), MIT, Homebrew Cask +
`.dmg`. **No LLM, no cloud, no third-party deps.**

### v0.1 (weeks 3–4)

Optional Ollama cleanup, snippets/text replacements, more languages
(en-GB, hi-IN, …), WhisperKit fallback, logs/latency metrics, CLI shim
(`speak --start/--stop`).

### v1 (month 2)

Apple Intelligence Writing Tools integration (free cleanup, no Ollama
dep), cloud STT opt-in (user supplies API key), Intel Mac support
(whisper.cpp), Mac App Store build (sandboxed variant).

### v2 (months 3–4)

Code-aware mode (auto-detect code context), iOS/iPadOS sync, snippet
library + import/export, team/on-prem plan.

### Explicit non-goals (all versions until stated)

No agentic loop (that's the abandoned `deepvoice`), no Windows/Linux in
v0/v1 (v2+ only, and only via the §4.3 extraction seam).

---

## 12. Build roadmap (the 14-day v0 plan)

> Ordered by dependency, not by date. "Done when" criteria are
> **testable** (binary pass/fail). A single senior engineer should
> complete this in 14 working days.

| # | Phase | Task | Effort | Done when |
|---|---|---|---|---|
| 0 | Repo setup | `git init`, Xcode project (app + `SpeakCore.framework` + `SpeakTests`), dir layout (§7.3), `README.md`, `LICENSE` (MIT), `.gitignore`, `.swift-version` (5.9+), `Makefile`/`justfile`, GitHub Actions CI (build + `swiftlint`) | M | `make build` produces a runnable `.app` from a clean clone |
| 1 | Menubar scaffold | `MenuBarExtra` with idle icon + "About" panel | S | `speak` shows in menubar, panel opens |
| 2 | Audio capture | `PermissionManager` (mic) + `AudioCapture` (`AVAudioEngine`, 16kHz mono) | M | speak into mic → raw PCM buffer logged via OSLog |
| 3 | SpeechAnalyzer | `Transcribing` protocol + `AppleSpeechTranscriber` | M | spoken audio → partial + final text in console |
| 4 | Partial overlay | floating overlay streams partial transcript | S | speak → see live text in overlay |
| 5 | Hotkey | `HotkeyMonitor` (`CGEventTap`), double-tap Fn (400ms), single-tap Fn | L | Fn keys trigger start/stop; works while another app has focus |
| 6 | Paste | `PasteboardWriter` (write + Cmd+V) + state wiring | M | final text pastes into TextEdit, Slack, Terminal |
| 7 | Permissions flow | Accessibility + Input Monitoring prompts, deep-links to System Settings | M | fresh user grants all 3 in < 90 s |
| 8 | Menubar states | idle/listening/processing/done/error icon states | S | icon changes color on state |
| 9 | History | `HistoryStore` (SQLite), last 50, searchable | M | dictations persist + search works across launches |
| 10 | Settings | `SettingsStore` (typed UserDefaults), hotkey rebinding, language, auto-paste toggle | M | settings persist; user can rebind hotkey |
| 11 | Build + sign + notarize + package | Developer ID signing, notarization, `.dmg`, Homebrew Cask formula | L | `brew install --cask speak` works on a clean machine |
| 12 | Docs + demo | `README.md`, screenshots, demo GIF, privacy section | S | repo is public-ready |
| 13 | Dogfood | 4 hours real use: Slack, code comments, terminal, email | M | log latency, false triggers, missed words, permission edges |
| 14 | Fix top 3 | close top dogfood bugs | M | latency < 1s, no false triggers, no permission edge cases |

**Critical path**: 0 → 2 → 3 → 5 → 6 → 11 → 13. If anything slips, it
slips here. (1, 4, 7, 8, 9, 10, 12 can parallelize.)

**First 48 hours (Monday morning start)**: 0 → 1 → 2 → begin 3.

### v0.1 / v1 / v2

Carry forward from §11. Sequence after v0 ships: Ollama cleanup (v0.1)
→ Apple Intelligence + WhisperKit + Intel (v1) → code-aware + iOS (v2).

---

## 13. Validation & testing

Every roadmap task gets test coverage. Three test layers:

### 13.1 Unit tests (`SpeakTests`, XCTest) — by module

- **AudioCapture**: sample rate, format, callback timing.
- **HotkeyMonitor**: single-tap, double-tap within/outside window,
  modifier combos, external-keyboard Fn behavior.
- **SpeechTranscriber**: against a `MockTranscriber` (contract tests);
  engine-id correct; partial→final ordering.
- **PasteboardWriter**: mocked paste; verifies *write* path only,
  never reads pasteboard.
- **PermissionManager**: full state machine (notDetermined→…→granted/denied).
- **HistoryStore**: CRUD, search, last-N limit.
- **SettingsStore**: persistence, validation, hotkey rebind round-trip.
- **(v0.1) LLMCleanup**: mocked; prompt contract; failure → raw text.

### 13.2 Integration tests (real macOS + mic)

- End-to-end dictation in 5 app categories: native macOS, Electron,
  browser, IDE, Terminal.
- Multi-language round-trip (v0.1).
- Long session: 5 min continuous capture, no leak, no crash.
- Background-app behavior (capture continues when `speak` is hidden).

### 13.3 Cross-app compatibility matrix (manual, v0 ship gate)

Test paste + hotkey + no-26.4-prompt in: TextEdit, Notes, Mail,
Messages, Safari, Chrome, VS Code, Cursor, Terminal, iTerm2, Slack,
Discord, Zoom chat, Notion, Linear, GitHub web. Record pass/fail per
app; document known-broken (Electron focus, password fields).

### 13.4 Performance benchmarks

XCTest performance tests for: first-partial latency, e2e latency for
10s/30s/60s speech, CPU%, memory, 1h battery drain. Assert against §7.8
budgets.

### 13.5 Edge & failure cases

Empty audio; < 1s utterance; > 5 min utterance; background noise;
multiple speakers; accented English; **network offline (must work)**;
no microphone / permission denied; **permission revoked mid-session**;
transcriber crash; pasteboard busy; hotkey conflict with another app.

### 13.6 v0 ship checklist (binary gate)

- [ ] `make build` clean from clone
- [ ] All 3 permissions grantable in < 90 s
- [ ] Paste works in ≥ 13/16 apps in the matrix
- [ ] No `print` in codebase (OSLog only)
- [ ] No force-unwraps / `try!` outside tests
- [ ] Signed + notarized; `brew install --cask speak` works
- [ ] 4h dogfood done, top-3 bugs fixed
- [ ] README + privacy section + demo GIF public

---

## 14. Risks (top 12, each with a decision rule)

| # | Risk | L | I | Mitigation | Decision rule ("if X, do Y") |
|---|---|---|---|---|---|
| 1 | SpeechAnalyzer quality worse than Wispr in noise | M | H | WhisperKit fallback (v0.1); document noise limits | If word-error-rate > Wispr's by > 5pts in quiet tests, ship WhisperKit as default |
| 2 | Fn key is OS-controlled, conflicts vary | H | M | Customizable hotkey from v0; document Fn vs F-key | If > 10% of users report Fn doesn't fire, promote a non-Fn default |
| 3 | macOS 26.4 paste protection breaks Cmd+V | L | H | We *write*, never *read* pasteboard | If Cmd+V triggers a prompt in any top-20 app, switch that app to AX paste |
| 4 | 3-permission onboarding drops 30%+ | H | H | Streamlined flow, deep-links, video walkthrough | If dropoff > 25%, add a "skip and configure later" path |
| 5 | Local LLM adds 1–2s latency | M | M | Streaming UI; per-session disable | If median cleanup > 2.5s, default cleanup OFF |
| 6 | Apple closes/changes SpeechAnalyzer access | L | H | Pluggable protocol; WhisperKit ready as fallback | If API deprecated, ship WhisperKit as default in next minor |
| 7 | Wispr Flow copies local-first model | L (2026) | H | Open source + community + MIT moat | Compete on free + open + developer UX, not feature parity |
| 8 | Ollama install friction (non-devs) | H (non-dev) | M | Apple Intelligence in v1 removes the dep | If v0.1 LLM adoption < 20%, prioritize Apple Intelligence for v1 |
| 9 | App Store sandboxing blocks hotkeys/paste | H | M | v0 is non-sandboxed (Homebrew only); MAS in v1 with reduced scope | If MAS rejection, ship Homebrew-only indefinitely |
| 10 | Single-maintainer bus factor | H | M | Clean docs, tests, modular `SpeakCore`; MIT invites contributors | If no commits for 30 days, write a "maintainer needed" issue |
| 11 | Mic hardware quality variance | M | L | Document supported devices; allow input-device picker | If specific device > 15% error, add device-selection UI |
| 12 | Apple-Silicon-only limits GTM | Certain | M | Intel support (whisper.cpp) in v1 | Not a v0 risk; revisit at v1 launch |

**L** = likelihood, **I** = impact. Every row has an explicit "if X, do
Y" — no "we'll monitor."

---

## 15. Distribution & licensing

- **License**: **MIT** (not GPL). Community moat, less restrictive than
  VoiceInk/FluidVoice/TypeWhisper (all GPL v3). Matches Aiko. `[decision]`
- **v0 distribution**: **Homebrew Cask + `.dmg`**. Not sandboxed (needed
  for global hotkeys + Cmd+V).
- **v1+ distribution**: add **Mac App Store** as a sandboxed variant
  (reduced scope — MAS sandbox blocks some global hotkey paths; accept
  the tradeoff for discoverability).
- **Signing**: Developer ID + notarization (required for Gatekeeper on
  macOS 26). Budget ~$99/yr Apple Developer Program.
- **Update mechanism (v0)**: Homebrew (`brew upgrade`) + manual `.dmg`.
  **v0.1+**: evaluate Sparkle for in-app updates.

---

## 16. Open questions for the user (with my recommended defaults)

The research left a few genuine decisions. My recommended defaults are
below; **the agent should build to these unless you override.**

| # | Question | Recommended default | Why |
|---|---|---|---|
| 1 | Working name `speak` — keep or rename? | **Keep `speak`** for v0 | short, generic, no conflict; rename is cosmetic, defer |
| 2 | Apple-Silicon-only, or backport Intel in v0? | **Apple-Silicon-only v0** | dramatically simpler; Intel (whisper.cpp) is v1 |
| 3 | MIT or source-available/GPL? | **MIT** | biggest community + trust moat vs Wispr |
| 4 | Homebrew + `.dmg` only, or Mac App Store too? | **Homebrew + `.dmg` v0**, MAS v1 | sandbox blocks hotkeys; MAS deferred |
| 5 | Ollama in v0 or v0.1? | **v0.1** | keeps v0 focused on core STT |
| 6 | Brand: icon, color, name? | **SF Symbol `waveform`**, monochrome, accent = system blue; no logo spend v0 | minimal, native, ships in the 2 weeks |
| 7 | Landing page? | **Single `README.md`-as-site for v0** | full site post-launch |

---

## 17. How the agent should use this spec

1. **Read this whole file once.** Do not skim §4 — the language decision
   is settled and must not be reopened.
2. **Do not read the other `SPEAK_*.md` files for direction.** They are
   superseded. Use them only as reference for *why* a decision was made
   (especially `SPEAK_DICTATION_STACKS.md` and
   `TECH_STACK_JUDGMENT.md`, which contain the verified evidence).
3. **Verify the load-bearing Apple claims yourself** against primary
   sources before coding (see §18). If a claim is wrong, surface it —
   don't silently paper over it.
4. **Implement strictly from §5–§13.** Use the Swift signatures in §7.4
   verbatim. Respect the performance budgets in §7.8.
5. **Follow the roadmap in §12 in dependency order.** The critical path
   is 0 → 2 → 3 → 5 → 6 → 11 → 13.
6. **Hit the §13.6 ship checklist** before declaring v0 done.
7. **Be opinionated. Pick a path. State the tradeoff. Move on.** No
   "TBD," no "figure out later." If genuinely unknown, state the
   question + your best guess.
8. **Quality bar**: a senior Swift engineer must be able to start coding
   Phase 0 from this doc with zero clarifying questions.

---

## 18. Claims to verify before coding (load-bearing)

The agent should confirm these against primary sources on day 0. All are
`[verified]` as of 2026-06-18 per the source docs, but re-confirm:

1. **Apple `SpeechAnalyzer`** exists, on-device, macOS 26+, Apple
   Silicon. — [developer.apple.com/documentation/speech/speechanalyzer](https://developer.apple.com/documentation/speech/speechanalyzer),
   [WWDC25 session 277](https://developer.apple.com/videos/play/wwdc2025/277/)
2. **`NSPasteboard` write + `CGEvent` Cmd+V** avoids the macOS 26.4
   paste-protection prompt (because we write, not read). —
   [Michael Tsai blog, 2026-04-09](https://mjtsai.com/blog/2026/04/09/)
3. **`CGEventTap`** requires Accessibility + Input Monitoring on macOS
   26.
4. **`WhisperKit`** (Argmax) current version, MIT license, Apple Silicon
   support. — [github.com/argmaxinc/argmax-oss-swift](https://github.com/argmaxinc/argmax-oss-swift)
5. **Ollama MLX** backend + model list (Qwen 2.5 3B, Gemma 3 4B,
   Phi-4-mini).
6. **Apple Intelligence Writing Tools** API surface + Apple Silicon
   requirement. — [Apple support](https://support.apple.com/guide/mac-help/find-the-right-words-with-writing-tools-mchldcd6c260/mac)
7. **Homebrew Cask** submission + review SLA. — [brew.sh](https://docs.brew.sh/Cask-Cookbook)

If any of these contradict primary sources, **stop and surface it**
before coding.

---

## 19. Sources (primary, 2025–2026)

### STT engines
- [Apple SpeechAnalyzer docs](https://developer.apple.com/documentation/speech/speechanalyzer)
- [WWDC25: Bring advanced speech-to-text to your app](https://developer.apple.com/videos/play/wwdc2025/277/)
- [Argmax: Apple SpeechAnalyzer and WhisperKit comparison](https://www.argmaxinc.com/blog/apple-and-argmax)
- [Argmax WhisperKit repo](https://github.com/argmaxinc/argmax-oss-swift)
- [FluidAudio repo](https://github.com/FluidInference/FluidAudio)
- [whisper.cpp](https://github.com/ggerganov/whisper.cpp)

### Mac dictation apps (verified stacks)
- [Wispr Flow](https://wisprflow.ai/) · [engineering blog](https://wisprflow.ai/post/technical-challenges) · [March 2026 updates](https://www.reddit.com/r/WisprFlow/comments/1s9t41f/march_2026_product_updates/)
- [Willow Voice](https://willowvoice.com/) · [founder talk (Whisper+Llama, cloud)](https://www.youtube.com/watch?v=Z2MaMTphhg0)
- [Superwhisper](https://superwhisper.com/) · [careers (native Android, on-device ML)](https://superwhisper.com/careers)
- [Aiko (Sindre Sorhus)](https://sindresorhus.com/aiko) · [whisper.cpp discussion #849](https://github.com/ggml-org/whisper.cpp/discussions/849)
- [VoiceInk (Beingpax)](https://github.com/Beingpax/VoiceInk) — Swift, 1.8M LOC, GPL v3, 5.3K stars
- [FluidVoice (altic-dev)](https://github.com/altic-dev/FluidVoice) — Swift, pluggable multi-engine, GPL v3, 2.4K stars ← **architectural role model**
- [TypeWhisper](https://github.com/TypeWhisper/typewhisper-mac) — Swift, prompt-based post-processing

### Mac UX primitives
- [yulrizka/osx-push-to-talk](https://github.com/yulrizka/osx-push-to-talk) — Swift push-to-talk reference
- [Keyboard Maestro: double-tap modifier hotkeys](https://forum.keyboardmaestro.com/t/double-tap-cmd-opt-shift-control-as-hotkeys/30449)
- [macOS 26.4 Paste Protection (Michael Tsai, 2026-04-09)](https://mjtsai.com/blog/2026/04/09/)

### Local LLM
- [Apple Intelligence Writing Tools](https://support.apple.com/guide/mac-help/find-the-right-words-with-writing-tools-mchldcd6c260/mac)
- [Ars Technica: Ollama MLX support](https://arstechnica.com/civis/threads/running-local-models-on-macs-gets-faster-with-ollama%E2%80%99s-mlx-support.1512366/)
- [Best small local LLMs 2026](https://gemma4-ai.com/blog/best-local-ai-models-2026)

### Category landscape (context, not competitors for v0)
- [CATEGORY_LANDSCAPE.md](./CATEGORY_LANDSCAPE.md) — 5-bucket 2026 sweep
- [Best dictation software 2026 (Utter)](https://utter.to/blog/best-dictation-software-2026/)

### Superseded research (reference only — do NOT follow for direction)
- `SPEAK_PRODUCT_SPEC.md` — product brief (still accurate; this spec refines it)
- `SPEAK_PLATFORM_MODEL.md` — **Rust-core recommendation: REJECTED for v0** (wrong category)
- `SPEAK_ARCHITECTURE_VERIFICATION.md` — **"Rust confirmed": factually wrong** (Claude Code is TS+Bun)
- `SPEAK_LANGUAGE_CORRECTION.md` — the correction that settled the language debate
- `SPEAK_DICTATION_STACKS.md` — **definitive evidence: all Mac dictation apps are Swift-native**
- `TECH_STACK_JUDGMENT.md` — the meta-process lesson (read for *why*)

---

*End of spec. Build to §5–§13. Ship v0 in 2 weeks.*
