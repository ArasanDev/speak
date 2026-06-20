# `speak` — Platform Model & Generalized Architecture (Ideation)

> **Status**: Ideation memo. The previous spec (`SPEAK_PRODUCT_SPEC.md`) is **not wrong** — it's correct *as a v0 product brief*. But it answers the wrong question. It says "build a Mac dictation app." You're asking "build a *product* that happens to ship on Mac first." Those are different architectures.
>
> **Date**: 2026-06-18
> **Author**: this session, questioning the prior session
> **Goal**: figure out the right *code structure* before any code is written.

---

## 0. The question, stated bluntly

There are three different products you could ship, with three different architectures:

| | Product | Architecture | Time to v0 | Time to v1 (next platform) |
|---|---|---|---|---|
| **A** | Mac dictation app (current spec) | Swift, SwiftUI, macOS-only | 2 wks | **+ N wks for Windows** (rewrite core) |
| **B** | Cross-platform dictation framework | Rust core + per-platform shells | 6-8 wks | + 2 wks per platform |
| **C** | **Portable-ready product, Mac-first** | Rust core + thin Swift shell | **2-3 wks** | **+ 2-3 wks** for Windows (add a shell, not a rewrite) |

The current spec is **A**. You are (rightly) questioning whether it should be **C** — same v0 speed, but the second platform is a shell, not a rewrite. The honest answer is **C is what you want**, and it's not much slower than A if you do it right.

I had implicitly assumed "Mac-only forever" and didn't surface the platform question. That's a real omission. Let me lay out the three options honestly.

---

## 1. Why the question matters — the 2026 technology shift

The reason this isn't a hypothetical is that **the technology shift is real and platform-agnostic**:

- **2020-2022**: STT is cloud-only (Google Speech-to-Text, Whisper API). LLM is cloud-only (GPT-3.5/4, Claude). A dictation app is a thin client over a vendor API. Platform doesn't matter much — you're calling `https://api.openai.com/...`.
- **2024-2025**: First local STT (Whisper.cpp, faster-whisper). LLM still mostly cloud. A dictation app *could* be local-first but it costs 10x more in dev time.
- **2026**: **Local is the default.** Apple SpeechAnalyzer (macOS 26) is on-device, low-latency, free. NVIDIA Parakeet-TDT-0.6B-v3 is open-source and tops 2026 benchmarks. Ollama with MLX is the recommended local-LLM path on macOS. Apple Intelligence runs on M-series. Windows Copilot+ PCs have NPUs. **A $1,000 laptop in 2026 is faster on local STT/LLM than a cloud call.**

The shift means **the architecture of a dictation app in 2026 is fundamentally different from 2022**. The cloud call is the *escape hatch*, not the default. The local engine is the product.

**This shift is platform-agnostic.** It's not "Mac is special." It's "any modern device with an NPU / M-series chip / Apple Silicon / Snapdragon X is special." The same architecture serves all of them. **The question is whether you build the framework once, or you build it three times and discover the framework later.**

---

## 2. The three options, honestly

### A. Mac-only (current spec)

- **Code**: Swift, SwiftUI, macOS 26+, Apple SpeechAnalyzer primary, WhisperKit fallback, Apple Intelligence v1.
- **Pros**: Best-in-class latency on Apple Silicon, native UX, fast to v0, leverages Apple-only APIs (SpeechAnalyzer, Apple Intelligence, Vision).
- **Cons**: When you want to ship Windows in v2, you rewrite the core. The Swift codebase is the product — it doesn't port.
- **Time to v0**: 2 weeks.
- **Time to Windows**: 3-4 months (rewrite core in C# or C++).
- **This is what the current spec describes.**

### B. Cross-platform from day 1 (Electron / Tauri / Flutter / Qt)

- **Code**: One codebase, all platforms, using a cross-platform UI framework.
- **Pros**: All platforms in v1, single team, single mental model.
- **Cons**: 
  - **Audio quality suffers** — none of these frameworks have a good low-level audio API. Real-time STT needs sub-100ms latency; Electron's audio is 200-500ms.
  - **Hotkey APIs are weak** — Electron has `globalShortcut`, but it's push-to-talk only and unreliable on Mac. No double-tap support.
  - **Paste simulation is brittle** — `clipboard.writeText` triggers the macOS 26.4 paste prompt on Mac; on Windows the Win32 `OpenClipboard` path is locked by the OS.
  - **You fight the framework more than you ship the product.** This is the path of "I built a Mac dictation app, but it's slow and the hotkey is wrong."
- **Time to v0**: 6-8 weeks (still need to write per-platform audio/hotkey/paste shims).
- **Time to next platform**: 0 (already there).
- **This is what Wispr Flow did** — they use Electron, and it's why they're "polishing" instead of "shipping features." It's also why their accuracy-on-noisy-environments is weaker than native apps.

### C. Portable-ready product, Mac-first (the recommendation)

- **Code**: A portable *core* in a systems language (Rust, with C++ as fallback) that owns the engine (STT orchestration, LLM cleanup, history, settings). A thin *platform shell* per OS that owns the I/O (audio, hotkey, paste, permissions, UI). The shell calls into the core via a stable C ABI or via FFI.
- **Pros**:
  - Same v0 speed as A if the core is small and the shell does the I/O.
  - Windows in v1 is *add a shell*, not a rewrite. Estimated 2-3 weeks for a Windows dev who knows the core.
  - Linux later is the same.
  - The core is testable headless — you can `cargo test` the engine without a UI.
  - The core is benchmarkable headless — you measure STT latency without audio I/O noise.
- **Cons**:
  - **One extra layer.** More files, more indirection, more upfront design.
  - **Two languages.** Rust (core) + Swift (Mac shell) or C++ (core) + Swift (Mac shell) etc. Two toolchains.
  - **FFI cost.** Marshalling types across the boundary. Not free, but `uniffi` (Mozilla's Rust→Swift/Kotlin/Python FFI generator) is mature.
- **Time to v0**: 2-3 weeks (1 week slower than A, but the v1 is dramatically faster).
- **Time to Windows v1**: 2-3 weeks (add a Win32 shell).
- **Time to Linux v2**: 2 weeks (add a GTK or Qt shell, or just a CLI).
- **This is what serious cross-platform products do.** Firefox, VS Code, Zed, Deno, ripgrep, alacritty, ghostty, bat. The pattern is well-trodden.

---

## 3. The recommendation: C

**Why C over A:**

- **GTM reality.** If `speak` is good, the second-most-common request after "works on my Mac" is "works on my work Windows laptop." Saying "sorry, Mac-only" loses 75% of the desktop market. The 1-2 week upfront cost is a small price for a 4x addressable market.
- **The core is the product.** The Apple-specific parts (SpeechAnalyzer, Apple Intelligence, CGEventTap, NSPasteboard) are *shells*. The STT orchestration, the LLM cleanup, the history, the settings, the model management — that's the core, and it's platform-agnostic by nature.
- **The Mac shell can be best-in-class.** The shell is the place where you use Apple-only APIs. SpeechAnalyzer, Apple Intelligence, Vision, SwiftUI, the menubar, the permissions — all Apple-only, all in the shell. The shell is where the Mac *feels like a Mac*. The core is where the logic lives.
- **V1 cost asymmetry.** With A, Mac v0 = 2 wks, Windows v1 = 3-4 months. With C, Mac v0 = 2-3 wks, Windows v1 = 2-3 wks. The total cost of "Mac + Windows in 6 months" is roughly the same; the difference is the shape of the work (one rewrite vs. two parallel tracks).

**Why C over B:**

- B (Electron/Tauri/Flutter) sacrifices the per-platform quality that defines a *good* dictation app. The user is paying attention to latency, hotkey reliability, paste behavior, permissions UX. Cross-platform UI frameworks compromise all of these.
- C gives you the per-platform quality of A *plus* the portability of B. The cost is a small upfront design investment.

**Why C is achievable in 2-3 weeks for v0:**

- The Mac shell does the I/O. The core is small. The FFI boundary is well-defined.
- Most of the v0 work is the Mac shell (Swift, SwiftUI, AVAudioEngine, SpeechAnalyzer, CGEventTap, NSPasteboard). That's the same 2-week workload as A.
- The core (Rust crate) is a thin layer for v0 — STT orchestration, history, settings. Maybe 200-400 lines of Rust.
- FFI setup (uniffi) is a half-day. CI is a half-day.

---

## 4. The concrete architecture (C)

### 4.1 The 4-layer model

```
┌─────────────────────────────────────────────────────┐
│  Layer 4: UI per platform                           │
│  (SwiftUI on Mac, WinUI on Windows, GTK on Linux)  │
├─────────────────────────────────────────────────────┤
│  Layer 3: Platform shell (Swift / C# / C++)         │
│  - AudioSource (mic capture, format conversion)     │
│  - HotkeySource (CGEventTap / RegisterHotKey)       │
│  - PasteSink (NSPasteboard / Win32 clipboard)       │
│  - PermissionGate (TCC / UAC / polkit)              │
│  - App lifecycle, menubar/tray, settings window     │
├─────────────────────────────────────────────────────┤
│  Layer 2: FFI boundary                              │
│  - speak-core-sys (raw C header)                    │
│  - speak-core (idiomatic Swift/Kotlin/Python)       │
│  - Stable, versioned, additive-only ABI             │
├─────────────────────────────────────────────────────┤
│  Layer 1: Core (Rust crate, or C++ as fallback)     │
│  - STT orchestration (pluggable engines)            │
│  - LLM cleanup (pluggable providers)                │
│  - History store (SQLite)                           │
│  - Settings store (typed)                           │
│  - Model management (download, cache, lifecycle)    │
│  - Streaming event bus (callbacks)                  │
└─────────────────────────────────────────────────────┘
```

### 4.2 The Rust core (Layer 1)

```rust
// speak-core/src/lib.rs

pub trait SttEngine: Send + Sync {
    async fn transcribe_stream(
        &self,
        audio: AudioStream,
        on_partial: Callback<PartialTranscript>,
        on_final: Callback<FinalTranscript>,
    ) -> Result<TranscriptSession, SpeakError>;
}

pub trait LlmCleaner: Send + Sync {
    async fn clean(
        &self,
        text: String,
        mode: CleanupMode,
    ) -> Result<String, SpeakError>;
}

pub trait HistoryStore: Send + Sync {
    async fn append(&self, entry: HistoryEntry) -> Result<(), SpeakError>;
    async fn search(&self, q: &str, limit: usize) -> Result<Vec<HistoryEntry>, SpeakError>;
}

pub struct SpeakEngine {
    stt: Box<dyn SttEngine>,
    cleaner: Option<Box<dyn LlmCleaner>>,
    history: Arc<dyn HistoryStore>,
    settings: Arc<SettingsStore>,
}

impl SpeakEngine {
    pub async fn start_session(&self, config: SessionConfig) -> Result<SessionHandle, SpeakError> {
        // ...
    }
}
```

- **Pluggable everything.** STT engines, LLM cleaners, history stores. The core doesn't know about Apple SpeechAnalyzer; it knows about the `SttEngine` trait.
- **Async-first.** Uses Tokio. The shell drives the audio stream and partial-result callbacks from the main thread.
- **Streaming callbacks.** Partial transcripts flow back to the shell for live UI. Final transcripts are stored and emitted for paste.
- **Testable headless.** `cargo test` runs the engine with a `MockSttEngine` and a `MockLlmCleaner` and asserts on the session lifecycle. No UI, no audio hardware.

### 4.3 The Mac shell (Layer 3)

```swift
// SpeakCore/SpeakSwift.swift (uniffi-generated + idiomatic)

public final class SpeakClient {
    private let engine: SpeakEngine  // uniffi-generated handle

    public init(config: SpeakConfig) throws {
        // 1. Initialize Rust core
        // 2. Pick STT engine (AppleSpeechAnalyzer | WhisperKit | FluidAudio)
        // 3. Pick LLM cleaner (AppleIntelligence | Ollama | None)
        // 4. Pick history store (SQLite at ~/Library/Application Support/speak/)
    }

    public func startCapture() async throws {
        // Drive AVAudioEngine → Rust AudioStream → STT
    }
}

// SpeakApp/AudioCapture.swift
final class MacAudioSource: AudioSource {
    private let engine = AVAudioEngine()
    func start() -> AsyncStream<AudioBuffer> { /* ... */ }
}

// SpeakApp/HotkeyMonitor.swift
final class MacHotkeySource: HotkeySource {
    // CGEventTap, double-tap Fn
}

// SpeakApp/PasteboardSink.swift
final class MacPasteSink: PasteSink {
    func paste(_ text: String) {
        NSPasteboard.general.setString(text, forType: .string)
        simulateCmdV()
    }
}
```

- **Thin.** The Mac shell is mostly Apple-framework glue. The logic is in the Rust core.
- **Testable per-platform.** XCTest runs the shell against a `MockSpeakClient` that wraps a Rust core with mocked engines. UI tests use a real core.
- **The macOS-only parts stay macOS-only.** SpeechAnalyzer, Apple Intelligence, Vision, NSPasteboard, CGEventTap — all in the shell. The core is platform-agnostic.

### 4.4 The FFI boundary (Layer 2)

- **`uniffi`** (Mozilla's generator) is the modern choice. You define the surface in Rust, annotate with `#[uniffi::export]`, and it generates Swift, Kotlin, Python bindings. Mature, used in production by Firefox Sync, Bitwarden, etc.
- **Alternative: raw C ABI.** More work, but more control. You define `extern "C"` functions, hand-write the Swift headers, and maintain both. Choose this if you want maximum portability (uniffi is great for Apple/Windows/Linux but Python/Kotlin generation can be a tax).
- **ABI stability.** The FFI is the contract. It's versioned (semver). Additive-only changes in v0.x. Breaking changes bump the major version.

### 4.5 What goes where — the dispatch table

| Concern | Mac shell | Windows shell | Linux shell | Rust core |
|---|---|---|---|---|
| Mic capture | AVAudioEngine | WASAPI | PulseAudio/ALSA | (consumes stream) |
| STT | Apple SpeechAnalyzer, WhisperKit, FluidAudio | WhisperKit, faster-whisper, Parakeet | faster-whisper, Parakeet | orchestrator |
| LLM cleanup | Apple Intelligence, Ollama MLX | Ollama, llama.cpp | Ollama, llama.cpp | orchestrator |
| Hotkey | CGEventTap | RegisterHotKey | evdev | (consumes events) |
| Paste | NSPasteboard + Cmd+V | OpenClipboard + Ctrl+V | xdotool / wl-copy | (emits final text) |
| Permissions | TCC (mic, accessibility, input monitoring) | UAC, registry hooks | polkit, X11/Wayland | (queries gate) |
| UI | SwiftUI MenuBarExtra | WinUI Tray | GTK / Qt | (none) |
| Distribution | Homebrew Cask, .dmg, MAS | WinGet, Chocolatey, .msi, MSIX | apt, flatpak, AUR | crates.io (for libs) |
| Settings window | SwiftUI | WinUI | GTK | typed config structs |
| History | SQLite at `~/Library/Application Support/speak/` | SQLite at `%APPDATA%/speak/` | SQLite at `~/.local/share/speak/` | SQLite abstraction |

---

## 5. What changes vs the current spec

### 5.1 What stays the same

- **Product positioning**: local-first, free, open source, MacBook-first GTM.
- **Hotkey UX**: double-tap Fn = start, single-tap Fn = stop & paste. Customizable.
- **Paste flow**: write pasteboard, simulate Cmd+V. No programmatic read.
- **v0 timeline**: 2-3 weeks (vs the spec's 2 weeks). One extra week of upfront core work.
- **Distribution**: Homebrew Cask + .dmg v0, Mac App Store v1.
- **The 3-permission onboarding**: same on Mac.

### 5.2 What changes

- **Language split**: Swift (shell) + Rust (core). Two toolchains. `cargo` and `swift` both on PATH.
- **Build system**: Cargo for the core, Xcode for the shell, `justfile` (or `Makefile`) at the root to coordinate. Or full Bazel if you want one tool.
- **FFI tooling**: `uniffi` (Mozilla). Add a `udl` file or inline `#[uniffi::export]` annotations.
- **CI**: GitHub Actions matrix — `macos-latest` for shell, `ubuntu-latest` for core. Both must pass.
- **Test strategy split**: `cargo test` for core (fast, headless, no UI), XCTest for shell (slower, with UI).
- **Repo layout**: monorepo, `core/`, `shells/macos/`, `shells/windows/` (future), `shells/linux/` (future), `docs/`, `dist/`.

### 5.3 What gets added to the roadmap

- **Phase 0b (Day 1-2)**: Cargo workspace, `speak-core` skeleton, `uniffi` setup, FFI smoke test ("Rust function called from Swift returns expected value"). 1-2 days.
- **Phase 0c (Day 2-3)**: STT trait + a `MockSttEngine` for tests. Confirm the boundary is workable before writing real STT. 1 day.
- **Phase 1b (Day 4)**: LLM trait + a `MockLlmCleaner`. Same idea. Half-day.
- **The rest of the phases** (audio, hotkey, paste, UI, distribution) are unchanged from the spec.

### 5.4 What doesn't change for v0 (intentional)

- **No Windows shell in v0.** The architecture *allows* it; v0 ships only the Mac shell. We add the Windows shell in v1.
- **No Linux shell in v0.** Same idea.
- **No CLI in v0.** Possible later (`speak --start`); not now.

---

## 6. The honest cost of each option

| | Mac v0 | Windows v1 | Linux v2 | iOS v2 | Total to "everywhere" |
|---|---|---|---|---|---|
| **A (Mac-only)** | 2 wks | 12-16 wks (rewrite) | 8-12 wks (rewrite) | 4-6 wks (port Swift) | 26-36 wks |
| **B (cross-platform from day 1)** | 6-8 wks | 0 wks (already there) | 0 wks | 4-6 wks (Flutter/QT port) | 10-14 wks |
| **C (portable-ready, Mac-first)** | 2-3 wks | 2-3 wks (add shell) | 2-3 wks (add shell) | 2-3 wks (port Mac shell) | 8-12 wks |

**The C row is the cheapest total** to "everywhere," and it's only 1 week slower to v0 than A. The B row has the worst per-platform quality (latency, hotkey reliability, paste behavior). **C is the right answer.**

---

## 7. The real question to answer

The choice between A and C depends on one question:

> **In 6 months, is the user "Mac developer / writer" or "developer / writer on any platform"?**

If the answer is Mac-only (you have evidence that 90%+ of the demand is Mac), pick A. The current spec is right. Don't over-engineer.

If the answer is "any platform" (which is the default for any consumer product), pick C. The 1-week cost in v0 is paid back 10x in v1+v2.

**My read of the situation:** the user (you) is a Mac developer building for themselves and their community. The community is probably Mac-heavy today. But:
- The cheapest path to Windows is C.
- The cheapest path to iOS/iPadOS is C.
- The cheapest path to "this is a real product, not a Mac hobby project" is C.
- C is only 1 week slower to v0.

**Pick C unless you have a specific reason to pick A.**

---

## 8. What this means for the existing docs

- **`SPEAK_PRODUCT_SPEC.md`**: keep as-is. The product brief is correct. Add a §0.5 note: "Architecture is `SPEAK_PLATFORM_MODEL.md`, which describes a portable-ready structure. The Mac shell is v0; other platforms are v1+."
- **`OPUS_BUILD_PROMPT.md`**: needs a small update. The Opus brief should now produce 6 deliverables instead of 5: add a `SPEAK_CORE_API.md` for the Rust core's public API. The Mac shell API is `SPEAK_API.md`; the core API is `SPEAK_CORE_API.md`. Same quality bar.
- **A new `SPEAK_REPO_LAYOUT.md`**: the monorepo directory tree, Cargo workspace + Xcode project + FFI setup + CI matrix.
- **The roadmap shifts by 1-2 days**: Phase 0 adds the core/FFI work. v0 is 2-3 weeks instead of 2 weeks.

---

## 9. The minimal architecture memo (if you want to go even smaller)

If you don't want a full architecture brief, here's the 5-line version:

> `speak` is a Rust core that owns the engine (STT orchestration, LLM cleanup, history, settings) and a thin Swift/C#/C++ shell per platform that owns the I/O (mic, hotkey, paste, permissions, UI). The shells use platform-native APIs for the parts that matter (Apple SpeechAnalyzer on Mac, RegisterHotKey on Windows, evdev on Linux). FFI is `uniffi`. v0 ships the Mac shell. v1+ adds Windows, Linux, iOS, Web shells. The core is testable headless with `cargo test`. The shells are testable per-platform with XCTest/VS Test. **This is the pattern used by Firefox, VS Code, Zed, Deno, ripgrep, ghostty.**

If that memo makes sense, the rest of this doc is detail. If you have questions about the dispatch table (§4.5), the cost analysis (§6), or the GTM question (§7), let's talk through them before running the Opus prompt.

---

## 10. Sources

- **Mozilla uniffi** — multi-language bindings generator, used in Firefox Sync, Bitwarden. `github.com/mozilla/uniffi-rs`.
- **Tokio** — async runtime for the Rust core. `tokio.rs`.
- **Argmax WhisperKit** — Apple Silicon STT. `github.com/argmaxinc/argmax-oss-swift`.
- **Apple SpeechAnalyzer** — on-device STT, macOS 26. `developer.apple.com/documentation/speech/speechanalyzer`.
- **NVIDIA Parakeet-TDT-0.6B-v3** — open-source, multilingual STT. `arxiv.org/abs/2509.14128`.
- **Apple NSPasteboard + CGEvent** — paste simulation, macOS. Avoid macOS 26.4 paste prompt by writing not reading.
- **Firefox / VS Code / Zed / Deno / ripgrep** — all use the core/shell pattern with portable cores + per-platform shells.
- **Cargo workspaces** — `doc.rust-lang.org/book/ch14-03-cargo-workspaces.html`.
- **Microsoft WinUI 3 + Windows App SDK** — modern Windows shell.
- **Linux evdev** — low-level input on Linux, used by `xdotool` and Wayland compositors.
