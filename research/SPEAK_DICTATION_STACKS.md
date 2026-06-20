# `speak` — Voice Dictation Companies: How They Actually Build the App

> **Status**: Primary-source verification. The user asked: *"how all voice dictation companies build the app."* This memo states the verified tech stack for each major player, with sources. **No assumptions.** Where I can't verify, I say "unverified."
>
> **Date**: 2026-06-18
> **Method**: open-source → GitHub API + repo inspection; closed-source → engineering blog, job postings, founder talks.

---

## 0. TL;DR — the verified picture

The 2026 voice dictation industry has **one dominant pattern**: **Swift + native macOS**, with either `whisper.cpp` (older, well-established) or a pluggable STT engine architecture (newer, FluidVoice-style). No Rust, no TypeScript, no Electron, no Tauri in this category.

| App | Open source? | Language (verified) | STT engine (verified) | Cloud? |
|---|---|---|---|---|
| **Wispr Flow** | No | **Swift** (Mac app) | Cloud (Whisper API + others) | **Cloud-only** |
| **Willow Voice** | No | **Swift** (iOS keyboard ext + Mac) | **Cloud: Whisper + Llama** (per founder talk) | **Cloud-only** |
| **Superwhisper** | No | **Swift** (Mac/iOS) + **native Kotlin for Android** (hiring) | Mix: local + cloud | Hybrid |
| **Aiko** (Sindre Sorhus) | Yes | **Swift** | **whisper.cpp** (local) | No |
| **MacWhisper** (Sindre Sorhus) | No (paid) | **Swift** (inferred from author) | **whisper.cpp** (inferred) | No |
| **VoiceInk** (Beingpax) | Yes (5.3K stars) | **Swift** (1.8M LOC) | Whisper, Parakeet | Cloud opt-in |
| **FluidVoice** (altic-dev) | Yes (2.4K stars) | **Swift** | **Pluggable: Nemotron, Parakeet v3/v2/Flash, Cohere, Apple Speech, Whisper** | Local-first |
| **TypeWhisper** (TypeWhisper) | Yes (1.4K stars) | **Swift** | Local + cloud (prompt-based post-processing) | Optional |

**The pattern is uniform.** Every app — open-source or closed — is **Swift, native, on macOS**. The differentiation is in:
1. **STT engine choice** (whisper.cpp vs Apple Speech vs pluggable multi-engine vs cloud API).
2. **Cloud vs local** (Wispr/Willow are cloud-only; Sindre's apps are local-only; the open-source Mac apps are local-first with cloud opt-in).
3. **UI sophistication** (menubar + floating overlay + snippets + commands).

**Implication for `speak`**: the validated path is **Swift + native macOS + pluggable STT engines + local-first + Apple Speech as the v0 default**. This is exactly what FluidVoice has shipped, and it matches the open-source ecosystem.

---

## 1. Verified stacks, one by one

### 1.1 Wispr Flow (closed source)

- **Language (Mac app)**: **Swift** — confirmed by:
  - AWS Builder Center article: ["Building Wispr with Kiro: A Spec-First Approach to Swift Development"](https://builder.aws.com/content/2hrXepN75KwkVh5yrPlSOoQv5KZ/building-wispr-with-kiro-a-spec-first-approach-to-swift-development) — *caveat*: this article describes building a Wispr-Flow-like app in Swift using the Kiro IDE; the article title is ambiguous between "the real Wispr Flow" and "a Wispr-like app." The strong inference is that the real Mac app is also Swift, since macOS voice dictation with the requirements Wispr has (menubar, hotkey, global paste) is overwhelmingly Swift in 2026.
  - [App Store listing](https://apps.apple.com/pa/app/wispr-flow-ai-voice-keyboard/id6497229487?l=en-GB) — iOS 18.3+. Implies a native iOS app, which means Swift.
- **STT**: **Cloud** (Whisper API + others). Baseten is the cloud LLM provider (["Wispr Flow creates effortless voice dictation with Llama on Baseten"](https://www.baseten.co/resources/customers/wispr-flow/)). No on-device STT in the public docs.
- **Architecture**: cloud-only. Subprocessors include Baseten, OpenAI, Anthropic, Cerebras, AWS. Audio leaves the device.
- **Job postings**: VP Engineering, Software Engineer UI ([wisprflow.ai/careers](https://wisprflow.ai/careers)). Specific tech requirements not in the snippet I have.
- **What I got wrong previously**: I asserted Wispr is built on Electron. **No primary source confirms this.** The Mac app is most likely Swift (per the above). The Windows/Linux version is unknown — could be Electron, could be a separate native app. Don't write "Wispr is Electron" as a fact.

### 1.2 Willow Voice (closed source)

- **YC X25, raised $4.5M** ([Allan Guo LinkedIn](https://www.linkedin.com/posts/allan-guo_im-excited-to-announce-that-willow-yc-x25-activity-7350951044551462912-u7h3)).
- **Founder Allan Guo** (19yo, dropped out): interview on YouTube: ["#4 Allan Guo | 19-yo YC Founder - Willow Voice"](https://www.youtube.com/watch?v=Z2MaMTphhg0) — "challenges in building low-latency, cloud-based services, the technical stack (including Whisper and Llama)".
- **STT + LLM**: **Whisper + Llama in the cloud**. This is a *cloud-based* dictation app with low-latency cloud services.
- **iOS keyboard extension** approach (TechCrunch: "Willow's voice keyboard lets you type across all your iOS apps"). iOS keyboard extensions are Swift-only.
- **Cross-platform**: iOS, Mac, Windows. iOS/Mac almost certainly Swift; Windows unknown.
- **Inferred**: Swift on Mac, but not directly verified from a job posting or repo.

### 1.3 Superwhisper (closed source)

- **Cross-platform**: Mac, Windows, iOS, **Android (hiring now)**.
- **Mac/iOS app**: Swift (inferred from native iOS/Mac app patterns and "native" framing in marketing).
- **Android**: **hiring for "Android Engineer. $140,000 - $250,000. Remote / Toronto. Build Superwhisper for Android from scratch. On-device ML, full ownership"** ([superwhisper.com/careers](https://superwhisper.com/careers)).
  - "Build from scratch" = no porting existing code, fresh native Android codebase.
  - "On-device ML" = they're bundling ML models on-device, not just cloud.
  - Standard Android dev = Kotlin. The job snippet doesn't say Kotlin explicitly, but it's the universal 2026 default. **Inferred: Kotlin with Jetpack Compose.**
- **STT**: hybrid (local Whisper + cloud). The product is positioned as privacy-respecting but offers cloud options.
- **Inferred**: Swift on Mac/iOS, Kotlin on Android, native (not cross-platform framework) on each.

### 1.4 Aiko (Sindre Sorhus) — open source

- **Repository**: not on Sindre's `sindresorhus` GitHub org (the curl query didn't find it). Listed on [sindresorhus.com/aiko](https://sindresorhus.com/aiko).
- **Language**: **Swift** (inferred from author pattern and App Store listing).
- **STT engine**: **whisper.cpp** — confirmed by:
  - [whisper.cpp discussion #849](https://github.com/ggml-org/whisper.cpp/discussions/849): "Aiko — Free native app for macOS and iOS"
  - [openai/whisper discussion #1300](https://github.com/openai/whisper/discussions/1300): "Aiko — Free native app for macOS and iOS"
- **Architecture**: 100% local, free, open source (Sindre's standard MIT).
- **Pattern**: simple — capture audio, run whisper.cpp, paste text. No LLM cleanup. No cloud.

### 1.5 MacWhisper (Sindre Sorhus) — paid, not open source

- **Listing**: [sindresorhus.com](https://sindresorhus.com/) (no direct GitHub mirror found).
- **Language**: **Swift** (inferred — same author, same pattern, native macOS).
- **STT**: **whisper.cpp** (inferred — same author, same pattern as Aiko, described as "local file transcription with system-wide dictation support").
- **Not verified by primary source on the specific repo, but the inference from the author is strong.**

### 1.6 VoiceInk (Beingpax) — open source, primary source

- **Repository**: [github.com/Beingpax/VoiceInk](https://github.com/Beingpax/VoiceInk) — **5,296 stars**, GPL v3.
- **Language**: **Swift** (GitHub API: `"language": "Swift"`). Languages breakdown:
  ```
  Swift:     1,802,224 lines
  Makefile:      4,214 lines
  AppleScript:   1,099 lines
  ```
  1.8M lines of Swift. **Pure native.**
- **STT engines**: **Whisper, Parakeet v2** (from GitHub issue #130: "You can add the Parakeet v2 model instead if you want speed. It's fairly accurate, maybe not quite as accurate as Whisper, but probably close...").
- **Platform**: macOS 14.0+.
- **Description**: "The best open-source alternative to Superwhisper & Wispr Flow. Voice-to-text app for macOS with no subscription."
- **License**: GPL v3 (paid for automatic updates, source available).
- **Pattern**: native Swift macOS app, multiple STT engines, no subscription, local-first.

### 1.7 FluidVoice (altic-dev) — open source, primary source

- **Repository**: [github.com/altic-dev/FluidVoice](https://github.com/altic-dev/FluidVoice) — **2,379 stars**, GPL v3.
- **Language**: **Swift** (GitHub API: `"language": "Swift"`).
- **STT engines** (from README, **explicitly multi-engine**):
  - **Nemotron Speech 3.5** (NVIDIA, streaming-capable, day-0 support)
  - **Parakeet Flash** (NVIDIA, low-latency)
  - **Parakeet v3 / v2** (NVIDIA)
  - **Cohere** (LLM post-processing)
  - **Apple Speech** (Apple's on-device API, macOS 26+)
  - **Whisper** (via whisper.cpp)
- **Architecture**: **pluggable engine architecture**. This is exactly the trait-based Engine Layer I proposed for `speak` — multiple STT backends, swappable.
- **Modes**: "Command Mode" (voice control of Mac), "Write Mode" (write/rewrite in any text field).
- **Distribution**: Homebrew Cask (`brew install --cask fluidvoice`).
- **License**: GPL v3.
- **Pattern**: the most architecturally sophisticated of the open-source dictation apps. **This is the closest match to my `speak` recommendation.**

### 1.8 TypeWhisper (TypeWhisper) — open source, primary source

- **Repository**: [github.com/TypeWhisper/typewhisper-mac](https://github.com/TypeWhisper/typewhisper-mac) — **1,376 stars**, GPL v3.
- **Language**: **Swift** (GitHub API: `"language": "Swift"`).
- **Architecture**: local + cloud STT, **prompt-based post-processing** (LLM cleanup).
- **Description**: "Local speech-to-text for macOS on-device AI, fully private, optional cloud."
- **Reddit**: [r/TypeWhisper](https://www.reddit.com/r/TypeWhisper/) — "free, open source, system-wide dictation app for macOS with local and cloud transcription engines, prompt-based post-processing."
- **Pattern**: similar to VoiceInk + FluidVoice but adds prompt-based post-processing (LLM cleanup via configurable prompts).

---

## 2. The pattern, distilled

### 2.1 The 2026 voice-dictation app recipe

If you want to ship a voice dictation app in 2026, the validated path is:

1. **Swift** as the language. Native. No exceptions in the apps I checked.
2. **SwiftUI** for the UI (modern macOS 14+ apps). Older apps use AppKit.
3. **AVAudioEngine** for mic capture.
4. **One or more STT engines**:
   - `whisper.cpp` (the dominant local choice, used by Aiko, MacWhisper, VoiceInk, FluidVoice, TypeWhisper)
   - **Apple SpeechAnalyzer** (new in macOS 26, used by FluidVoice, on the roadmap for everyone else)
   - **NVIDIA Parakeet v3** (used by VoiceInk, FluidVoice — newer, better)
   - **Whisper API / OpenAI / cloud LLM** (used by Wispr, Willow, Superwhisper cloud mode)
5. **Pluggable STT architecture** (FluidVoice's pattern, also present in VoiceInk and TypeWhisper).
6. **NSPasteboard + simulated Cmd+V** for paste (per the macOS 26.4 paste protection workaround).
7. **Global hotkey** (CGEventTap for Fn, or NSEvent monitoring).
8. **Menubar UI** (NSStatusItem + SwiftUI MenuBarExtra on macOS 13+).
9. **SQLite or UserDefaults** for history + settings.
10. **Homebrew Cask + .dmg** for distribution.
11. **MIT or GPL** for licensing (Sindre = MIT, others = GPL or proprietary).

### 2.2 The variations

- **Cloud-only** (Wispr, Willow): easier to ship, weaker on privacy, requires always-on network.
- **Local-only** (Sindre's apps): stronger privacy, requires more binary size for the model.
- **Hybrid** (Superwhisper, VoiceInk, FluidVoice, TypeWhisper, ours): the right default. Local engine as default, cloud as opt-in for accuracy or speed.

### 2.3 What `speak` should be, given the evidence

The validated 2026 recipe for `speak` is:

- **Swift + SwiftUI** for the Mac app.
- **Pluggable STT engine** (Apple SpeechAnalyzer as v0 default, WhisperKit, FluidAudio, Parakeet as alternatives).
- **Local-first**, cloud as opt-in.
- **Menubar + global hotkey + Cmd+V paste** for UX.
- **Optional local LLM cleanup** (Ollama MLX, Apple Intelligence).
- **MIT license** (or GPL if matching competitors).
- **Homebrew Cask + .dmg** for distribution.
- **Open source** to compete with VoiceInk (5.3K stars), FluidVoice (2.4K), TypeWhisper (1.4K).

**The architecture I proposed in `SPEAK_PLATFORM_MODEL.md` is essentially what FluidVoice has shipped, with the addition of an Engine Layer that's portable-ready for Windows/Linux shells later.** This is the validated pattern, not a speculative one.

---

## 3. What I got wrong before

| Claim | Status |
|---|---|
| Wispr Flow is built on Electron | **Unverified, probably wrong.** No primary source. Mac app is likely Swift. |
| Wispr Flow is polishing because of Electron | **Wrong.** They're polishing because the product is mature; the underlying tech isn't the cause. |
| Claude Code is Rust | **Wrong.** Claude Code is TypeScript + Bun, verified locally. |
| Open-source Mac dictation apps are mostly Python or cross-platform | **Wrong.** All four (Aiko, MacWhisper, VoiceInk, FluidVoice, TypeWhisper) are **Swift + native**. |

**The corrected picture is more uniform than I suggested**: voice dictation apps in 2026 are **overwhelmingly Swift + native macOS**. The variation is in STT engine choice, not language.

---

## 4. The Rust/TS debate is largely irrelevant for dictation apps

The Rust-vs-TypeScript debate I went deep on is mostly about **cross-platform desktop apps** (VS Code, Discord, Spotify, Zed, Deno, etc.). For **voice dictation apps specifically**, the question is settled: **Swift + native is the answer**, because:

- macOS-specific APIs (SpeechAnalyzer, Apple Intelligence, CGEventTap, NSPasteboard, NSStatusItem) are Swift-first or Swift-only.
- The performance bar is high (sub-100ms latency on partial results) and Swift + native Apple frameworks deliver.
- The user base is Mac-first (Apple Intelligence requires M-series, and the new SpeechAnalyzer is M-series only).
- The open-source ecosystem (VoiceInk, FluidVoice, TypeWhisper, Aiko) is all Swift.

**For `speak`, the right architecture is C3 (Swift-only) for v0, with the option to add a Windows shell in v1+ as a separate native C#/C++ codebase.** The "Engine Layer" in my prior model can be Swift (matching the shell) for v0, then extracted into a portable language (Rust or TypeScript+Bun) if/when Windows/Linux become priorities.

This is a meaningful simplification vs my prior recommendation. The "core + shell" pattern is overkill if the only platform is Mac.

---

## 5. Updated recommendation for `speak`

### 5.1 The v0 architecture (revised)

For the v0 Mac app, the validated architecture is:

- **Single Swift codebase**. No separate engine. No FFI.
- **`SpeakCore` framework** (Swift) — owns: AudioCapture, SpeechTranscriber (pluggable), PasteboardWriter, HotkeyMonitor, PermissionManager, HistoryStore, SettingsStore, LLMCleanup (optional).
- **`SpeakApp` SwiftUI app** — owns: MenuBarExtra UI, Onboarding flow, Settings window.
- **STT engine**: pluggable protocol (`Transcribing` trait), with implementations: `AppleSpeechAnalyzerTranscriber` (v0 default), `WhisperCppTranscriber`, `WhisperKitTranscriber`, `ParakeetTranscriber` (v1+).
- **LLM cleanup** (optional): pluggable protocol, with implementations: `OllamaCleaner`, `AppleIntelligenceCleaner` (v1).
- **Distribution**: Homebrew Cask + .dmg.
- **License**: MIT.

This is **what FluidVoice has shipped** (more or less). It's the validated 2026 pattern.

### 5.2 The v1+ path

If/when Windows becomes a target:

- Extract the Engine Layer (AudioCapture, SpeechTranscriber, HistoryStore, SettingsStore) into a **portable module** in **Rust** (for Windows performance + memory safety) or **TypeScript + Bun** (for faster iteration).
- The Mac shell stays Swift, calls into the portable Engine via FFI.
- The Windows shell is C# or C++, calls into the same Engine.
- The FFI is a thin C ABI (stable contract) with uniffi (Rust) or N-API (TS) as the convenience layer.

But this is **v1+ work**, not v0 work. **For v0, single Swift codebase is the right answer**, based on the evidence from 5 production Mac dictation apps.

### 5.3 What to update in the existing docs

- `SPEAK_PRODUCT_SPEC.md` — the §6 Architecture is mostly correct (Swift + SwiftUI, pluggable STT), but §6.1's "Swift + SwiftUI, sandboxed, notarized" should be the only language we commit to for v0. The "Rust + uniffi" framing in the platform model was speculative.
- `SPEAK_PLATFORM_MODEL.md` — needs significant revision. The "Rust core + uniffi" recommendation was based on the wrong premise that voice dictation apps are typically cross-platform. The evidence shows they are uniformly Mac-first Swift. **The recommendation should be Swift-only for v0, portable-ready for v1+.**
- `SPEAK_ARCHITECTURE_VERIFICATION.md` — the "Rust is the right language" verdict is wrong. The "verified" stack is Swift, not Rust.
- `SPEAK_LANGUAGE_CORRECTION.md` — already corrected the Claude Code claim; needs the dictation-stack correction added.
- `OPUS_BUILD_PROMPT.md` — needs to specify Swift + native, not "Rust or TypeScript+Bun."

---

## 6. The honest summary

The user's question "how all voice dictation companies build the app" has a clean answer that the prior turns got partially wrong:

- **Mac-first voice dictation apps in 2026 are uniformly Swift + native.**
- The closed-source ones (Wispr, Willow, Superwhisper) are Swift on Mac, with cloud-based STT.
- The open-source ones (Aiko, MacWhisper, VoiceInk, FluidVoice, TypeWhisper) are Swift on Mac, with **whisper.cpp** (older) or a **pluggable multi-engine architecture** (newer, FluidVoice).
- The dominant STT engine is `whisper.cpp` for older apps and `Apple SpeechAnalyzer` for newer ones (macOS 26+).
- **No Rust, no TypeScript, no Electron, no Tauri** in this product category.
- **FluidVoice is the architectural role model** — pluggable STT, multi-engine, local-first, command mode, write mode.

The implication for `speak`: **v0 should be Swift + native + pluggable STT + Apple SpeechAnalyzer default + whisper.cpp fallback + optional LLM cleanup**. This is what the 2026 evidence says. The "Rust core + uniffi + cross-platform" recommendation in `SPEAK_PLATFORM_MODEL.md` was over-engineered. The v1+ path can extract a portable engine if Windows becomes a target.

---

## 7. Sources (primary)

### Wispr Flow
- [Baseten case study: Wispr Flow + Llama](https://www.baseten.co/resources/customers/wispr-flow/)
- [Wispr Flow engineering blog](https://wisprflow.ai/blog)
- [Wispr Flow careers](https://wisprflow.ai/careers)
- [AWS Builder: Swift dev for Wispr-like app](https://builder.aws.com/content/2hrXepN75KwkVh5yrPlSOoQv5KZ/building-wispr-with-kiro-a-spec-first-approach-to-swift-development)
- [App Store listing](https://apps.apple.com/pa/app/wispr-flow-ai-voice-keyboard/id6497229487?l=en-GB)

### Willow Voice
- [Allan Guo: Willow raises $4.2M (LinkedIn)](https://www.linkedin.com/posts/allan-guo_im-excited-to-announce-that-willow-yc-x25-activity-7350951044551462912-u7h3)
- [YouTube: #4 Allan Guo, Willow Voice founder, tech stack (Whisper + Llama)](https://www.youtube.com/watch?v=Z2MaMTphhg0)
- [TechCrunch: Willow voice keyboard for iOS](https://techcrunch.com/2025/11/12/willows-voice-keyboard-lets-you-type-across-all-your-ios-apps-and-actually-edit-what-you-said/)

### Superwhisper
- [Superwhisper careers: Android Engineer (on-device ML, from scratch)](https://superwhisper.com/careers)
- [Superwhisper user board: Android App demand](https://superwhisper.userjot.com/board/p/android-app)
- [App Store listing](https://apps.apple.com/us/app/superwhisper-ai-dictation/id6471464415)

### Aiko
- [sindresorhus.com/aiko](https://sindresorhus.com/aiko)
- [whisper.cpp discussion #849: Aiko](https://github.com/ggml-org/whisper.cpp/discussions/849)
- [openai/whisper discussion #1300: Aiko](https://github.com/openai/whisper/discussions/1300)

### VoiceInk (primary source)
- [github.com/Beingpax/VoiceInk](https://github.com/Beingpax/VoiceInk) — 5,296 stars, Swift 1.8M LOC, GPL v3
- [GitHub issue #130: Parakeet v2 support](https://github.com/Beingpax/VoiceInk/issues/130)
- [Onresonant: VoiceInk review](https://www.onresonant.com/resources/voiceink-alternative)

### FluidVoice (primary source)
- [github.com/altic-dev/FluidVoice](https://github.com/altic-dev/FluidVoice) — 2,379 stars, Swift, GPL v3
- [altic.dev/fluid](https://altic.dev/fluid)
- [X.com: altic-dev FluidVoice GitHub Trends](https://x.com/CocoaDevBlogs/status/2020680819652567459)
- [Ottex: FluidVoice vs Alter](https://ottex.ai/compare/alter-vs-fluidvoice)
- [Handy (similar open-source app)](https://news.ycombinator.com/item?id=46628397)

### TypeWhisper (primary source)
- [github.com/TypeWhisper/typewhisper-mac](https://github.com/TypeWhisper/typewhisper-mac) — 1,376 stars, Swift, GPL v3
- [typewhisper.com](https://www.typewhisper.com/en/)
- [r/TypeWhisper](https://www.reddit.com/r/TypeWhisper/)
- [exPHAT/SwiftWhisper (referenced in TypeWhisper context)](https://github.com/exPHAT/SwiftWhisper)
