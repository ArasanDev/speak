# Correction: Claude Code is TypeScript + Bun, not Rust

> **Status**: Correction memo. I made a factual error in `SPEAK_ARCHITECTURE_VERIFICATION.md` §1.2 and `SPEAK_PLATFORM_MODEL.md`. This memo states the corrected facts, shows the local evidence, and updates the recommendation.
>
> **Date**: 2026-06-18
> **What was wrong**: I claimed "Both Anthropic and OpenAI rewrote their coding agents from TypeScript to Rust in 2025-2026. Massive signal." The first half is wrong. **Anthropic did not rewrite Claude Code to Rust. Claude Code is still TypeScript, compiled with Bun into a native binary.** The second half (OpenAI's Codex CLI) is right.
>
> **Why it matters**: this correction changes the narrative from "Rust is the inevitable choice" to "TypeScript + Bun and Rust are both viable choices for production coding agents in 2026." That has real consequences for the `speak` architecture recommendation.

---

## 0. The corrected fact, in one line

**Claude Code 2.1.181 (June 2026) is TypeScript source code, compiled to a native Mach-O arm64 binary by Bun. It is not Rust.**

**Codex CLI (2025-2026) is Rust, rewritten from TypeScript.**

Two different products, two different stacks. I conflated them.

---

## 1. The local evidence (verified on this Mac, 2026-06-18)

The user's machine has Claude Code installed at:

```
/Users/tamil/.local/bin/claude -> /Users/tamil/.local/share/claude/versions/2.1.181
```

Inspection:

```
$ file /Users/tamil/.local/share/claude/versions/2.1.181
/Users/tamil/.local/share/claude/versions/2.1.181: Mach-O 64-bit executable arm64

$ du -sh /Users/tamil/.local/share/claude/versions/2.1.181
205M    /Users/tamil/.local/share/claude/versions/2.1.181
```

`strings` output on the binary (filtered for runtime identifiers) shows:

- `---- Bun! ----` (Bun's banner)
- `__bun`, `__BUN`
- `BUN_PORT`, `BUN_CONFIG_TOKEN`, `NPM_CONFIG_TOKEN`
- `bun.lock`, `bun-repl`, `bun.fish`
- `--bun` CLI flag
- `node_modules_tmp`, `node-gyp rebuild`, `"workspaces": { "bundled": true }`
- `node:net`, `node:os`, `node:sys`, `node:tty`, `node:url` (Node-API compatibility)
- `transpiler_cache`, `JSVALUE_TO_BOOL`, `e_branch_boolean`, `e_name_of_symbol`
- `index.ts`, `index.js` (TypeScript entry points)

This is the **Bun runtime + TypeScript toolchain, compiled into a single Mach-O binary**. Not Rust. The 205MB size is consistent with Bun + Node-API + bundled JS modules + TypeScript transpiler.

---

## 2. The primary sources (web, 2026)

### 2.1 The source-code leak (2026-03-31, definitive)

Anthropic accidentally shipped a source map file in `@anthropic-ai/claude-code@2.1.88` (March 31, 2026), exposing the full TypeScript source. Security researcher Chaofan Shou (`@Fried_rice`) discovered and analyzed it. Multiple primary sources:

- **The Pragmatic Engineer** (Sep 23, 2025): [newsletter.pragmaticengineer.com/p/how-claude-code-is-built](https://newsletter.pragmaticengineer.com/p/how-claude-code-is-built) — "A rare look into how the new, popular dev tool is built."
- **The leak write-up**: [dev.to/stevengonsalvez/claude-code-source-code-leaked-512k-lines-of-typescript-and-what-actually-matters-4k06](https://dev.to/stevengonsalvez/claude-code-source-code-leaked-512k-lines-of-typescript-and-what-actually-matters-4k06) — "The Claude Code leak is catnip for this pattern. It's 512,000 lines of production TypeScript from one of the most interesting AI companies in..."
- **InfoQ**: [infoq.com/news/2026/04/claude-code-source-leak](https://www.infoq.com/news/2026/04/claude-code-source-leak/) — "Anthropic's Claude Code CLI had its full TypeScript source exposed after a source map file was accidentally included in version 2.1.88."
- **arXiv academic analysis**: [arxiv.org/html/2604.14228v1](https://arxiv.org/html/2604.14228v1) — "Dive into Claude Code: The Design Space of Today's and Future AI Agent Systems. This study describes its comprehensive architecture by analyzing the publicly available TypeScript source code v2.1.88."
- **Hacker News mirror**: [github.com/tornikeo/claude-code](https://github.com/tornikeo/claude-code) — "original claude code source in typescript."
- **Medium analysis**: [medium.com/@sathishkraju/everyone-analyzed-claude-codes-features-we-analyzed-its-architecture-d971ca723a68](https://medium.com/@sathishkraju/everyone-analyzed-claude-codes-features-we-analyzed-its-architecture-d971ca723a68) — "Five hundred thousand lines of leaked source code reveal that the moat in AI coding tools is not the model. It is the harness."

The leak is **public, verifiable, and definitive**: Claude Code's source is TypeScript. Not Rust. Not Go. Not C++. TypeScript.

### 2.2 Bun is the runtime (2025-12 onward)

- **Anthropic acquires Bun** (2025-12-03): [anthropic.com/news/anthropic-acquires-bun-as-claude-code-reaches-usd1b-milestone](https://www.anthropic.com/news/anthropic-acquires-bun-as-claude-code-reaches-usd1b-milestone) — "Bun has improved the JavaScript and TypeScript developer experience by optimizing for reliability, speed, and delight."
- **Bun X.com post**: [x.com/bunjavascript/status/2045300183479865602](https://x.com/bunjavascript/status/2045300183479865602) — "Starting in v2.1.113, the Claude Code npm package ships the native binary instead of the JavaScript build."
- **LinkedIn technical analysis**: [linkedin.com/posts/msaad-ch_claude-codes-binary-is-235-mb-on-linux-x64-activity-7434631080483373056-0LXy](https://www.linkedin.com/posts/msaad-ch_claude-codes-binary-is-235-mb-on-linux-x64-activity-7434631080483373056-0LXy) — "Claude Code's binary is 235 MB on Linux-x64. It's a single-file executable built using Bun which packages both..."
- **DIY clone**: [dev.to/agent_69/how-i-built-my-own-claude-code-in-typescript-34n7](https://dev.to/agent_69/how-i-built-my-own-claude-code-in-typescript-34n7) — "It's built in TypeScript, runs on Bun, uses Vercel's AI SDK (Agents, Tools and Loop Control)..."

**The chain is**: TypeScript source → Bun compiler → native Mach-O binary. Anthropic *bought Bun* in December 2025 — this is a strategic bet, not an accident. They picked TypeScript + Bun over Rust.

### 2.3 Codex CLI is the Rust counterpart (confirmed separately)

- **devclass** (2025-06-02): [devclass.com/ai-ml/2025/06/02/nodejs-frustrating-and-inefficient-openai-rewrites-ai-coding-tool-in-rust/1619589](https://www.devclass.com/ai-ml/2025/06/02/nodejs-frustrating-and-inefficient-openai-rewrites-ai-coding-tool-in-rust/1619589) — "OpenAI rewrites AI coding tool in Rust."
- **Hacker News**: [news.ycombinator.com/item?id=44150093](https://news.ycombinator.com/item?id=44150093) — "Codex CLI is going native."
- **Codex Rust Migration Playbook** (2026): [digitalapplied.com/blog/codex-cli-rust-migration-playbook-config-changes-2026](https://www.digitalapplied.com/blog/codex-cli-rust-migration-playbook-config-changes-2026) — "OpenAI's Codex CLI was rewritten from TypeScript to Rust over 2025–2026."

Codex CLI's rewrite is real and confirmed. The "TS → Rust" claim applies to **Codex CLI**, not to **Claude Code**. I conflated the two.

---

## 3. What the corrected picture looks like

Two flagship coding agents, two stacks, both shipping in 2026:

| Product | Source language | Runtime | Binary size | Distribution |
|---|---|---|---|---|
| **Claude Code** (Anthropic) | **TypeScript** (512K LOC) | **Bun** (compiled to native) | 205MB (Mac arm64), 235MB (Linux x64) | npm package + native binary |
| **Codex CLI** (OpenAI) | **Rust** (rewritten 2025-2026 from TS) | Native Rust | ~30-50MB (typical Rust CLI) | npm wrapper + native binary |
| **Gemini CLI** (Google) | TypeScript (Go and Rust components per docs) | Node + native | varies | npm |

**The narrative is no longer "everyone is rewriting to Rust."** The narrative is:

- **OpenAI**: TypeScript → Rust. Strong opinion. Distributed as a single small native binary.
- **Anthropic**: TypeScript stays, but **acquires Bun** and compiles to native. Strategic bet on TypeScript + Bun, not on Rust.
- **Google**: TypeScript + native helpers. Hybrid.

**Both are valid.** Both ship in 2026. The choice is not "Rust is the only right answer." The choice is team-fit, distribution goals, and language ecosystem.

For `speak` specifically:
- If the team is TypeScript-first → TypeScript + Bun is a real, production-proven path.
- If the team is Rust-first → Rust is a real, production-proven path.
- Both can produce a Mac dictation app.

---

## 4. Updated recommendation for `speak`

### 4.1 The language choice is no longer "Rust by default"

**Before this correction**, my recommendation in `SPEAK_PLATFORM_MODEL.md` was: Rust core + uniffi.

**After this correction**: the language choice is a real fork in the road. Three options:

#### Option C1: TypeScript + Bun core (Anthropic's pattern)

- **Pros**: Claude Code validates the stack. Anthropic ships a 200MB native Mac binary. Bun is fast, well-supported, the team at Anthropic bought it. TypeScript has the largest talent pool. The `speak` engine (STT orchestration, LLM cleanup, history, settings) is well-suited to TS — it's not low-level audio processing, it's glue.
- **Cons**: 200MB binary is large (Rust would be ~30MB). Startup time slower than Rust. Hot-path FFI (if we wrap a Rust STT engine) adds overhead. Apple-specific bindings (Swift) require FFI either way.
- **Team fit**: if the team is TS-first, this is the path of least resistance.
- **Cross-platform**: Bun supports Mac, Linux, Windows. Same TypeScript codebase compiles to three native binaries.
- **Right for `speak` if**: the team is TS-first and "fast to v0" matters more than "smallest binary."

#### Option C2: Rust core (OpenAI's Codex CLI pattern)

- **Pros**: Smallest binary (~30MB). Fastest startup. Best latency on hot paths. The most-cited pattern in 2026 (Deno, Tauri, Zed, ripgrep, Ghostty-ish).
- **Cons**: Smaller talent pool. Slower v0 (1-2 days of FFI setup). The `speak` engine is not performance-critical at the core level (STT and LLM are already slow); the latency win is in the shell.
- **Team fit**: if the team is Rust-first, this is the natural choice.
- **Cross-platform**: Rust supports Mac, Linux, Windows. The same Rust crate + three platform shells.
- **Right for `speak` if**: the team is Rust-first or "smallest binary + best latency" matters.

#### Option C3: Swift-only (Sindre Sorhus's pattern)

- **Pros**: Single language. No FFI. Mac-native everything. Smallest binary by far (~10-20MB). Apple's frameworks are first-class (SpeechAnalyzer, Apple Intelligence, Vision).
- **Cons**: Mac-only. Swift on Windows is immature. The Sindre pattern doesn't port.
- **Team fit**: if the product is genuinely Mac-only forever, this is the simplest path.
- **Right for `speak` if**: pick A (Mac-only) over C (portable-ready).

### 4.2 My updated recommendation

**For `speak`, I now recommend C1 (TypeScript + Bun core) as the default, with C2 (Rust core) as a strong alternative if the team prefers Rust.**

The reasoning:

- The user (per memory) has a TypeScript-heavy background (`prompts-prd`, Piclaw, web work). TypeScript + Bun matches the team's existing skills.
- The `speak` engine is glue, not hot-path compute. TS is the right language for glue.
- Bun produces a real native binary. Anthropic ships it. The 200MB size is acceptable for a menubar app.
- Cross-platform (Mac + Windows + Linux) is straightforward: same TypeScript, Bun compiles for each.
- The shell layer still uses platform-native APIs (Swift/Objective-C on Mac, C# on Windows, etc.) via FFI or via separate small native helpers.

If the user prefers Rust, C2 is also right. Both paths are validated by 2026 production apps. The recommendation in the platform model should not be "Rust by default" — it should be "Rust or TypeScript+Bun; pick based on team."

### 4.3 The FFI layer still matters either way

Whichever language the core uses, the shell is platform-native:
- Mac shell: Swift, SwiftUI, AVAudioEngine, SpeechAnalyzer, CGEventTap, NSPasteboard.
- Windows shell: C# or C++, WinUI, WASAPI, RegisterHotKey, OpenClipboard.
- Linux shell: C++ or Rust, GTK or Qt, PulseAudio, evdev, xdotool.

The FFI is what connects them. If the core is TypeScript:
- uniffi is harder (it's Rust → Swift/Kotlin/Python, not TS → Swift).
- For TS → Swift, the natural choice is **a C ABI or a JSON-RPC over stdio**.
- Bun can compile to a native binary that exposes a C ABI via N-API or similar.

If the core is Rust:
- uniffi is the natural choice (Mozilla's project, used in Firefox Sync, Bitwarden).
- The C ABI under uniffi is the stable contract; uniffi is the convenience layer.

So the FFI choice is now:
- **Rust core + uniffi + thin C ABI** (as in the original platform model).
- **TypeScript + Bun core + C ABI or N-API** (alternative if we go C1).

Both are valid. Both have production precedents.

---

## 5. What this means for the other docs

### 5.1 `SPEAK_PLATFORM_MODEL.md`

- §1 (Why the question matters) — unchanged.
- §2 (The three options) — keep the three options, but add a note that the original "Rust core" framing was one of two valid choices. The other is TypeScript + Bun.
- §3 (Recommendation) — change from "Rust core + uniffi" to "Rust core OR TypeScript + Bun core; pick based on team. Default to TypeScript + Bun for the user's profile."
- §4 (Architecture) — the 4-layer model is unchanged. The Engine Layer can be Rust or TypeScript. The IPC Layer depends on the Engine choice.
- §5 (What changes vs current spec) — add: "the language of the engine is a real choice. If TypeScript + Bun, the FFI is C ABI or N-API from Bun. If Rust, the FFI is uniffi."
- §6 (Honest cost) — the cost analysis is the same. The language choice is orthogonal to the 4-layer model.
- §7 (Real question to answer) — the question is now: "What is the team's primary language?" not "Mac or cross-platform?"

### 5.2 `SPEAK_ARCHITECTURE_VERIFICATION.md`

- §1.2 (Rust is the right language) — needs the correction. The verdict is: "Rust is a strong choice but not the only choice. TypeScript + Bun is also strong, validated by Claude Code."
- §1.1 (Rust core + per-platform shell) — confirmed, but the Rust can be replaced with TypeScript + Bun.
- The "Both Anthropic and OpenAI rewrote their coding agents from TypeScript to Rust" line is wrong. Delete it.

### 5.3 `SPEAK_PRODUCT_SPEC.md`

- The product spec says nothing about Rust. It says "Swift, SwiftUI, macOS 26+". That's still correct (the Mac shell is Swift). The engine language is a separate decision.

### 5.4 `OPUS_BUILD_PROMPT.md`

- The brief should now include the language fork as an explicit decision the Opus agent should surface.
- Add: "Before designing the engine, the team must pick: Rust (C2) or TypeScript + Bun (C1)? Both are validated by 2026 production apps. The choice depends on team fit."

### 5.5 `SPEAK_PRODUCT_SPEC.md` §6 (Architecture)

- §6.1 Module layout currently says "SpeakCore/Framework: headless dictation engine". Add: "engine is in Rust or TypeScript + Bun; pick based on team."
- §6.2 Key design decisions: add the language fork.

---

## 6. The honest summary

I was wrong. Claude Code is not Rust. Claude Code is TypeScript, compiled with Bun into a native binary, validated by the 2026-03-31 source leak, and Anthropic's December 2025 acquisition of Bun is a strategic bet on TypeScript + Bun as the production stack for AI agents.

The correction changes the narrative from "TS→Rust is the inevitable trend" to "TypeScript + Bun and Rust are both viable in 2026." The recommendation for `speak` should be updated to surface the language choice (C1: TS+Bun, C2: Rust) as a real fork based on team fit, not as a default to Rust.

The user (you) was right to push back. The verification doc and platform model now need to be updated to reflect the correction. I will do that as the next step if you want.

---

## 7. Sources

### Claude Code is TypeScript (definitive)
- [The Pragmatic Engineer: How Claude Code is built](https://newsletter.pragmaticengineer.com/p/how-claude-code-is-built) — Sep 2025 exclusive
- [The leak: 512K lines of TypeScript](https://dev.to/stevengonsalvez/claude-code-source-code-leaked-512k-lines-of-typescript-and-what-actually-matters-4k06) — dev.to, Apr 2026
- [InfoQ: Claude Code source leak](https://www.infoq.com/news/2026/04/claude-code-source-leak/) — Apr 2026
- [arXiv: Dive into Claude Code architecture (TypeScript source)](https://arxiv.org/html/2604.14228v1) — academic analysis
- [github.com/tornikeo/claude-code](https://github.com/tornikeo/claude-code) — TypeScript source mirror
- [Medium: Everyone analyzed features, we analyzed architecture](https://medium.com/@sathishkraju/everyone-analyzed-claude-codes-features-we-analyzed-its-architecture-d971ca723a68) — Mar 2026

### Bun is the runtime
- [Anthropic acquires Bun (Dec 2025)](https://www.anthropic.com/news/anthropic-acquires-bun-as-claude-code-reaches-usd1b-milestone) — definitive
- [Bun X.com: v2.1.113 ships native binary](https://x.com/bunjavascript/status/2045300183479865602)
- [LinkedIn: Decompiling Claude Code's binary (235MB on Linux)](https://www.linkedin.com/posts/msaad-ch_claude-codes-binary-is-235-mb-on-linux-x64-activity-7434631080483373056-0LXy)
- [DIY Claude Code clone in TypeScript + Bun](https://dev.to/agent_69/how-i-built-my-own-claude-code-in-typescript-34n7)

### Codex CLI is Rust (still confirmed)
- [devclass: OpenAI rewrites AI coding tool in Rust](https://www.devclass.com/ai-ml/2025/06/02/nodejs-frustrating-and-inefficient-openai-rewrites-ai-coding-tool-in-rust/1619589) — Jun 2025
- [HN: Codex CLI is going native](https://news.ycombinator.com/item?id=44150093)
- [Codex CLI Rust Migration Playbook (2026)](https://www.digitalapplied.com/blog/codex-cli-rust-migration-playbook-config-changes-2026)
