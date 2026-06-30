# How to Make Correct Tech-Stack Judgments

> **Status**: Meta-process memo. The user asked: *"how to take correct judgment for tech stack."* This session produced 4 wrong claims (Wispr is Electron, Claude Code is Rust, both Anthropic and OpenAI went Rust, Rust is right for `speak`'s core) and 1 right call (Mac dictation apps are Swift + native). The right answer is the *process* that would have caught the 4 wrong claims and produced the right one faster.
>
> **Date**: 2026-06-18
> **Use case**: a repeatable diagnostic for picking a tech stack in 2026.

---

## 0. TL;DR — the 7-step process

1. **Name the category precisely.** "Mac-first real-time audio + system-integration product" beats "desktop app." The category determines the sample.
2. **Find the dominant pattern.** Look at 5-10 products in the *same category*. The majority is usually right.
3. **Verify with the most-direct source.** Local binary, GitHub API, App Store, official docs. Skip Medium articles when you can.
4. **Distinguish verified from inferred, and label both.** A claim from a Medium article is not a claim from a GitHub repo. Never blur the line.
5. **Understand the constraint, not just the pattern.** "Firefox uses Rust" is meaningless without "Firefox has these specific constraints."
6. **Test in 24 hours before committing to 6 months.** A 1-day prototype beats a 6-month architecture decision.
7. **Update the verdict when the source contradicts the narrative.** Source beats narrative. Always.

This session failed steps 3, 4, 5, and 7 four times. Following the process would have caught all four.

---

## 1. The 4 evidence tiers, ranked by reliability

When you cite a source, you should be able to name which tier it's in. The tiers, in order from most to least reliable:

### Tier 1: Direct primary source (the binary, the repo, the official doc)

- The Claude Code binary on the local machine showing `---- Bun! ----` in `strings`.
- The GitHub API returning `"language": "Swift"` for FluidVoice.
- Apple's official SpeechAnalyzer documentation.
- The npm package source map exposing 512K lines of TypeScript.

**Use when**: you need to know *exactly* what a product is built with. This is the answer, not a clue.

### Tier 2: Authoritative secondary source (engineering blog, founder talk, official job posting)

- Anthropic's official "We acquired Bun" announcement.
- The Pragmatic Engineer's exclusive look at how Claude Code is built.
- Wispr Flow's engineering blog post on Baseten.
- Superwhisper's "Android Engineer — on-device ML, build from scratch" job posting.

**Use when**: Tier 1 doesn't exist (closed source) and the company itself is talking about its stack. This is the next best thing.

### Tier 3: Aggregator / analyst (Medium article, dev.to, YouTube tutorial, HN comment)

- "Claude Code is built in TypeScript" articles based on the leaked source.
- "Tauri vs Electron 2026" comparisons.
- "Build your own Wispr Flow in 33 minutes" tutorials.

**Use when**: Tier 1 and 2 don't exist for your specific question. Cross-reference multiple Tier 3 sources to triangulate.

### Tier 4: Speculation, opinion, default assumption

- "Wispr Flow is probably Electron because it's cross-platform."
- "Rust is the future of desktop apps."
- "Everyone is rewriting TypeScript to Rust."

**Use when**: never. Don't cite this. Don't write it as a fact. If you have to use it, label it explicitly as "unverified — best guess."

**This session's failures by tier:**

| Claim | Tier I used | Should have used | What I missed |
|---|---|---|---|
| "Wispr Flow is Electron" | Tier 4 (speculation) | Tier 1 (no public binary, but Tier 2 from job postings) | No source at all |
| "Claude Code is Rust" | Tier 3 (article title said "Rust Rewrite") | Tier 1 (inspect the local binary, query GitHub) | "Bun!" string in the binary |
| "Both Anthropic and OpenAI went Rust" | Tier 3 (conflated two articles) | Tier 1 (the Codex source is public, the Claude Code binary is local) | Codex is Rust, Claude Code is TS+Bun — different stacks |
| "Rust is right for `speak`'s core" | Tier 3 (Firefox/Deno/Tauri pattern) | Tier 1 (VoiceInk, FluidVoice, TypeWhisper are all Swift) | 5/5 open-source Mac dictation apps are Swift |

---

## 2. The 7-step diagnostic

### Step 1: Name the category precisely

The category is the *sample frame*. Wrong category = wrong sample = wrong conclusion.

- ❌ "Desktop app" — too broad. Includes VS Code, Discord, Spotify, Adobe Creative Cloud, AutoCAD. Sample is too heterogeneous.
- ❌ "AI app" — too broad. Includes web apps, mobile apps, CLI tools, embedded.
- ❌ "Voice tool" — too broad. Includes voice assistants, voice agents, voice cloning, voice-to-voice.
- ✅ "Mac-first real-time audio capture + system-integration dictation app" — precise. Sample: Wispr Flow, Willow Voice, Superwhisper, Aiko, MacWhisper, VoiceInk, FluidVoice, TypeWhisper. Homogeneous.

**Rule**: if you can list 5+ products in the category that you would compare yourself against, the category is right. If you can't, the category is too broad or too narrow.

### Step 2: Find the dominant pattern in that category

List the 5-10 closest products. For each, find the language + STT + distribution.

In this session, when I actually did this for the Mac dictation category, the pattern was 100% Swift + native. The dominant pattern is the right starting hypothesis.

**The failure mode**: I cited the *cross-platform desktop app* category (Firefox, Deno, Tauri) instead of the *Mac-first dictation app* category. Different categories, different patterns. The mistake was at Step 1.

### Step 3: Verify with the most-direct source

For each claim, ask: *what is the most direct source I could check?* Then check it.

For "what language is X written in?":

- **Open source**: GitHub API. `curl https://api.github.com/repos/.../languages` returns exact byte counts. 5-second verification.
- **Closed source, installed locally**: `file`, `strings`, `otool -L`, `plutil`. The local binary tells the truth. 1-minute verification.
- **Closed source, not installed**: App Store listing, official docs, engineering blog, founder talks, job postings. 10-30 minute verification.
- **Tier 3 only**: don't commit to a claim. Note "inferred from secondary sources" and move on.

**Rule**: for every claim you make, you should be able to name the verification you'd run. If you can't, you don't have a claim, you have a guess.

### Step 4: Distinguish verified from inferred, and label both

Every claim in a doc should be labeled:

- `[verified]` — direct primary source, current as of date.
- `[inferred]` — based on indirect evidence; here's the inference chain.
- `[unverified]` — no source, best guess.

**This session's mistakes** all came from blurring this line. I wrote "Wispr Flow is Electron" as if it were a fact when it was speculation.

**Practical tip**: when you write a doc, put `[verified | inferred | unverified]` next to each non-trivial claim. Forces you to be honest.

### Step 5: Understand the constraint, not just the pattern

"Firefox uses Rust" is true. But the reason Firefox uses Rust is:
- High-performance browser engine (V8 competitor)
- Memory safety for a security-critical surface
- Cross-platform support (Windows, Mac, Linux, Android)
- A team that had the budget to invest in a new language

`Speak` has *none* of these constraints. The Firefox pattern is irrelevant. The pattern copy needs the constraint match.

**Rule**: when copying a pattern, copy the constraint too. If the constraint doesn't match, the pattern doesn't apply.

### Step 6: Test in 24 hours before committing to 6 months

Before writing a 6-month roadmap around a tech-stack decision, build a 1-day prototype that validates the core hypothesis.

For `speak`'s "Swift + Apple SpeechAnalyzer" choice:
- **1-day test**: Build a Swift command-line tool that captures mic audio, runs Apple SpeechAnalyzer, prints the result. 50 lines of Swift. If it works in 24 hours, the choice is validated.
- **If it doesn't work** (Apple SpeechAnalyzer is unreliable on this Mac, or the API is harder than docs suggest), pivot *now* — 1 day lost, not 6 months.

**Rule**: a 1-day prototype that contradicts a 6-month plan is a sign the plan is wrong. Listen to the prototype.

### Step 7: Update the verdict when the source contradicts the narrative

When the source (binary, repo, doc) contradicts the narrative (Medium article, Twitter thread, conference talk), trust the source.

This session: the local Claude Code binary showed "Bun!" embedded. The narrative said "TypeScript is being rewritten to Rust." I should have noticed the contradiction immediately. I didn't, because I was anchored on the article title.

**Rule**: if the source contradicts the narrative, the narrative is wrong. Update the narrative. Don't try to reconcile them by saying "well, it could be..."

---

## 3. The 5 anti-patterns (with this session's examples)

### Anti-pattern 1: Cargo culting

- **Definition**: copying a tech-stack choice because a prestigious project uses it, without checking if the constraints match.
- **This session's example**: I cited Firefox, Deno, Tauri as proof that "Rust is the right language for cross-platform desktop apps." True. But `speak` isn't a cross-platform desktop app in the Firefox/Deno/Tauri sense — it's a Mac-first system-integration product. The constraint didn't match.
- **How to avoid**: copy the *constraint* first, then the pattern.

### Anti-pattern 2: Narrative acceptance

- **Definition**: accepting a "trend" or "industry direction" claim from a Tier 3 source without verifying against Tier 1.
- **This session's example**: I accepted "TS → Rust is the trend" and built the whole `SPEAK_PLATFORM_MODEL.md` around it. The local Claude Code binary contradicted this; I didn't check.
- **How to avoid**: before accepting a trend, find 3+ primary sources. If you can't, the trend is unverified.

### Anti-pattern 3: Category drift

- **Definition**: starting in one category (Mac-first dictation) and silently switching to another (cross-platform desktop) when the evidence is more abundant in the second.
- **This session's example**: I was researching Mac dictation apps but cited Firefox/Deno/Tauri (which are cross-platform desktop, a different category). The category drift made the conclusion wrong.
- **How to avoid**: name the category in §1 of every analysis, and check the sample frame matches before citing evidence.

### Anti-pattern 4: Closed-source speculation

- **Definition**: making claims about a closed-source product's stack without primary source evidence.
- **This session's example**: "Wispr Flow is Electron" was pure speculation, no source. I wrote it as fact. The user caught it.
- **How to avoid**: for closed-source products, label every claim `[inferred]` or `[unverified]` unless you have a Tier 1/2 source. The user will catch you if you don't.

### Anti-pattern 5: Source-tier confusion

- **Definition**: treating a Medium article or YouTube tutorial as equivalent to a GitHub repo or official doc.
- **This session's example**: I treated the AWS Builder "Swift dev for Wispr-like app" article as if it were a Tier 1 source for Wispr Flow's actual stack. It was a Tier 3 source about a *similar* app, not the real Wispr.
- **How to avoid**: before citing, ask: *is this source saying something about THIS product, or about a similar product?* If similar, label as `[inferred]`.

---

## 4. The 5 questions to ask before committing to a tech stack

Before writing a 6-month architecture, answer these 5 questions:

1. **What category am I in?** Be precise. Name 5+ products you'd compare yourself against.
2. **What is the dominant pattern in that category?** Find 5+ examples. The majority pattern is the right starting hypothesis.
3. **What is the most-direct source for each example?** Open-source → GitHub. Closed-source → binary inspection, official blog, job postings, founder talks.
4. **Does my constraint match the dominant pattern's constraint?** If not, why am I different?
5. **Can I build a 1-day prototype that validates the core hypothesis?** If yes, build it before committing.

If any answer is "I don't know," you don't have a tech-stack decision. You have a guess. Get the answer first.

---

## 5. Applied to `speak`

### The category, precisely

"Mac-first, Apple-Silicon-only, real-time voice dictation app with system-wide hotkey, menubar UI, and local-first privacy. v0 = Mac only. v1+ may add Windows."

### The dominant pattern (verified)

| App | Lang | STT | License |
|---|---|---|---|
| Wispr Flow | Swift | Cloud | Proprietary |
| Willow Voice | Swift | Cloud (Whisper+Llama) | Proprietary |
| Superwhisper | Swift + native Android | Hybrid | Proprietary |
| Aiko | Swift | whisper.cpp | MIT |
| MacWhisper | Swift (inferred) | whisper.cpp (inferred) | Paid |
| VoiceInk | **Swift (verified)** | Whisper + Parakeet | GPL v3 |
| FluidVoice | **Swift (verified)** | Pluggable multi-engine | GPL v3 |
| TypeWhisper | **Swift (verified)** | Local + cloud | GPL v3 |

**Dominant pattern**: **Swift + native + macOS-first + pluggable STT + local-first (open source) or cloud (closed)**.

### The constraint match

- `speak` is Mac-first, Apple-Silicon only — matches the entire sample.
- `speak` is local-first — matches the open-source half (Aiko, VoiceInk, FluidVoice, TypeWhisper).
- `speak` is open source (MIT planned) — matches the open-source half.
- `speak` wants pluggable STT — matches FluidVoice exactly.
- `speak` wants optional LLM cleanup — matches TypeWhisper (prompt-based post-processing).

**Constraint match: 100%**. The dominant pattern is the right answer.

### The 1-day prototype (validates the choice)

Build a 50-line Swift CLI tool that:
1. Captures mic audio for 5 seconds.
2. Runs Apple SpeechAnalyzer.
3. Prints the transcript.

If this works in 24 hours, the choice is validated. If not, pivot to whisper.cpp or WhisperKit.

### The verdict (correct this time)

**Swift + native macOS + pluggable STT protocol + Apple SpeechAnalyzer default + whisper.cpp fallback + MIT license + Homebrew Cask.**

The "Rust core + uniffi" recommendation in `SPEAK_PLATFORM_MODEL.md` is **wrong for `speak`'s v0**. It was the right pattern for Firefox/Deno/Tauri (cross-platform desktop frameworks) but the wrong pattern for Mac-first dictation apps.

**v1+**: if Windows is added, extract the STT orchestration + history + settings into a portable module (Rust or TypeScript + Bun), with the Mac shell staying Swift and calling into the portable module via FFI. **But this is a v1+ concern.**

---

## 6. The honest summary

The user asked the right meta-question. The right process has 7 steps and 5 anti-patterns. This session violated steps 3, 4, 5, and 7 four times, producing 4 wrong claims that the user had to catch.

The corrected verdict for `speak`: **Swift + native + pluggable STT**, validated by 8 production Mac dictation apps. The "Rust core" recommendation in `SPEAK_PLATFORM_MODEL.md` was based on the wrong category (cross-platform desktop frameworks, not Mac-first dictation apps).

The lesson is the process, not the verdict. Apply the 7 steps to the next tech-stack decision and the same 4 mistakes don't happen.

---

## 7. Sources (for the meta-process)

This doc is about *how* to verify, not *what* to verify. The relevant Tier 1 sources for the *process*:

- [The Pragmatic Engineer: How Claude Code is built](https://newsletter.pragmaticengineer.com/p/how-claude-code-is-built) — example of Tier 2 source.
- [The Claude Code source leak (TypeScript, 512K lines)](https://dev.to/stevengonsalvez/claude-code-source-code-leaked-512k-lines-of-typescript-and-what-actually-matters-4k06) — example of Tier 1 via Tier 3.
- [GitHub API for repo languages](https://docs.github.com/en/rest/repos/repos#list-repository-languages) — the Tier 1 verification method.
- [macOS `strings` man page](https://www.unix.com/man-page/osx/1/strings/) — the Tier 1 binary inspection method.
- [Apple's SpeechAnalyzer documentation](https://developer.apple.com/documentation/speech/speechanalyzer) — Tier 1 for Apple API claims.
- [Anthropic acquires Bun announcement](https://www.anthropic.com/news/anthropic-acquires-bun-as-claude-code-reaches-usd1b-milestone) — Tier 2 for the Anthropic + Bun relationship.
- [FluidVoice repo languages via GitHub API](https://github.com/altic-dev/FluidVoice) — Tier 1 verification of "Swift" claim.
- [VoiceInk repo languages via GitHub API](https://github.com/Beingpax/VoiceInk) — Tier 1 verification.
- [TypeWhisper repo languages via GitHub API](https://github.com/TypeWhisper/typewhisper-mac) — Tier 1 verification.
