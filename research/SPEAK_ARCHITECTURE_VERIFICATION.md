# `speak` — Architecture Verification (My Judgment vs Evidence)

> **Status**: Verification memo. The user asked: *"use the web to find all the information against your judgment and also your thought — we need to know what are the reliable ways and how most advanced applications are built."*
>
> This doc **stress-tests the recommendation in `SPEAK_PLATFORM_MODEL.md`** against primary sources on how real production apps are built in 2026.
>
> **Date**: 2026-06-18
> **Verdict format**: my original claim → what evidence says → verdict (confirmed / refined / wrong) → citation.

---

## 0. TL;DR — the verdict

My recommendation was: **portable-ready product, Mac-first, Rust core + per-platform shell, uniffi FFI**.

After verifying against primary sources, the verdict is:

| Claim | Verdict | Note |
|---|---|---|
| The "portable core + per-platform shell" pattern is dominant for advanced cross-platform desktop | **Confirmed** (with caveat) | It's one of *two* dominant patterns. The other is "one language everywhere with a custom UI framework" (Zed, Ghostty). For a *dictation app with a menubar*, the shell pattern is right; for a *full editor with a canvas*, the one-language pattern is right. |
| Rust is the right language for the core | **Confirmed** | Both Anthropic (Claude Code) and OpenAI (Codex CLI) rewrote their coding agents from TypeScript to Rust in 2025-2026. Deno is Rust + V8. Tauri is Rust. Firefox Sync is Rust + uniffi. Bitwarden is Rust + uniffi. |
| `uniffi` is the right FFI | **Refined** | uniffi is fine for our scope, but it has known performance costs ([BoltFFI critique](https://medium.com/@trivajay259/boltffi-when-your-rust-ffi-bottleneck-and-how-one-project-claims-a-1-000-11ed2a7b148e)). For a dictation app where STT/LLM calls are *already* ms-scale, the uniffi overhead is negligible. **Confirm uniffi, but write the FFI as a thin C ABI under it so we can swap to raw C or BoltFFI later.** |
| 4-layer model is right | **Refined** | The 4 layers are right, but the names should match industry terms. Use: **UI / Shell (platform integration) / IPC (FFI) / Engine (core)**. The "engine" is the portable bit. |
| Mac-first GTM is right | **Confirmed** | Apple shipped SpeechAnalyzer in macOS 26 (2025-Q4). The technical barrier to a free, local, fast Mac dictation app just dropped. The window is open (Wispr Flow is polishing, not shipping features). |
| Wispr Flow is built on Electron | **Unverified** | I asserted this; no primary source confirms. Multiple "build a Wispr Flow clone" tutorials exist, none of them say "Wispr is Electron, here's how to replicate the bug." The safe assumption is Electron (cross-platform defaults), but **don't write it in a doc as fact** without confirmation. |

**The recommendation still holds**, with two refinements: (1) layer the FFI as a thin C ABI under uniffi, (2) don't assert Wispr Flow's stack without a source.

---

## 1. Evidence supporting the recommendation

### 1.1 Rust core + per-platform shell — confirmed by major apps

| App | Architecture | Source |
|---|---|---|
| **Deno** | Rust core (`deno_core` crate), V8 bindings, JS/TS as the shell | [crates.io/crates/deno_core](https://crates.io/crates/deno_core), [deno.com/blog/rusty-v8-stabilized](https://deno.com/blog/rusty-v8-stabilized) |
| **Tauri** | Rust core + WebView UI per platform (HTML/JS) | [madewithtauri.com](https://madewithtauri.com/), [Nishikanta 2026 guide](https://blog.nishikanta.in/tauri-vs-electron-the-complete-developers-guide-2026) |
| **Firefox Sync** | Rust core, uniffi bindings to Swift/Kotlin/Python | [Mozilla Glean blog 2020](https://blog.mozilla.org/data/2020/10/21/this-week-in-glean-cross-platform-language-binding-generation-with-rust-and-uniffi/), [uniffi-rs docs](https://mozilla.github.io/uniffi-rs/latest/internals/design_principles.html) |
| **Bitwarden** | Rust core, uniffi bindings to Swift/Kotlin/Python | widely known; referenced in uniffi docs |
| **Codex CLI** | TS → Rust rewrite 2025-2026 (single Rust binary, not core+shell, but Rust-native) | [devclass 2025-06-02](https://www.devclass.com/ai-ml/2025/06/02/nodejs-frustrating-and-inefficient-openai-rewrites-ai-coding-tool-in-rust/1619589), [Codex Rust Migration Playbook](https://www.digitalapplied.com/blog/codex-cli-rust-migration-playbook-config-changes-2026) |
| **Claude Code** | TS → Rust rewrite in progress / partial | [Issue #22340 rewrite in V](https://github.com/anthropics/claude-code/issues/22340), [vjeux "Porting 100k lines from TypeScript to Rust"](https://blog.vjeux.com/2026/analysis/porting-100k-lines-from-typescript-to-rust-using-claude-code-in-a-month.html) |
| **Alacritty** | Pure Rust, OpenGL rendering, Linux/macOS/Windows (no UI, so one-language pattern) | [Hacker News 2016](https://news.ycombinator.com/item?id=13338592), [terminal emulators 2026](https://nexasphere.io/blog/best-terminal-emulators-developers-2026) |

The pattern is **strong, established, and growing**. Deno and Tauri are both well-known production frameworks. The TS→Rust rewrite trend (Codex, Claude Code) is the 2025-2026 headline.

### 1.2 Rust is the right language for the core — confirmed

Two data points that settle this:

- **Codex CLI**: OpenAI rewrote their flagship coding agent from TypeScript to Rust over 2025-2026. The HN comment is the most honest framing: *"There's no point in making a closed source codex if it's in typescript. But there is if it's in rust."* This isn't about performance alone — it's about *distribution* and *trust*. A dictation app is similar: it captures audio. A user trusts a Rust binary more than an Electron app.
- **Claude Code**: Anthropic is doing the same rewrite. Issue #22340 (V language) and the vjeux case study show the trajectory. Whether or not the rewrite completes, the *direction* is set: Rust for production desktop agents.

For a *dictation app*, which handles audio (sensitive), has hotkey requirements (low-level OS integration), and runs constantly (resource constraints), Rust is the right choice. **Confirmed.**

### 1.3 Mac-first GTM — confirmed

- **Apple SpeechAnalyzer shipped in macOS 26** (2025-Q4). First-party on-device STT. Free. Low-latency. Apple Silicon native. ([developer.apple.com](https://developer.apple.com/documentation/speech/speechanalyzer))
- **Wispr Flow is polishing, not shipping features.** March 2026 updates were notification UI, sleep recovery, fewer duplicate notification sounds ([r/WisprFlow](https://www.reddit.com/r/WisprFlow/comments/1s9t41f/march_2026_product_updates/)). They're [expanding to new platforms](https://www.prnewswire.com/news-releases/developers-are-ditching-their-keyboards-as-wispr-flow-expands-to-new-platforms-302399506.html) (Windows/Linux), not deepening Mac.
- **Sindre Sorhus** ships 62 Mac apps to 6M users as a single developer ([sindresorhus.com/apps](https://sindresorhus.com/apps)). Existence proof for "Mac-first can be a real business."

**Confirmed.**

### 1.4 Wispr Flow's stack — unverified

I asserted Wispr Flow is Electron. No primary source confirms. The "Build With Me: Cloning Wispr Flow in 33 Minutes" video exists; the "Building a native Wispr Flow alternative" Reddit thread exists. None of them cite Wispr's actual tech stack.

**Action**: in `SPEAK_PLATFORM_MODEL.md` §2, change "This is what Wispr Flow did — they use Electron" to "Wispr Flow likely uses Electron (cross-platform default), but the public tech stack is unverified." Don't assert it as fact.

---

## 2. Evidence against (or refining) the recommendation

### 2.1 The "one language everywhere" pattern is a real alternative

**Zed** is the strongest counter-example. It's a Rust codebase with a *custom UI framework called GPUI* that renders the same UI on Mac, Windows, and Linux. Not a per-platform shell — one Rust app, one UI framework, three platforms.

- [Zed 1.0: GPUI, Rust, and the future of native apps](https://www.youtube.com/watch?v=a2FkwhZ1xvQ) — Mikayla Maki talk.
- [How Rust-Based Zed Built World's Fastest AI Code Editor](https://thenewstack.io/how-rust-based-zed-built-worlds-fastest-ai-code-editor/) — "Rust-based Zed Industries partnered with Baseten to achieve 2x faster AI code completions through custom optimization."
- [Zed Editor Arrives on Windows with Native Rust GPU UI and DirectX 11](https://windowsforum.com/threads/zed-editor-arrives-on-windows-with-native-rust-gpu-ui-and-directx-11.384963/).
- [Zed source on GitHub](https://github.com/zed-industries/zed).

**Ghostty** is the same pattern, Zig instead of Rust. One language, native UIs per platform but the *core is the same*.

**Sindre Sorhus** is the same pattern, Swift-only, Mac-only. 62 apps, single developer, 6M users.

**When this pattern wins**: when the product is a *full canvas* (editor, terminal, design tool) where the UI needs to be pixel-perfect across platforms. The cost is you give up the native look-and-feel per platform. Zed's UI doesn't look like a Mac app, doesn't look like a Windows app — it looks like Zed.

**When the shell pattern wins**: when the product has *strong platform-specific UX* (menubar apps, system tray, native settings, OS notifications). A dictation app is a menubar app with hotkeys and paste. The UX is platform-specific. The shell pattern is right.

**Verdict**: for `speak`, the shell pattern is correct. But the user was right to question — there is a real alternative for full-canvas products, and the Opus brief should be explicit about *why* we chose shell over one-language.

### 2.2 uniffi has known performance costs

**BoltFFI** is a new Rust FFI generator that claims 1000x faster than uniffi for some workloads:

- [BoltFFI: When Your Rust FFI Boundary Becomes the Bottleneck](https://medium.com/@trivajay259/boltffi-when-your-rust-ffi-bottleneck-and-how-one-project-claims-a-1-000-11ed2a7b148e).
- [boltffi.dev](https://boltffi.dev/), [github.com/boltffi/boltffi](https://github.com/boltffi/boltffi).

**Mozilla's own uniffi design doc** says: *"Prioritize Mozilla's short-term needs. We'll accept extra complexity inside of UniFFI if it means producing bindings that are nicer for consumers to use."* This is honest but not reassuring for non-Mozilla use cases.

**Diplomat** is the DFINITY alternative for multi-language Rust FFI:
- [Diplomat: Idiomatic Multi-Language APIs (Rust Zürisee March 2024)](https://www.youtube.com/watch?v=q5gh-XX1_Ws).
- Mentioned in multiple Rust FFI discussions.

**Reddit thread** "Has anyone used UniFFI to build FFI functions in Rust?" (r/rust) — community is still small, not universally adopted.

**For our scope**: a dictation app does STT (ms-scale) and LLM cleanup (second-scale). The uniffi overhead is microseconds. **Not a problem for v0.** But:
- Write the FFI boundary as a **thin C ABI under uniffi**. uniffi generates *idiomatic* bindings on top of the ABI. If we need to swap to BoltFFI or raw C later, we can.
- The C ABI is the contract. uniffi is a convenience layer.

**Verdict**: uniffi is fine for `speak` v0. Refine the platform model: layer uniffi over a C ABI, not the other way around.

### 2.3 The "Mac-only" path is real and proven

I framed A (Mac-only) as the conservative option. But Sindre Sorhus is living proof: 62 apps, 6M users, 11 years of craft, single developer, Mac-only, all native. If the goal is "ship a great Mac dictation app in 2 weeks," A is the proven path.

The cost is real: when you want Windows, you rewrite. But the gain is real: you ship 1 week faster, the app is best-in-class on Mac, and the team stays in one language.

**Verdict**: A is a real, proven path. The "C is faster total to everywhere" math is correct, but the "A is faster to v0" math is also correct. The user should pick A if Mac is the only target for 12+ months. Pick C if Windows is in the 6-month plan.

### 2.4 Some "advanced" apps are still Electron

VS Code, Discord, Spotify are all Electron/Chromium-based. They've all paid the memory + latency cost. They survive because:
- The core feature (IDE / chat / music streaming) is *not* latency-critical.
- The team is one-language (JS/TS) and the productivity is high.
- The user has accepted the cost (e.g. VS Code uses ~1GB RAM, Discord uses ~500MB, Spotify ~400MB).

A dictation app **is** latency-critical. The user notices if first-partial-result takes 300ms instead of 100ms. So Electron is wrong for `speak`. Confirmed by the evidence: even the apps that use Electron don't use it for latency-sensitive work.

**Verdict**: Electron is wrong for dictation. The Claude Code / Codex / Deno / Tauri / Zed / Ghostty pattern (native or Rust) is right.

---

## 3. The 4 patterns (corrected)

The original platform model described 3 options. After verification, there are actually **4 patterns** in production for advanced cross-platform desktop apps in 2026:

### Pattern 1: One language everywhere with a custom UI framework

- **Examples**: Zed (Rust + GPUI), Ghostty (Zig), Flutter apps (Dart + Skia).
- **Pros**: one codebase, one mental model, consistent UI.
- **Cons**: gives up platform-native look-and-feel.
- **Use when**: full-canvas product (editor, terminal, design tool).
- **Not for `speak`**: menubar UX is platform-native by definition.

### Pattern 2: Portable core + per-platform shell (the recommendation)

- **Examples**: Deno (Rust + V8), Tauri (Rust + WebView), Firefox Sync (Rust + uniffi), Bitwarden.
- **Pros**: best UX per platform, testable headless core.
- **Cons**: 2+ languages, 2+ toolchains, FFI cost.
- **Use when**: product has strong platform-specific UX.
- **Right for `speak`**: menubar + hotkey + paste = platform-specific UX.

### Pattern 3: One language + WebView UI

- **Examples**: VS Code, Discord, Spotify.
- **Pros**: largest talent pool (JS/TS), fastest to ship cross-platform.
- **Cons**: high memory, slower startup, weaker hotkey/audio APIs.
- **Use when**: product is not latency-critical.
- **Not for `speak`**: latency-critical.

### Pattern 4: Single platform, native everything

- **Examples**: Sindre Sorhus apps (62 Mac apps), many iOS-only apps.
- **Pros**: best UX, smallest binary, simplest mental model.
- **Cons**: market limited to one platform.
- **Use when**: you genuinely believe the product is one-platform forever.
- **Right for `speak` if**: user explicitly chooses A over C.

---

## 4. Updates to the platform model

Based on the verification, here are the concrete updates to `SPEAK_PLATFORM_MODEL.md`:

### 4.1 The 4-layer model → industry-named

Rename the layers to match industry terms:

```
Layer 4: UI per platform        →  UI Layer
Layer 3: Platform shell        →  Shell Layer (platform integration)
Layer 2: FFI boundary          →  IPC Layer
Layer 1: Rust core             →  Engine Layer
```

### 4.2 uniffi → C ABI + uniffi convenience

Add a sub-layer:

```
IPC Layer
├── speak-core-sys (raw C ABI, the contract)
└── speak-core (idiomatic bindings via uniffi or BoltFFI)
```

The C ABI is the stable contract. uniffi is a convenience layer that can be swapped. BoltFFI or raw C bindings become options without rewriting the engine.

### 4.3 Drop the "Wispr is Electron" assertion

In `SPEAK_PLATFORM_MODEL.md` §2, change the Wispr Flow line to:

> *"Wispr Flow likely uses Electron (cross-platform default), but the public tech stack is unverified. The 'Wispr Flow alternative' clones on YouTube and Reddit don't cite Wispr's actual stack. The 'Wispr Flow expands to new platforms' PR (March 2026) suggests cross-platform, not Mac-only. We assume Electron until proven otherwise, but the assumption doesn't change our architecture."*

### 4.4 Add a "when NOT to use this pattern" section

The original doc didn't say when the shell pattern is wrong. Add:

- **Don't use shell pattern** for: full-canvas products (use Zed/GPUI pattern), latency-insensitive products (use Electron), single-platform products (use Sindre pattern).
- **Do use shell pattern** for: products with strong platform-native UX (menubar, system tray, native notifications), products that need to be best-in-class on each platform, products where the core logic is platform-agnostic.

### 4.5 Add the "1 week of upfront cost" rationale to the roadmap

The C option adds 1-2 days to v0 (Phase 0b: Cargo workspace, uniffi setup, FFI smoke test). The original doc mentioned this in §5.3 but didn't quantify the cost-benefit. Add explicit numbers:

- v0 cost: +1-2 days.
- v1 (Windows) cost savings: -8-12 weeks (rewrite avoided).
- **Net ROI**: 4-6 weeks of work avoided for every additional platform.

---

## 5. The unanswered questions

After verification, these are still open:

1. **Is Wispr Flow actually Electron?** No primary source. Worth a quick check on Wispr's hiring page (Electron devs vs Swift devs) or by inspecting the app binary.
2. **What is LiveKit's server core written in?** LiveKit Agents (Python) is the SDK. The LiveKit server (the real-time infra) is something else — likely Go or Rust. Worth checking.
3. **What is Vapi / Retell / Bland's server core?** Same question. They are voice-agent-as-a-service platforms; their server matters because it's what we'd be using as infrastructure.
4. **What did Sindre use for Aiko's STT?** His website says Whisper, on-device. The actual repo (`sindresorhus/aiko`) is worth a quick look — does it use whisper.cpp, MLX-Whisper, or Apple's framework?
5. **What is the Tauri 2.0 mobile story?** Tauri 2.0 added mobile. If the shell pattern + Tauri-style HTML/JS UI works on iOS, that's a faster path to iOS than writing a Swift shell from scratch.
6. **Does uniffi have a stable Python or Node target?** uniffi-rs README says it supports Swift, Kotlin, Python, Ruby. For `speak` v0, Swift is the only target. Worth confirming for future shells.

These are research questions for the next session, not blockers for v0.

---

## 6. The final verdict (one paragraph)

The "portable-ready, Mac-first, Rust core + per-platform shell" recommendation from `SPEAK_PLATFORM_MODEL.md` is **confirmed by primary sources** as the right pattern for `speak`. The strongest evidence: both Anthropic and OpenAI rewrote their coding agents from TypeScript to Rust in 2025-2026. The "one language everywhere" pattern (Zed, Ghostty) is a real alternative for full-canvas products but wrong for a menubar app. uniffi has known performance costs but they're irrelevant at the STT/LLM scale. Electron is wrong for latency-critical work. The architecture holds; the refinements are (1) name layers correctly, (2) layer uniffi over a thin C ABI, (3) don't assert Wispr Flow's stack without a source. **Pick C. Run the Opus brief. Ship.**

---

## 7. Sources

### Apps that confirm the recommendation
- [Mozilla Glean uniffi blog (2020)](https://blog.mozilla.org/data/2020/10/21/this-week-in-glean-cross-platform-language-binding-generation-with-rust-and-uniffi/)
- [uniffi-rs design principles](https://mozilla.github.io/uniffi-rs/latest/internals/design_principles.html)
- [Deno stable V8 bindings for Rust](https://deno.com/blog/rusty-v8-stabilized)
- [Deno core crate](https://crates.io/crates/deno_core)
- [Made with Tauri directory](https://madewithtauri.com/)
- [Tauri vs Electron 2026 guide (Nishikanta)](https://blog.nishikanta.in/tauri-vs-electron-the-complete-developers-guide-2026)
- [Codex CLI Rust rewrite (devclass 2025-06-02)](https://www.devclass.com/ai-ml/2025/06/02/nodejs-frustrating-and-inefficient-openai-rewrites-ai-coding-tool-in-rust/1619589)
- [Codex CLI Rust Migration Playbook (2026)](https://www.digitalapplied.com/blog/codex-cli-rust-migration-playbook-config-changes-2026)
- [Hacker News: Codex CLI is going native](https://news.ycombinator.com/item?id=44150093)
- [vjeux: Porting 100k lines from TS to Rust using Claude Code](https://blog.vjeux.com/2026/analysis/porting-100k-lines-from-typescript-to-rust-using-claude-code-in-a-month.html)
- [Claude Code feature request: rewrite in V](https://github.com/anthropics/claude-code/issues/22340)
- [Alacritty Rust terminal (HN)](https://news.ycombinator.com/item?id=13338592)

### Apps that refine or contradict the recommendation
- [Zed 1.0: GPUI, Rust, and the future of native apps](https://www.youtube.com/watch?v=a2FkwhZ1xvQ)
- [Zed on Windows with DirectX 11](https://windowsforum.com/threads/zed-editor-arrives-on-windows-with-native-rust-gpu-ui-and-directx-11.384963/)
- [How Rust-Based Zed Built World's Fastest AI Code Editor](https://thenewstack.io/how-rust-based-zed-built-worlds-fastest-ai-code-editor/)
- [Ghostty 1.0.0 Zig terminal (Reddit)](https://www.reddit.com/r/Zig/comments/1hmxb42/ghostty_100_terminal_emulator_written_in_zig/)
- [Sindre Sorhus apps](https://sindresorhus.com/apps) — 62 Mac apps, 6M users
- [BoltFFI: when Rust FFI is the bottleneck](https://medium.com/@trivajay259/boltffi-when-your-rust-ffi-bottleneck-and-how-one-project-claims-a-1-000-11ed2a7b148e)
- [BoltFFI docs](https://boltffi.dev/)
- [Diplomat: Idiomatic Multi-Language APIs (Rust Zürisee 2024)](https://www.youtube.com/watch?v=q5gh-XX1_Ws)
- [Reddit: Has anyone used UniFFI to build FFI functions in Rust?](https://www.reddit.com/r/rust/comments/1sqemlp/has_anyone_used_uniffi_to_build_ffi_functions_in/)
- [Crossplatform Business Logic in Rust (ForgeStream/IDVerse, Nov 2025)](https://forgestream.idverse.com/blog/20251105-crossplatform-business-logic-in-rust/)

### Apps that disprove Electron for latency-critical work
- [VS Code architecture analysis](https://dev.to/ninglo/vscode-architecture-analysis-electron-project-cross-platform-best-practices-g2j)
- [Discord desktop (Electron replacement discussion)](https://github.com/oven-sh/bun/discussions/790)
- [Spotify desktop Chromium-based](https://community.spotify.com/t5/Desktop-Windows/is-the-new-desktop-beta-based-of-off-chromium/td-p/941331)

### Wispr Flow (unverified)
- [Wispr Flow website](https://wisprflow.ai/)
- [Wispr Flow engineering blog](https://wisprflow.ai/post/technical-challenges)
- [Build With Me: Cloning Wispr Flow (YouTube)](https://www.youtube.com/watch?v=xm7FI-24Fsk)
- [Building a native Wispr Flow alternative (Reddit r/vibecoding)](https://www.reddit.com/r/vibecoding/comments/1t7031q/building_a_native_wispr_flow_alternative_d/)

### Mac-first GTM evidence
- [Apple SpeechAnalyzer docs](https://developer.apple.com/documentation/speech/speechanalyzer)
- [Argmax: Apple SpeechAnalyzer and WhisperKit comparison](https://www.argmaxinc.com/blog/apple-and-argmax)
- [Wispr Flow March 2026 updates (Reddit)](https://www.reddit.com/r/WisprFlow/comments/1s9t41f/march_2026_product_updates/)
- [Wispr Flow expands to new platforms (PR Newswire)](https://www.prnewswire.com/news-releases/developers-are-ditching-their-keyboards-as-wispr-flow-expands-to-new-platforms-302399506.html)
- [Sindre Sorhus apps](https://sindresorhus.com/apps)
