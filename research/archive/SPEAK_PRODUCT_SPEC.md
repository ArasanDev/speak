# `speak` — Voice Dictation for MacBook

> **Status**: Product spec v0.1. Working name: `speak`. GTM wedge: MacBook (Apple Silicon, macOS 26+).
> **Date**: 2026-06-18
> **Author**: research pass + product design
> **Working dir**: `/Users/tamil/Developers/deepvoice` (separate product from `deepvoice` ambient pair-programmer)
> **Use case**: a Mac-native, local-first, free alternative to Wispr Flow for developers and writers.

---

## 0. Decision card

| | Choice | Why |
|---|---|---|
| **Name (working)** | `speak` | Short, generic, no conflict |
| **GTM** | MacBook (Apple Silicon, macOS 26+) | The user's stated wedge; biggest pain; Apple-only stack |
| **STT (v0)** | Apple **SpeechAnalyzer** (on-device) | Free, low-latency, no cloud, ships with macOS 26 |
| **STT (fallback)** | WhisperKit (Argmax) or FluidAudio | Better accuracy, more languages |
| **LLM (v0)** | Optional — Ollama MLX or Apple Intelligence Writing Tools | User opt-in cleanup; off by default |
| **Hotkey** | Double-tap Fn = start, single-tap Fn = stop & paste | User's stated spec; no holding required |
| **Distribution** | Free, open source (MIT), Homebrew Cask + .dmg | Compete with Wispr Flow $15/mo on price + privacy |
| **Build timeline** | v0 in 2 weeks; v1 in 4 weeks; v2 in 12 weeks | See §7 |

**Positioning (one sentence):** *The Mac-native, free, local-first voice dictation app for developers and writers who don't want their audio in someone else's cloud.*

**Why now:**
- Apple shipped **SpeechAnalyzer** in macOS 26 (2025-Q4) — a first-party on-device STT API that didn't exist before. The technical barrier just dropped.
- Wispr Flow (the market leader) is **polishing, not shipping major features** (March 2026 updates were notification UI + sleep recovery, per [r/WisprFlow](https://www.reddit.com/r/WisprFlow/comments/1s9t41f/march_2026_product_updates/)). Window is open.
- The user has been paying Wispr Flow $15/mo and wants an alternative. So do many other developers (r/ClaudeAI thread on "go-to voice-to-text setup for Cursor or Claude Code" shows the ad-hoc reality).
- macOS 26.4 (2026-04) added **paste protection** — but the user's described `Cmd+V` flow is still the cleanest workaround.

---

## 1. The 2026 STT landscape (ground truth)

This is the technology layer a Mac voice-dictation app can build on in 2026. Ordered by relevance to `speak`.

### 1.1 Apple SpeechAnalyzer (NEW, primary choice)

- **Docs**: [developer.apple.com/documentation/speech/speechanalyzer](https://developer.apple.com/documentation/speech/speechanalyzer)
- **WWDC25 video**: [Bring advanced speech-to-text capabilities to your app](https://developer.apple.com/videos/play/wwdc2025/277/)
- **Availability**: iOS 26, iPadOS 26, macOS 26, Mac Catalyst 26.
- **What it is**: First-party Apple API for live speech-to-text. Runs on-device. Supports multiple locales, custom vocabularies, final/partial results.
- **Benchmark vs WhisperKit**: Argmax published [Apple SpeechAnalyzer and Argmax WhisperKit](https://www.argmaxinc.com/blog/apple-and-argmax) — Apple is competitive on accuracy and faster on Apple Silicon, especially at the small-model tier.
- **Why we pick it**: zero cost, zero cloud, low latency, runs on M-series natively, supports en-US out of the box, gets better with OS updates.

### 1.2 WhisperKit (Argmax)

- **Repo**: [github.com/argmaxinc/argmax-oss-swift](https://github.com/argmaxinc/argmax-oss-swift)
- **Website**: [.argmaxinc.com](https://www.argmaxinc.com/)
- **What it is**: Open-source Swift package wrapping Whisper for Apple Silicon via Core ML. Models: tiny, base, small, medium, large-v3, distil-large-v3.
- **Comparison**: [Argmax vs whisper.cpp on Cactus Compute](https://cactuscompute.com/compare/argmax-vs-whisper-cpp). Argmax wins on Apple Silicon for latency and battery.
- **Use case for `speak`**: **fallback** if SpeechAnalyzer quality is insufficient in noisy environments, or for languages SpeechAnalyzer doesn't support.

### 1.3 FluidAudio

- **Repo**: [github.com/FluidInference/FluidAudio](https://github.com/FluidInference/FluidAudio)
- **CocoaPods**: [cocoapods.org/pods/FluidAudio](https://cocoapods.org/pods/FluidAudio)
- **What it is**: Frontier STT + TTS + VAD + speaker diarization, Core ML, on-device. From Fluid Inference.
- **Use case**: alternative fallback, especially if speaker diarization matters for v2 (multi-person dictation).

### 1.4 MLX-Whisper

- **Repo**: [github.com/mustafaaljadery/lightning-whisper-mlx](https://github.com/mustafaaljadery/lightning-whisper-mlx)
- **What it is**: Whisper running on Apple's MLX framework. Often the fastest Whisper path on Apple Silicon.
- **Use case**: for users who want Whisper-quality on Apple Silicon, faster than whisper.cpp CPU.

### 1.5 whisper.cpp

- **Repo**: [github.com/ggerganov/whisper.cpp](https://github.com/ggerganov/whisper.cpp)
- **What it is**: The original C++ Whisper port. Cross-platform, CPU-only, works on Intel Macs.
- **Use case**: Intel Mac fallback. Universal binary path.

### 1.6 faster-whisper (CTranslate2)

- **Source**: [pypi.org/project/whisper-ctranslate2](https://pypi.org/project/whisper-ctranslate2/), [Modal comparison](https://modal.com/blog/choosing-whisper-variants)
- **What it is**: 4x faster than whisper.cpp on CPU, slightly less accurate.
- **Use case**: cross-platform fallback, Python tooling.

### 1.7 NVIDIA Parakeet-TDT-0.6B-v3 / Canary-1B-v2

- **Source**: [arXiv 2509.14128](https://arxiv.org/abs/2509.14128), [NVIDIA developer blog](https://developer.nvidia.com/blog/nvidia-speech-ai-models-deliver-industry-leading-accuracy-and-performance/), [Northflank 2026 STT benchmarks](https://northflank.com/blog/best-open-source-speech-to-text-stt-model-in-2026-benchmarks)
- **What it is**: Open-source, multilingual, top of the 2026 benchmark leaderboards. **Industry-leading accuracy** in 2026.
- **Use case**: server-side, cloud mode. Too heavy for on-device (600M-1B params). Use when user opts into cloud.

### 1.8 Moonshine (Useful Sensors)

- **Source**: [Onresonant 2026 STT comparison](https://www.onresonant.com/resources/local-stt-models-2026)
- **What it is**: Sentence-level STT, very small, fast. Optimized for short utterances.
- **Use case**: low-latency wake-word / command layer, not full dictation.

### 1.9 Kyutai STT

- **Source**: [LinkedIn announcement](https://www.linkedin.com/posts/vaclav-volhejn_weve-just-open-sourced-kyutai-stt-the-speech-to-text-activity-7341441228099522561-geGF), [YouTube demo](https://www.youtube.com/watch?v=FuylIIjtDbs)
- **What it is**: Streaming, real-time, open-sourced by Kyutai (the Moshi team). 2.6B params.
- **Use case**: streaming cloud STT, opt-in.

### 1.10 Voxtral Transcribe 2 (Mistral)

- **Source**: [mistral.ai/news/voxtral-transcribe-2](https://mistral.ai/news/voxtral-transcribe-2/), [Voxtral vs Whisper 2026](https://weesperneonflow.ai/en/blog/2026-03-31-voxtral-whisper-open-source-speech-models-comparison-2026/)
- **What it is**: Mistral's real-time STT. Open weights.
- **Use case**: cloud fallback, alternative to OpenAI Whisper API.

### 1.11 Apple SFSpeechRecognizer (legacy)

- **What it is**: The old Apple STT API, predates SpeechAnalyzer. Tied to cloud for some languages, on-device for others.
- **Use case**: none for v0. SpeechAnalyzer supersedes it.

### 1.12 RealtimeSTT (KoljaB)

- **Repo**: [github.com/KoljaB/RealtimeSTT](https://github.com/KoljaB/RealtimeSTT)
- **What it is**: Python library for low-latency STT with VAD. Reference implementation pattern.
- **Use case**: reference for VAD + streaming design. Not a v0 dependency (we're Swift-native).

### 1.13 STT engine matrix

| Engine | Apple Silicon | On-device | Languages | Latency | License | v0 role |
|---|---|---|---|---|---|---|
| Apple SpeechAnalyzer | Required (M1+) | Yes | 50+ | Lowest | Apple EULA | **Primary** |
| WhisperKit | Required | Yes | 99 | Low | MIT | Fallback |
| FluidAudio | Required | Yes | Limited | Low | Apache 2.0 | Alt fallback |
| MLX-Whisper | Required | Yes | 99 | Low | MIT | Speed option |
| whisper.cpp | Universal | Yes | 99 | Medium | MIT | Intel Mac |
| faster-whisper | Universal | Yes | 99 | Low | MIT | Server fallback |
| NVIDIA Parakeet | No (GPU) | No | 25 | Lowest | Apache 2.0 | Cloud option |
| Kyutai STT | No (GPU) | No | EN/FR | Low | Apache 2.0 | Cloud option |
| Voxtral 2 | No (GPU) | No | EN+ | Low | Apache 2.0 | Cloud option |
| Moonshine | Universal | Yes | EN | Lowest | MIT | Wake-word |

---

## 2. The 2026 voice dictation app landscape

What ships in 2026 that we are competing with (or building on).

### 2.1 Wispr Flow (the incumbent)

- **URL**: [wisprflow.ai](https://wisprflow.ai/)
- **Pricing**: Free / $12-15 Pro / Enterprise.
- **Architecture**: **Cloud only**. Subprocessors: Baseten, OpenAI, Anthropic, Cerebras, AWS. No on-device.
- **March 2026 updates** ([r/WisprFlow](https://www.reddit.com/r/WisprFlow/comments/1s9t41f/march_2026_product_updates/)): notification UI, sleep recovery, fewer duplicate notification sounds. **Polishing, not shipping features.**
- **2026 expansion** ([PR Newswire](https://www.prnewswire.com/news-releases/developers-are-ditching-their-keyboards-as-wispr-flow-expands-to-new-platforms-302399506.html)): expanding to **new platforms** (likely Windows, Linux). This signals they are *not* deepening the Mac experience.
- **For `speak`**: the wedge is everything Wispr Flow *isn't* — local, free, open source, Mac-native. They are moving away from where we are strongest.

### 2.2 Willow Voice

- **URL**: [willowvoice.com](https://willowvoice.com/)
- **Accuracy**: 95%+ claim.
- **Platforms**: Mac, iOS, Windows.
- **Differentiator**: cross-platform polish, Apple-native feel.
- **For `speak`**: not free. Not open source. Our alternative.

### 2.3 Superwhisper

- **URL**: [superwhisper.com](https://superwhisper.com/)
- **Pricing**: $9.99/mo.
- **Platforms**: Mac, Windows, iOS.
- **For `speak`**: cheaper than Wispr but still paid.

### 2.4 Aiko (Sindre Sorhus)

- **URL**: [sindresorhus.com/aiko](https://sindresorhus.com/aiko)
- **Pricing**: **Free**.
- **Architecture**: Whisper, on-device. macOS, iOS.
- **For `speak`**: closest *philosophical* competitor. Sindre ships beautiful native Mac apps. Our differentiation: developer-focused (Fn key UX, command mode, snippet handling), code-aware.

### 2.5 MacWhisper (Sindre Sorhus)

- **Position**: best for local file transcription with system-wide dictation support.
- **For `speak`**: longer-form focused, not push-to-talk dictation. Different niche.

### 2.6 VoiceInk

- **URL**: [tryvoiceink.com](https://tryvoiceink.com/)
- **Position**: lightweight offline Mac dictation.
- **For `speak`**: closest *paid* competitor. Our differentiation: free, open, developer-focused.

### 2.7 TypeWhisper (open source)

- **Source**: [r/macapps](https://www.reddit.com/r/macapps/comments/1r4t83f/os_typewhisper_speechtotext_for_macos_100_local/) — "100% local, no cloud".
- **For `speak`**: direct open-source competitor. Our differentiation: Fn-key UX, Apple SpeechAnalyzer (faster on Apple Silicon), developer-targeted.

### 2.8 FluidVoice (altic-dev)

- **Repo**: [github.com/altic-dev/FluidVoice](https://github.com/altic-dev/FluidVoice)
- **Tagline**: "Fastest macOS Offline Dictation app".
- **For `speak`**: direct open-source competitor. Our differentiation: Apple SpeechAnalyzer integration, explicit developer UX, opt-in local LLM.

### 2.9 Best Open Source Wispr Flow Alternatives 2026 (Voibe)

- **Source**: [getvoibe.com](https://www.getvoibe.com/resources/best-open-source-wispr-flow-alternatives/)
- **For `speak`**: this is the article we want `speak` to top in 6 months.

### 2.10 Voicy — Best Dictation Apps for Mac 2026

- **Source**: [usevoicy.com](https://usevoicy.com/blog/best-dictation-apps-mac-macbook)
- **For `speak`**: another article we want to be #1 in.

### 2.11 Voice agent frameworks (infrastructure, not competitors)

- [LiveKit Agents](https://github.com/livekit/agents) — open source, Python/Node.
- [Pipecat (Daily.co)](https://github.com/pipecat-ai/pipecat) — open source, Python.
- [KoljaB RealtimeSTT](https://github.com/KoljaB/RealtimeSTT) — Python reference impl.
- [yulrizka osx-push-to-talk](https://github.com/yulrizka/osx-push-to-talk) — Swift, push-to-talk reference.
- [awesome-ai-agents-2026](https://github.com/ARUNAGIRINATHAN-K/awesome-ai-agents-2026), [awesome-llm-apps](https://github.com/Shubhamsaboo/awesome-llm-apps) — discovery.
- **For `speak`**: not direct competitors. We don't need their full stacks, but we can borrow patterns.

---

## 3. The MacBook UX primitives (ground truth)

What a Mac-native voice dictation app actually has to do on the OS.

### 3.1 Permissions stack (3 prompts)

A global-hotkey + paste dictation app needs:

1. **Microphone** (`NSMicrophoneUsageDescription` in Info.plist). Required for any audio capture.
2. **Accessibility** — required to monitor global keyboard events (CGEventTap) and to simulate key events (Cmd+V).
3. **Input Monitoring** — required on macOS 10.15+ to receive keystrokes from other apps.
4. *(Optional)* **Speech Recognition** (`NSSpeechRecognitionUsageDescription`) for older SFSpeechRecognizer. **Not needed for SpeechAnalyzer.**

User experience: 3 permission prompts is a *lot*. Onboarding flow must explain *why* each one is needed, with a screenshot of the System Settings pane.

Reference: [Logitech docs on Accessibility + Input Monitoring](https://hub.sync.logitech.com/mk370-combo/post/how-to-enable-accessibility-and-input-monitoring-permissions-for-logitech-RCpLLfkKKtnXTdS), [Omnissa docs](https://docs.omnissa.com/bundle/HorizonClient-MacGuideVmulti/page/AllowingAccesstomacOSAccessibilityFeatures.html).

### 3.2 The Fn key (the user's specific spec)

The user described: **double-tap Fn to start, single-tap Fn to stop & paste.**

- **Fn behavior is OS-controlled** ([YouTube "How To Use the FN/Globe Key On Your Mac Keyboard"](https://www.youtube.com/watch?v=_7VDohUBQKI), [Setapp guide](https://setapp.com/how-to/mac-function-keys)). System Settings → Keyboard → "Use F1, F2, etc. as standard function keys" toggles between media keys and F-keys. The Fn/Globe key is the modifier that flips between them.
- **Fn key sends a unique event** on macOS — `kVK_Function` (0x3F, 63). Different from the F-keys themselves.
- **Double-tap detection is custom.** No macOS API gives you a "double-tap Fn" event. You monitor the key, timestamp, count taps within a 300-500ms window, fire start. Pattern: [Keyboard Maestro thread on double-tap modifiers](https://forum.keyboardmaestro.com/t/double-tap-cmd-opt-shift-control-as-hotkeys/30449).
- **Reference implementation**: [yulrizka/osx-push-to-talk](https://github.com/yulrizka/osx-push-to-talk) — Swift, configurable hotkey, persistent. **Direct inspiration for `speak`.**

**Tradeoffs of the Fn-double-tap design** (must be in the spec):
- ✅ Clear start signal (two taps, unambiguous)
- ✅ No holding required (good for RSI)
- ✅ Fn is in the corner of every MacBook keyboard (easy reach)
- ❌ Slower to start (two taps instead of one)
- ❌ First tap is a "false start" if user means to single-tap
- ❌ Fn behavior varies on external keyboards (may not exist; "Globe" on some)
- ❌ User may have toggled "Use F-keys as standard" — need to handle both Fn and bare F-keys

**Decision: implement Fn double-tap as default, but allow user to rebind to any hotkey in v0 settings.** This includes F-keys, Cmd, Option, Shift, Control combinations. Double-tap Cmd is a familiar pattern (Spotlight, Alfred). Single-tap-to-toggle is also supported as an option.

### 3.3 Paste simulation (the macOS 26.4 wrinkle)

- **macOS 26.4 Paste Protection** ([Michael Tsai blog, 2026-04-09](https://mjtsai.com/blog/2026/04/09/)) — AppleScript and apps that programmatically read the pasteboard now trigger a user permission prompt.
- **The fix**: don't programmatically read the pasteboard. Use `NSPasteboard.general.setString(...)` to *write* the text, then simulate `Cmd+V` keystroke via `CGEvent`. The user explicitly pastes, no prompt.
- **Alternative**: use `AXUIElement` accessibility APIs to set the value of the focused text field directly. This is what Wispr Flow does in some apps. But it requires per-app support and breaks on Electron/CEF apps.
- **Decision for v0**: use `NSPasteboard` + `Cmd+V` simulation. Works in 95% of apps. Document the edge cases (Terminal, password fields, Electron apps).

### 3.4 Apple SpeechAnalyzer integration

- **WWDC25 video**: [developer.apple.com/videos/play/wwdc2025/277](https://developer.apple.com/videos/play/wwdc2025/277/)
- **Guide**: [developer.apple.com/documentation/Speech/bringing-advanced-speech-to-text-capabilities-to-your-app](https://developer.apple.com/documentation/Speech/bringing-advanced-speech-to-text-capabilities-to-your-app)
- **API shape**: `SpeechAnalyzer` → `SpeechTranscriber` (model) → `AudioInput` (input source) → `AnalysisResult` (output). Supports final + partial results, custom vocabulary, multiple locales.
- **Constraint**: macOS 26+ only. Apple Silicon required for the on-device model.

### 3.5 Microphone capture

- `AVAudioEngine` is the standard Swift API for real-time mic capture. Sample rate 16kHz or 48kHz mono.
- For real-time streaming to STT, push buffers into a circular buffer and feed to the transcriber.

### 3.6 Menubar UI (SwiftUI)

- SwiftUI `MenuBarExtra` (macOS 13+) is the right surface. Shows icon, status (idle / listening / processing), quick toggles.
- Optional floating overlay during capture (like Loom's recording dot) — small, top-right, always-on-top.

---

## 4. Local LLM for post-processing (optional)

`speak` does not need an LLM for v0 — pure STT is enough. But LLM post-processing is a major differentiator vs Wispr Flow (which does LLM cleanup in the cloud).

### 4.1 Use cases for LLM post-processing

- **Filler word removal**: "um", "uh", "like", "you know" → removed.
- **Punctuation & capitalization**: "hello world period how are you question mark" → "Hello world. How are you?"
- **Number formatting**: "twenty three thousand" → "23,000".
- **Code-aware mode**: "function add paren a comma b close paren" → `function add(a, b)`.
- **Tone adjustment**: dictation comes out conversational, LLM rewrites for email/Slack.
- **Translation**: dictate in one language, output in another.

### 4.2 Local LLM options (2026)

| Tool | Model | Apple Silicon | RAM | Latency |
|---|---|---|---|---|
| **Ollama + MLX** | Qwen 2.5 3B, Gemma 3 4B, Phi-4-mini | Native MLX | 8GB+ | ~1-2s for 100 words |
| **LM Studio** | Same models, GUI | MLX backend | 8GB+ | ~1-2s |
| **Apple Intelligence** | Apple Foundation Model | M1+ | 4GB unified | <1s, integrated |
| **llama.cpp** | Any GGUF | CPU/Metal | 8GB+ | ~3-5s |

- **Ollama MLX** is now the recommended path ([Ars Technica](https://arstechnica.com/civis/threads/running-local-models-on-macs-gets-faster-with-ollama%E2%80%99s-mlx-support.1512366/)). Much faster than CPU llama.cpp.
- **Apple Intelligence + Writing Tools** ([Apple support page](https://support.apple.com/guide/mac-help/find-the-right-words-with-writing-tools-mchldcd6c260/mac)) is the cleanest in-place rewriting API. Available on Apple Silicon, M1+. But limited to Apple-supported transformations (proofread, rewrite, tone).
- **Small models for cleanup** ([gemma4-ai.com 2026](https://gemma4-ai.com/blog/best-local-ai-models-2026)): Phi-4-mini, Qwen 2.5 3B Instruct, Gemma 3 4B. All fit in 8GB.

### 4.3 Decision: ship Ollama integration in v0, Apple Intelligence in v1

- v0: optional Ollama integration, off by default, user configures model.
- v1: Apple Intelligence "Proofread" + "Rewrite" integration for free, no LLM to install.
- Both layers stack: STT → optional local LLM cleanup → paste.

### 4.4 Streaming UX

If LLM cleanup is enabled, the user sees a streaming partial transcript (live, "hello wor-"), then a 1-2s pause, then the cleaned final text. Status indicators:
- Listening: red dot
- Processing: yellow spinner
- Done: green flash, paste.

---

## 5. Product spec

### 5.1 Personas

| Persona | Use case | Pain with Wispr Flow |
|---|---|---|
| **Dev, MacBook M-series** | Code comments, commit messages, Slack, terminal | $15/mo, audio in cloud, no local-first option |
| **Writer, MacBook** | Long-form text, email, notes | Same + wants offline mode on planes |
| **Accessibility** | RSI, can't type | Same + needs free (vs $15/mo) |
| **Privacy-conscious** | Lawyer, doctor, journalist | **Cloud-only is a deal-breaker** |

### 5.2 Core flows

**Flow 1: Quick dictate (the headline)**
1. User double-taps Fn.
2. Menubar icon turns red. Optional floating dot appears.
3. User speaks.
4. Partial transcript streams in a small overlay.
5. User single-taps Fn.
6. Status: processing (yellow, ~100-500ms).
7. Text is pasted at cursor (Cmd+V simulation).
8. Menubar returns to idle.

**Flow 2: Quick dictate with cleanup**
1-5. Same.
6. Status: processing (yellow, ~1-2s if LLM enabled).
7. Cleaned text is pasted.
8. Optional: "Original" / "Cleaned" toggle on the floating dot during the pause.

**Flow 3: First-run onboarding**
1. Welcome screen: explain what `speak` is, why it's local-first.
2. Microphone permission prompt (with rationale).
3. Speech recognition permission (if needed).
4. Accessibility permission (with deep-link to System Settings).
5. Input Monitoring permission (with deep-link).
6. Hotkey picker (default: double-tap Fn, with alternatives).
7. Test dictation: "say something to test your setup."
8. Done.

**Flow 4: Settings**
- Hotkey: rebind (default double-tap Fn).
- Language: en-US, en-GB, etc.
- LLM cleanup: on/off, model picker.
- Auto-paste: on/off (off = copy to clipboard only).
- Paste mode: simulate Cmd+V (default) / accessibility API per app.
- Snippets: text replacements ("my email" → "tamil@...").
- History: keep last N dictations, searchable.
- Diagnostic: log of last session, model, latency.

### 5.3 Non-goals for v0

- No iOS/iPadOS (Mac-first).
- No Windows / Linux (Mac-only).
- No cloud STT (local-only in v0; cloud opt-in in v1).
- No real-time multi-speaker (single user, one voice).
- No code-aware mode (general dictation only in v0; code mode in v2).
- No team / enterprise features (solo product).

### 5.4 v0 scope (2 weeks)

- macOS 26+, Apple Silicon only.
- Swift + SwiftUI, sandboxed, notarized.
- Apple SpeechAnalyzer STT (en-US).
- Double-tap Fn / single-tap Fn / alternative hotkeys.
- Paste via Cmd+V simulation.
- Menubar UI (start, stop, settings).
- 3-permission onboarding flow.
- Basic history (last 50 dictations).
- No LLM cleanup (defer to v0.1).
- Distributed as `.dmg` + Homebrew Cask.
- License: MIT. Open source.

### 5.5 v0.1 (week 3-4)

- Optional Ollama integration for cleanup.
- Snippets / text replacements.
- More languages.
- Logs / latency metrics.

### 5.6 v1 (month 2)

- Apple Intelligence Writing Tools integration.
- WhisperKit fallback for languages SpeechAnalyzer doesn't cover.
- Cloud STT opt-in (Wispr-quality, user provides API key).
- Intel Mac support (whisper.cpp fallback).

### 5.7 v2 (month 3-4)

- Code-aware mode (auto-detect code context, format accordingly).
- iOS/iPadOS sync.
- Snippet library + import/export.
- Team plan (shared snippets, on-prem).

---

## 6. Architecture

### 6.1 Module layout

```
speak/
  App/                       # SwiftUI app target
    SpeakApp.swift
    MenuBar/
    Onboarding/
    Settings/
  SpeakCore/                 # Framework: headless dictation engine
    AudioCapture.swift       # AVAudioEngine wrapper, 16kHz mono
    HotkeyMonitor.swift      # CGEventTap, double-tap detection
    SpeechTranscriber.swift  # Apple SpeechAnalyzer wrapper
    PasteboardWriter.swift   # NSPasteboard + Cmd+V simulation
    PermissionManager.swift  # Mic / Accessibility / Input Monitoring
    HistoryStore.swift       # SQLite, last N dictations
  SpeakLLM/                  # Optional: Ollama client + prompt templates
    OllamaClient.swift
    CleanupPrompt.swift
  SpeakCLI/                  # CLI shim: `speak --start`, `speak --stop`
    SpeakCLI.swift
  SpeakTests/                # Unit + UI tests
```

### 6.2 Key design decisions

- **`SpeakCore` is a framework, not an app.** Lets us ship a CLI shim, a menubar app, and (later) an iOS app from the same core.
- **No global mutable state.** All state is owned by an `Engine` class injected via SwiftUI environment.
- **Streaming everywhere.** Audio → partial transcript → (optional) LLM streaming → final paste. Every layer streams, nothing blocks.
- **Permissions are first-class.** `PermissionManager` exposes the state machine: `notDetermined → requesting → granted/denied`. UI gates on this.
- **No third-party dependencies for v0.** Use Apple frameworks only. WhisperKit added in v0.1 as the first external dep.

### 6.3 Hotkey design (the Fn double-tap spec)

```swift
final class HotkeyMonitor {
    enum Event { case startCapture, stopCapture }

    private var tap: CGEventTap?
    private var lastFnTap: Date?
    private let doubleTapWindow: TimeInterval = 0.4  // 400ms

    func start() throws {
        tap = CGEvent.tapCreate(
            .cgSessionEventTap,
            .headInsertEventTap,
            .defaultTapOption,
            CGEventMask(1 << kCGEventFlagsChanged),
            { proxy, type, event, refcon in
                // detect Fn down, timestamp, count taps in window
                // emit .startCapture on second tap
                // emit .stopCapture on single tap after capture started
            }
        )
    }
}
```

- Default: double-tap Fn (400ms window) to start, single-tap Fn to stop.
- Configurable: any modifier + key, including single-key, modifier-only, double-tap modifier.
- Persisted in `UserDefaults`.

### 6.4 Paste flow

```swift
final class PasteboardWriter {
    func paste(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        simulateCmdV()
    }

    private func simulateCmdV() {
        let source = CGEventSource(stateID: .hidSystemState)
        let v = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true)  // kVK_ANSI_V
        v?.flags = .maskCommand
        v?.post(tap: .cghidEventTap)
        // ... release
    }
}
```

- Works in 95% of macOS apps. Doesn't trigger macOS 26.4 paste protection prompt (because we *write* not *read*).
- Edge cases: Electron apps may not have keyboard focus reliably. Terminal needs special handling (different paste character handling).
- **Decision for v0**: ship Cmd+V simulation only. Per-app accessibility API in v1.

---

## 7. Build plan

### 7.1 v0 (2 weeks)

| Day | Goal | Done when |
|---|---|---|
| 1 | Xcode project, SwiftUI menubar scaffold | `speak` shows in menubar, "About" panel works |
| 2 | Microphone permission + AVAudioEngine capture | Speak into mic, get raw PCM buffer in console |
| 3 | Apple SpeechAnalyzer integration | Speak, get final text in console |
| 4 | Partial transcript streaming + overlay UI | Speak, see partial text in a small floating window |
| 5 | CGEventTap, double-tap Fn, single-tap Fn | Fn keys trigger start/stop events |
| 6 | Pasteboard + Cmd+V simulation | Final text pastes into focused text field |
| 7 | 3-permission onboarding flow | First-run user grants all 3 perms end-to-end |
| 8 | Menubar status (idle/listening/processing) | Icon changes color on state |
| 9 | History (last 50, SQLite) | Dictations persisted, searchable |
| 10 | Hotkey customization (settings) | User can rebind hotkey, persists across launches |
| 11 | Build, notarize, .dmg, Homebrew Cask | `brew install --cask speak` works |
| 12 | README, screenshots, demo GIF | Repo is public-ready |
| 13 | Internal dogfood for 4 hours | Used `speak` for real Slack/code comments/email |
| 14 | Fix top 3 dogfood issues | Latency < 1s, no false triggers, no permission edge cases |

### 7.2 v0.1 (week 3-4)

- Ollama integration (optional cleanup).
- Snippets / text replacements.
- More languages (en-GB, hi-IN, etc.).
- Per-app paste mode (Cmd+V vs accessibility).
- Telemetry (opt-in, local-only).

### 7.3 v1 (month 2)

- Apple Intelligence Writing Tools integration.
- WhisperKit fallback.
- Cloud STT opt-in.
- Intel Mac support (whisper.cpp).

### 7.4 v2 (month 3-4)

- Code-aware mode.
- iOS/iPadOS.
- Snippet library.
- Team / on-prem.

---

## 8. Differentiation matrix

| Feature | Wispr Flow | Willow Voice | Superwhisper | Aiko | TypeWhisper | FluidVoice | **speak** |
|---|---|---|---|---|---|---|---|
| Price | $15/mo | Paid | $9.99/mo | Free | Free | Free | **Free** |
| Open source | No | No | No | Yes | Yes | Yes | **Yes (MIT)** |
| Local-only | No (cloud) | Hybrid | Hybrid | Yes | Yes | Yes | **Yes** |
| macOS-native | Yes | Yes | Yes | Yes | Yes | Yes | **Yes** |
| Apple SpeechAnalyzer | No | No | No | No | No | No | **Yes (v0 default)** |
| Apple Silicon optimized | Yes | Yes | Yes | Yes | Yes | Yes | **Yes** |
| Fn double-tap hotkey | No | No | No | No | No | No | **Yes** |
| Custom hotkeys | Yes | Yes | Yes | No | No | No | **Yes** |
| LLM cleanup (local) | No | No | No | No | No | No | **Yes (Ollama v0.1)** |
| Apple Intelligence integration | No | No | No | No | No | No | **Yes (v1)** |
| Cloud option | Default | Opt-in | Opt-in | No | No | No | **Yes (v1)** |
| iOS sync | No | Yes | Yes | Yes | No | No | **Yes (v2)** |
| Team / enterprise | Yes | No | No | No | No | No | **Yes (v2)** |

**Three durable differentiators** for `speak`:
1. **Local + free + open source.** The only Mac-native dictation app in 2026 that is all three.
2. **Apple SpeechAnalyzer first.** Fastest on Apple Silicon, no model download, no licensing, no cloud.
3. **Developer-first UX.** Fn double-tap, code-aware mode (v2), CLI shim, scriptable.

---

## 9. Risks

| Risk | Likelihood | Mitigation |
|---|---|---|
| Apple SpeechAnalyzer quality worse than Wispr in noisy environments | Medium | WhisperKit fallback in v0.1; document noise limitations |
| Fn key behavior is OS-controlled, can conflict | High | Customizable hotkey from v0; document Fn vs F-key behavior |
| macOS 26.4 paste protection breaks Cmd+V simulation | Low | We *write* to pasteboard, not *read*; Cmd+V is user-initiated; shouldn't trigger prompt |
| 3-permission onboarding drops 30% of users | High | Streamline flow, deep-link to System Settings, video walkthrough |
| Local LLM cleanup adds 1-2s latency | Medium | Streaming UI shows progress; user can disable per session |
| Apple doesn't ship SpeechAnalyzer to Intel Macs | Certain | WhisperKit / whisper.cpp fallback in v1; v0 Apple-Silicon-only |
| Wispr Flow copies the local-first model | Low (2026) | We are open source; community moat; developer UX |
| Ollama install friction for non-developers | High (for non-devs) | Apple Intelligence integration in v1 removes the dep |

---

## 10. Open questions for the user

1. **Working name `speak` OK?** Or do you have a preferred name?
2. **v0 Apple-Silicon-only, or backport to Intel?** Apple-Silicon-only is dramatically simpler. Wispr Flow / Willow / etc. all support Intel. What's the GTM implication?
3. **Open source (MIT) or source-available?** Open source gets community contributions + trust; source-available keeps competitive moat.
4. **Distribution: Homebrew Cask + .dmg only, or Mac App Store too?** Mac App Store is harder (sandboxing limits global hotkeys), but more discoverable.
5. **LLM cleanup: ship Ollama in v0 or v0.1?** I recommend v0.1 — keeps v0 focused on the core STT experience.
6. **Brand / design?** Need a name, icon, color. Suggest minimal: SF Symbol `waveform` in monochrome, accent color TBD.
7. **Website / landing page?** Recommend a simple `speak.md` site for v0; full site post-launch.

---

## 11. Sources (primary, 2025-2026)

### STT engines
- [Apple SpeechAnalyzer docs](https://developer.apple.com/documentation/speech/speechanalyzer)
- [Apple WWDC25: Bring advanced speech-to-text to your app](https://developer.apple.com/videos/play/wwdc2025/277/)
- [Apple: Advanced speech-to-text capabilities guide](https://developer.apple.com/documentation/Speech/bringing-advanced-speech-to-text-capabilities-to-your-app)
- [Argmax: Apple SpeechAnalyzer and WhisperKit comparison](https://www.argmaxinc.com/blog/apple-and-argmax)
- [Argmax WhisperKit repo](https://github.com/argmaxinc/argmax-oss-swift)
- [Argmax vs whisper.cpp on Cactus Compute](https://cactuscompute.com/compare/argmax-vs-whisper-cpp)
- [FluidAudio repo](https://github.com/FluidInference/FluidAudio)
- [FluidAudio on CocoaPods](https://cocoapods.org/pods/FluidAudio)
- [MLX-Whisper / lightning-whisper-mlx](https://github.com/mustafaaljadery/lightning-whisper-mlx)
- [Ars Technica: Ollama MLX support](https://arstechnica.com/civis/threads/running-local-models-on-macs-gets-faster-with-ollama%E2%80%99s-mlx-support.1512366/)
- [SitePoint: Local LLMs Apple Silicon Mac 2026](https://www.sitepoint.com/local-llms-apple-silicon-mac-2026/)
- [NVIDIA Canary & Parakeet (arXiv 2509.14128)](https://arxiv.org/abs/2509.14128)
- [NVIDIA speech AI blog](https://developer.nvidia.com/blog/nvidia-speech-ai-models-deliver-industry-leading-accuracy-and-performance/)
- [Northflank best open source STT 2026](https://northflank.com/blog/best-open-source-speech-to-text-stt-model-in-2026-benchmarks)
- [Onresonant Moonshine vs Parakeet 2026](https://www.onresonant.com/resources/local-stt-models-2026)
- [Modal: choosing Whisper variants](https://modal.com/blog/choosing-whisper-variants)
- [Modal: top open-source STT models](https://modal.com/blog/open-source-stt)
- [Kyutai STT open source announcement](https://www.linkedin.com/posts/vaclav-volhejn_weve-just-open-sourced-kyutai-stt-the-speech-to-text-activity-7341441228099522561-geGF)
- [Voxtral Transcribe 2 (Mistral)](https://mistral.ai/news/voxtral-transcribe-2/)
- [Voxtral vs Whisper 2026](https://weesperneonflow.ai/en/blog/2026-03-31-voxtral-whisper-open-source-speech-models-comparison-2026/)
- [RealtimeSTT (KoljaB)](https://github.com/KoljaB/RealtimeSTT)
- [Best small LLMs 2026](https://gemma4-ai.com/blog/best-local-ai-models-2026)

### Mac dictation apps
- [Wispr Flow](https://wisprflow.ai/)
- [Wispr Flow March 2026 updates (Reddit)](https://www.reddit.com/r/WisprFlow/comments/1s9t41f/march_2026_product_updates/)
- [Wispr Flow engineering blog](https://wisprflow.ai/post/technical-challenges)
- [PR Newswire: Wispr Flow expands to new platforms](https://www.prnewswire.com/news-releases/developers-are-ditching-their-keyboards-as-wispr-flow-expands-to-new-platforms-302399506.html)
- [Willow Voice](https://willowvoice.com/)
- [Willow Voice G2 reviews](https://www.g2.com/products/willow-voice/reviews)
- [Superwhisper](https://superwhisper.com/)
- [Aiko (Sindre Sorhus)](https://sindresorhus.com/aiko)
- [Aiko on Whisper discussion #1300](https://github.com/openai/whisper/discussions/1300)
- [TypeWhisper (r/macapps)](https://www.reddit.com/r/macapps/comments/1r4t83f/os_typewhisper_speechtotext_for_macos_100_local/)
- [FluidVoice (altic-dev)](https://github.com/altic-dev/FluidVoice)
- [Voibe: Best Open Source Wispr Flow Alternatives 2026](https://www.getvoibe.com/resources/best-open-source-wispr-flow-alternatives/)
- [Voicy: Best Dictation Apps for Mac 2026](https://usevoicy.com/blog/best-dictation-apps-mac-macbook)

### Mac UX primitives
- [yulrizka osx-push-to-talk](https://github.com/yulrizka/osx-push-to-talk)
- [Keyboard Maestro: double-tap modifier hotkeys](https://forum.keyboardmaestro.com/t/double-tap-cmd-opt-shift-control-as-hotkeys/30449)
- [macOS 26.4 Paste Protection (Michael Tsai blog, 2026-04-09)](https://mjtsai.com/blog/2026/04/09/)
- [Logitech: Accessibility + Input Monitoring permissions](https://hub.sync.logitech.com/mk370-combo/post/how-to-enable-accessibility-and-input-monitoring-permissions-for-logitech-RCpLLfkKKtnXTdS)
- [Omnissa: macOS Accessibility permissions](https://docs.omnissa.com/bundle/HorizonClient-MacGuideVmulti/page/AllowingAccesstomacOSAccessibilityFeatures.html)

### Voice agent / adjacent
- [LiveKit Agents](https://github.com/livekit/agents)
- [Pipecat (Daily.co)](https://github.com/pipecat-ai/pipecat)
- [awesome-ai-agents-2026](https://github.com/ARUNAGIRINATHAN-K/awesome-ai-agents-2026)
- [awesome-llm-apps](https://github.com/Shubhamsaboo/awesome-llm-apps)
- [ByteByteGo top AI repos 2026](https://blog.bytebytego.com/p/top-ai-github-repositories-in-2026)
- [Top Voice AI Agent Frameworks 2026](https://medium.com/@mahadise0011/top-voice-ai-agent-frameworks-in-2026-a-complete-guide-for-developers-4349d49dbd2b)
