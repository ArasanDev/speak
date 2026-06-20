# Opus Build Prompt — `speak` Voice Dictation (macOS)

> **Purpose**: This file is a self-contained work order for Claude Code running the Opus model. Copy it into a fresh Claude Code session (Opus selected, full permissions, working directory `/Users/tamil/Developers/deepvoice`) and run it. The expected output is a set of architecture, API, roadmap, validation, and risk files in the same directory, with a level of detail and rigor that lets a senior engineer start coding **tomorrow**.
>
> **Date**: 2026-06-18
> **Model target**: Opus 4.5+ (or current Anthropic flagship)
> **Harness**: Claude Code CLI
> **Working dir**: `/Users/tamil/Developers/deepvoice`

---

## 0. Mission (read this first)

You are the lead architect and PM for **`speak`**, a macOS-native, local-first, free, open-source voice dictation app competing with Wispr Flow. Your job is to produce **five production-grade documents** that together constitute a complete, executable build brief:

1. **Architecture** (`SPEAK_ARCHITECTURE.md`) — module layout, data flow, type definitions, concurrency, error model, state machines, integration points, performance budgets, test strategy, build & distribution.
2. **Public API surface** (`SPEAK_API.md`) — public protocols, types, module exports, usage examples, versioning policy.
3. **Build roadmap** (`SPEAK_ROADMAP.md`) — phased tasks ordered by dependency (not date), with effort estimates and "done when" criteria. The 2-week v0 plan is the critical path.
4. **Validation plan** (`SPEAK_VALIDATION.md`) — unit/integration/manual test scenarios, dogfooding protocol, performance benchmarks, edge cases, cross-app compatibility matrix, permission flow tests, failure mode tests.
5. **Risk register** (`SPEAK_RISKS.md`) — top 10-15 risks with likelihood, impact, mitigation, decision criteria, escape hatches.

**Quality bar.** If a senior Swift engineer (10+ years) cannot start coding from your architecture + API docs by end of day, the deliverable is incomplete. If a senior PM cannot sequence a launch from the roadmap, the deliverable is incomplete. If a senior QA cannot write a test plan from the validation doc, the deliverable is incomplete. Be opinionated. Be concrete. No TODOs. No "TBD". No "we'll figure that out later."

**Style bar.** Cite primary sources for every technical claim. Inline link URLs. State the date you accessed each source. Distinguish verified facts from inference. Use the `verified | inferred` convention.

---

## 1. Context — what already exists

The following files are in your working directory. **Read all of them before designing anything.** They contain the product spec, the competitive landscape, the prior ideation, and the user's GTM constraints.

| File | Purpose | Read it for |
|---|---|---|
| `IDEATION.md` | The 4 directions for `deepvoice` (an adjacent product) | High-level product thinking, market-gap framing |
| `CATEGORY_LANDSCAPE.md` | 2026 voice-coding category sweep | Bucket 1 (voice dictation) and Bucket 3 (IDE voice modes) — direct context |
| `SPEAK_PRODUCT_SPEC.md` | The `speak` product spec v0.1 | **Primary product brief.** Read this end-to-end. |

Key product decisions already made (do not re-litigate unless you find a primary-source reason):

- **Name (working)**: `speak`. MIT licensed. Free, open source.
- **GTM wedge**: MacBook, Apple Silicon only, macOS 26+. No Intel Mac in v0.
- **Primary STT**: Apple `SpeechAnalyzer` (macOS 26+, on-device, free).
- **Fallback STT**: `WhisperKit` (Argmax, open source) for v0.1; `whisper.cpp` for Intel Mac in v1.
- **Hotkey**: double-tap Fn = start, single-tap Fn = stop & paste. Customizable from v0.
- **Paste**: `NSPasteboard.general.setString(...)` + simulated `Cmd+V` keystroke. **Do not** read the pasteboard (macOS 26.4 paste protection).
- **Post-processing**: optional local LLM (Ollama MLX) in v0.1; Apple Intelligence Writing Tools in v1.
- **Distribution**: Homebrew Cask + `.dmg` in v0; Mac App Store in v1+.

Hard constraints:

- **100% local by default**. No cloud audio. No telemetry to a server. No accounts. No login.
- **Three permissions**: Microphone, Accessibility, Input Monitoring. Onboarding must explain all three with deep-links to System Settings.
- **Swift 5.9+**, **SwiftUI**, **macOS 26+ deployment target**, **Apple Silicon only** in v0.
- **No third-party dependencies for v0**. Use Apple frameworks only.
- **v0 ships in 2 weeks** (14 working days). The roadmap must be doable by a single senior engineer in that window.

---

## 2. What to produce — the five deliverables

### 2.1 `SPEAK_ARCHITECTURE.md`

Target: 500-800 lines, no fluff. Contains:

- **System context** (C4 Level 1) — `speak` in its environment: macOS, Apple frameworks, user, focused app.
- **Container diagram** (C4 Level 2) — the three deployable units: `Speak.app` (SwiftUI menubar), `SpeakCore.framework` (headless engine), `SpeakCLI` (shell shim).
- **Module layout** — full directory tree with one-line per-file purpose. Align with the `SpeakCore` framework split: `AudioCapture`, `HotkeyMonitor`, `SpeechTranscriber`, `PasteboardWriter`, `PermissionManager`, `HistoryStore`, `LLMCleanup` (v0.1+), `SettingsStore`, `Logging`.
- **Component diagram** (C4 Level 3) — internal `SpeakCore` data flow: Audio → Transcriber → (optional LLM) → Pasteboard → Cmd+V. State machine for capture session: `idle → listening → processing → done | error`.
- **Concurrency model** — actors, `MainActor` boundaries, async/await, structured concurrency, cancellation. Specifically: which class runs on which actor; how partial results stream; how the hotkey monitor interacts with the transcriber.
- **Key types** — full Swift signatures for: `CaptureSession`, `TranscriptionResult`, `HotkeyEvent`, `PasteEvent`, `PermissionState`, `Settings`, `HistoryEntry`, `LLMCleanupRequest`/`LLMCleanupResult`. Use Swift syntax verbatim, not pseudocode.
- **Error model** — `SpeakError` enum with all cases and their recovery paths.
- **State machines** — for `PermissionState`, `CaptureSession.State`, `Transcriber.State`, `HistoryStore.State`. Show transitions as a table or ASCII diagram.
- **Apple framework integration map** — every Apple framework used, with the specific class/protocol and the role it plays. Must include: `AVFoundation` (AVAudioEngine), `ApplicationServices` (CGEventTap, CGEvent), `AppKit` (NSPasteboard, NSStatusItem, NSWorkspace), `Speech` (SpeechAnalyzer, SpeechTranscriber, AudioInput), `SwiftUI` (MenuBarExtra, Settings), `OSLog` (logging), `Security` (hardened runtime, notarization).
- **Performance budgets** — for each hot path: target latency in ms (p50 / p95). Examples: hotkey-to-listen < 50ms, partial-to-UI < 100ms, stop-to-paste < 500ms, total round-trip < 2s for 30s of speech.
- **Test strategy** — unit (XCTest, in `SpeakCore`), UI (XCUITest, in `SpeakApp`), integration (real macOS with mic), dogfooding (real workflows).
- **Build & distribution** — Xcode project structure, scheme + target layout, code signing, notarization, `.dmg` packaging, Homebrew Cask formula (show a complete Cask file), Gatekeeper, sandboxing decision (recommend non-sandboxed for v0, explain why).
- **Cross-cutting concerns** — logging, error reporting, settings persistence (UserDefaults vs SQLite), update mechanism (Sparkle? Homebrew only? both?).
- **Anti-patterns to avoid** — explicit list: no global mutable state, no third-party deps in v0, no `print` for logging, no blocking the main thread, no force-unwraps, no `try!` outside of test code, no captures of `self` in long-lived closures without `[weak self]`.

### 2.2 `SPEAK_API.md`

Target: 300-500 lines. The public surface that other modules (and future external consumers, e.g. a future CLI flag) depend on. Contains:

- **Module exports** — every public type, protocol, function in `SpeakCore` and `SpeakCLI`.
- **Public protocols** — `Transcribing`, `Pasting`, `HotkeyMonitoring`, `HistoryStoring`, `PermissionChecking`, `LLMCleaning`. Each with method signatures, default implementations where appropriate, and rationale.
- **Public value types** — every `struct` and `enum` exposed across module boundaries.
- **Public error type** — `SpeakError` with all cases, messages, and recovery suggestions.
- **Configuration** — `Settings` struct: all fields, defaults, validation rules.
- **Usage examples** — 3-5 short code snippets showing how to: (a) start a capture session, (b) wire a custom hotkey, (c) plug in a custom LLM cleaner, (d) read history, (e) run the CLI.
- **Versioning policy** — semver, what counts as breaking, deprecation rules.
- **Stability tiers** — `@_spi(Experimental)` / `@_spi(Stable)` / public annotations, what's stable in v0, what's experimental.

### 2.3 `SPEAK_ROADMAP.md`

Target: 400-600 lines. The critical deliverable. Contains:

- **Phase 0 (Day 0)**: repo setup — `git init`, `Package.swift` or Xcode project, directory layout, CI (GitHub Actions for build + lint), `README.md`, `LICENSE` (MIT), `CONTRIBUTING.md`, `.gitignore`, `.swift-version`, `Makefile` or `justfile` for common tasks. **Done when**: `make build` produces a runnable `.app` from a clean clone.
- **Phase 1 (Days 1-2)**: menubar scaffold + `SpeakCore` framework skeleton + AudioCapture (AVAudioEngine) without STT. **Done when**: app shows in menubar, clicking it starts/stops a recording that writes raw PCM to disk.
- **Phase 2 (Days 3-4)**: SpeechAnalyzer integration + partial-result streaming. **Done when**: spoken audio produces partial + final transcripts in console.
- **Phase 3 (Days 5-6)**: HotkeyMonitor (CGEventTap) + double-tap Fn + single-tap Fn. **Done when**: Fn keys start/stop capture.
- **Phase 4 (Day 7)**: PasteboardWriter (NSPasteboard + Cmd+V simulation) + state machine wiring. **Done when**: text pastes into a focused text field in 3 different apps (TextEdit, Slack, Terminal).
- **Phase 5 (Day 8)**: PermissionManager + 3-permission onboarding flow with deep-links. **Done when**: a fresh user grants all 3 permissions in < 90 seconds.
- **Phase 6 (Days 9-10)**: HistoryStore (SQLite) + SettingsStore (UserDefaults) + MenubarExtra UI polish (idle/listening/processing states). **Done when**: settings persist across launches, history is searchable, menubar reflects state.
- **Phase 7 (Day 11)**: build + notarize + .dmg + Homebrew Cask. **Done when**: `brew install --cask speak` works on a clean machine.
- **Phase 8 (Days 12-14)**: dogfood + top-3 issues + README/demo GIF. **Done when**: 4 hours of real use, 3 high-priority bugs fixed, public repo with screenshots.
- **v0.1 (week 3-4)**: Ollama integration, snippets, more languages.
- **v1 (month 2)**: Apple Intelligence, WhisperKit fallback, Intel Mac support, cloud opt-in.
- **v2 (month 3-4)**: code-aware mode, iOS sync, team plan.

For each task: assign effort (S / M / L / XL), list dependencies, state the "done when" criterion in testable form, and call out the critical path. End the doc with a "first 48 hours" subsection that lists the first 8 tasks in dependency order so a new contributor can start on Monday morning.

### 2.4 `SPEAK_VALIDATION.md`

Target: 300-500 lines. Contains:

- **Unit test categories** — by module: AudioCapture (sample rate, format, callback timing), HotkeyMonitor (single-tap, double-tap, modifier combos, external keyboard), SpeechTranscriber (mocked, contract tests), PasteboardWriter (mocked), PermissionManager (state machine), HistoryStore (CRUD, search), SettingsStore (persistence, validation), LLMCleanup (mocked, prompt contract).
- **Integration test scenarios** — end-to-end with real audio: dictation in 5 categories of apps (native macOS, Electron, browser, IDE, Terminal), multi-language round-trip, long-session (5 min continuous), background app behavior.
- **Manual dogfooding protocol** — 4 hours of real use across: Slack, code comments, terminal, email, search bar. Log: latency, false triggers, missed words, permission edge cases. Daily review for 7 days.
- **Performance benchmarks** — `swift-benchmark` or XCTest performance tests for: first-partial-result latency, end-to-end dictation latency for 10s/30s/60s speech, CPU usage during capture, memory footprint, battery drain over 1 hour.
- **Edge cases** — empty audio, very short utterance (< 1s), very long utterance (> 5 min), background noise, multiple speakers, accented English, network offline (must work), no microphone (permission denied), revoked permission mid-session.
- **Cross-app compatibility matrix** — test in: TextEdit, Notes, Mail, Messages, Safari, Chrome, VS Code, Cursor, Terminal, iTerm2, Slack, Discord, Zoom chat, Notion, Linear, GitHub web. For each: does paste work? does hotkey conflict? does Cmd+V simulation trigger macOS 26.4 prompt?
- **Permission flow tests** — clean install, all denied, all granted, partial, revoked during use, on macOS upgrade (Tahoe → next).
- **Failure mode tests** — STT engine crash, microphone disconnected, LLM server down, pasteboard busy, accessibility permission revoked, hotkey conflict with another app.
- **Acceptance criteria for v0 ship** — the binary checklist of "is v0 ready for the Homebrew Cask tap"?

### 2.5 `SPEAK_RISKS.md`

Target: 200-400 lines. Contains:

- A table of 10-15 risks with columns: `Risk | Likelihood (Low/Med/High) | Impact (Low/Med/High) | Mitigation | Decision criteria | Escape hatch | Owner`.
- Cover at minimum: SpeechAnalyzer quality in noise, Fn-key OS conflict, macOS 26.4 paste protection, 3-permission onboarding dropoff, LLM cleanup latency, Apple-Silicon-only GTM limit, Apple closing SpeechAnalyzer access, Wispr Flow copying the model, Ollama install friction, App Store sandboxing, code signing cost, distribution channel (Homebrew-only is a discovery problem), single-maintainer bus factor, microphone hardware quality variance.
- Each risk should have an explicit "if this happens, we do X" decision rule. No hand-waving.

---

## 3. Process — how to do the work

Follow these steps in order. Update your plan as you go.

1. **Read all three input files** (`IDEATION.md`, `CATEGORY_LANDSCAPE.md`, `SPEAK_PRODUCT_SPEC.md`) end-to-end. Don't skim. Use `read_file`.
2. **Verify the technical claims** that the spec depends on. For each of the following, do a primary-source check via `web_search` (cite the URL and date):
   - Apple SpeechAnalyzer API surface, macOS 26+ requirement, on-device guarantee.
   - Apple `NSPasteboard` + `CGEvent` keystroke simulation behavior under macOS 26.4 paste protection.
   - `CGEventTap` permissions (Accessibility, Input Monitoring) on macOS 26.
   - `WhisperKit` current version, license, Apple Silicon support.
   - `Ollama` MLX backend availability and model list.
   - Apple Intelligence Writing Tools API surface and Apple Silicon requirement.
   - Homebrew Cask submission process and review SLA.
3. **Design the architecture** first. Module layout → data flow → state machines → types → concurrency → error model → integration map. Write `SPEAK_ARCHITECTURE.md`.
4. **Derive the public API** from the architecture. What's exposed across module boundaries? What's the public protocol set? Write `SPEAK_API.md`.
5. **Build the roadmap** from the API + architecture. Order by dependency. The critical path is Phase 0-8 (v0). Write `SPEAK_ROADMAP.md`.
6. **Write the validation plan** from the roadmap. Every roadmap task gets test coverage. Add cross-app + permission + failure-mode tests on top. Write `SPEAK_VALIDATION.md`.
7. **Write the risk register** by stress-testing your own design. What's brittle? What depends on Apple not changing something? What depends on the user doing something? Write `SPEAK_RISKS.md`.
8. **Cross-link all five docs** so a reader can navigate from roadmap task → architecture module → API surface → test → risk.
9. **Self-check**. Run the §7 self-check questions. If any answer is "no" or "sort of", fix the docs and re-check.
10. **Commit** each doc as a separate file in `/Users/tamil/Developers/deepvoice/`.

---

## 4. Constraints (hard rules)

- **No MVP**. The architecture must be the real system shape, not a stripped-down version. If a section needs more space, give it more space.
- **Primary sources only** for technical claims. Every Apple API, every framework version, every library — link the docs. If you can't find a primary source, say so explicitly with `verified: not-found | inferred: ...` and explain your reasoning.
- **No third-party dependencies in v0**. Apple frameworks only. If a third-party lib would help (e.g. `WhisperKit`, `Ollama` client), note it for v0.1+.
- **No "TBD" / "TODO" / "figure out later"**. Every section must be complete. If you genuinely don't know, state the question explicitly and your best guess.
- **No `print` debugging**. Use `OSLog` from day one. Define log categories in the architecture doc.
- **No force-unwraps in production code**. Use `guard let` / `if let` / `throws`. Exceptions only in tests.
- **No cloud by default**. Local-first is the rule. Cloud is the opt-in escape hatch.
- **No accounts, no login, no telemetry** in v0. The user pays nothing, registers nothing, leaks nothing.
- **Be opinionated**. Pick a path. State the tradeoff. Move on. The user wants a build brief, not a survey of options.
- **Cite dates** for every source. State when you accessed it. (Use the `accessed: YYYY-MM-DD` convention.)

---

## 5. Quality bar

Before declaring done, every doc must pass these checks:

- **Architecture**: a senior Swift engineer can start coding the first 5 roadmap tasks without asking a single clarifying question.
- **API**: a senior engineer can write a `SpeakCLI` command against the public API using only the API doc and Swift autocomplete.
- **Roadmap**: a senior PM can sequence the v0 launch and the v0.1/v1/v2 follow-ons from the doc alone.
- **Validation**: a senior QA can write an XCTest target from the validation doc without ambiguity.
- **Risks**: every risk has a decision rule. "If X happens, we do Y." No vague "we'll monitor" or "we'll see."

Cross-cutting checks:

- Every claim has a primary source link with date.
- Every module has a single sentence for "why this module exists."
- Every type has a Swift signature, not pseudocode.
- Every state machine has a transition table.
- Every performance budget has a number (ms / MB / % CPU).
- Every "done when" is testable (binary pass/fail).

---

## 6. Output format

- All five files in `/Users/tamil/Developers/deepvoice/`.
- File names exactly: `SPEAK_ARCHITECTURE.md`, `SPEAK_API.md`, `SPEAK_ROADMAP.md`, `SPEAK_VALIDATION.md`, `SPEAK_RISKS.md`.
- Each file starts with front matter:
  ```
  # <Title>
  > Status: Draft v0.1 · Owner: Opus (this session) · Date: 2026-06-18
  > Depends on: <list of other files in this set>
  > Depended on by: <list of files that reference this one>
  ```
- Use H2 (`##`) for top-level sections, H3 (`###`) for subsections. No H4 or deeper (link to sub-doc instead).
- Use code blocks with `swift` language hint for Swift snippets.
- Use tables for matrices, state machines, risk registers.
- Use ASCII diagrams (box-and-line) for C4-style context, container, component diagrams. No Mermaid (some readers won't render it).
- Inline links: `[Section 4.2](https://...)` for external, `[§4.2](#42-permissionmanager)` for internal.
- Source citation format: `[Apple SpeechAnalyzer docs](https://developer.apple.com/documentation/speech/speechanalyzer) — accessed 2026-06-18`.

---

## 7. Self-check questions

When you think you're done, answer these in a final section at the bottom of `SPEAK_ROADMAP.md` (titled "Self-check"):

1. Can a senior Swift engineer start coding the first 5 roadmap tasks from these docs alone, with no questions? Y/N + one-sentence justification.
2. Can a senior PM sequence the v0 / v0.1 / v1 / v2 launch from the roadmap? Y/N + justification.
3. Can a senior QA write a test plan from the validation doc? Y/N + justification.
4. Did you cite primary sources for every Apple API, library, and version claim? Y/N.
5. Is the architecture a real system, or a sketched MVP? Y/N.
6. Did you avoid "TBD" / "TODO" / "figure out later"? Y/N.
7. Did you derive the API from the architecture, the roadmap from the API, and the validation plan from the roadmap? Y/N.
8. Is every risk paired with a decision rule and an escape hatch? Y/N.
9. Are all five files internally consistent (no cross-doc contradictions)? Y/N.
10. If the user wanted to ship `speak` v0 next Monday, what's missing? Be honest. List gaps.

If any answer is "N" or "sort of", fix the doc(s) and re-run the self-check.

---

## 8. Tools to use

- **`read_file`** — read `IDEATION.md`, `CATEGORY_LANDSCAPE.md`, `SPEAK_PRODUCT_SPEC.md` first. Re-read sections as needed.
- **`write_file`** — create the five deliverable files.
- **`web_search`** — verify every technical claim against primary sources. Use specific queries: `Apple SpeechAnalyzer macOS 26 documentation`, `NSPasteboard macOS 26.4 paste protection`, `CGEventTap Accessibility permission macOS 26`, etc.
- **`update_plan`** — track your own progress. Step 1: read inputs, Step 2: verify, Step 3: architecture, ... Step 10: commit.
- **Shell** (`exec_command`) — only if you need to verify file paths or git status. Do not start coding yet — that comes after this brief is approved.
- **Do NOT use** `image_view` or any image-related tool — not needed for docs.
- **Do NOT use** `browser` tools — web search is enough.

---

## 9. Failure modes to avoid

- **Drift into a survey**. Don't list every STT engine with pros and cons. Pick the primary, the fallback, the cloud opt-in. Move on.
- **Cargo-cult patterns**. Don't import patterns from web frameworks (React, Next.js) — this is a macOS native app, not a web app. SwiftUI + AppKit + AVFoundation is the stack.
- **Hand-waving on concurrency**. "We'll use async/await" is not enough. Specify the actor model, the main-thread invariants, the cancellation policy.
- **Phantom APIs**. Don't invent Apple APIs. If you're not sure an API exists, search the docs. If you can't find it, mark it `inferred` and explain.
- **Cargo-cult "AI safety"**. `speak` is a dictation app. It pastes text. It doesn't need a permissions framework, a tool registry, an agentic loop. Stay scoped.
- **Premature optimization**. Don't add caching, prefetching, or batching unless the roadmap calls for it. Ship the v0 plan as specified.
- **Skipping the validation doc**. The validation plan is half the deliverable. A roadmap without a test plan is a wishlist.
- **Skipping the risk register**. Every shipped product has a risk register. Surface the hard parts, don't bury them.

---

## 10. Final checklist

Before you commit each file, run this checklist:

- [ ] Front matter is present and accurate.
- [ ] Every section is complete (no "TBD" / "TODO" / "we'll see").
- [ ] Every claim has a primary-source link with date.
- [ ] Every Swift type has a real signature, not pseudocode.
- [ ] Every state machine has a transition table.
- [ ] Every performance budget has a number.
- [ ] Every "done when" is testable.
- [ ] Every risk has a decision rule.
- [ ] Cross-links work (no broken anchors).
- [ ] Code blocks use `swift` hint.
- [ ] No Mermaid. ASCII diagrams only.
- [ ] File written to `/Users/tamil/Developers/deepvoice/`.

When all five files are committed and pass the self-check, output a single final message:

> **Build brief complete.** Five files in `/Users/tamil/Developers/deepvoice/`: `SPEAK_ARCHITECTURE.md`, `SPEAK_API.md`, `SPEAK_ROADMAP.md`, `SPEAK_VALIDATION.md`, `SPEAK_RISKS.md`. Ready for review. First 48-hour tasks: [list the first 3-5 tasks from the roadmap].

Then stop. The user will review, ask for changes, and approve before any code is written.

---

## 11. What comes after this brief

The user (or a follow-up Claude Code session) will use this brief to:

1. **Review** the five docs.
2. **Ask for changes** if any doc fails the self-check.
3. **Approve** the brief.
4. **Switch to implementation** — start with the Day 0 repo setup in `SPEAK_ROADMAP.md`.
5. **Track progress** against the roadmap and validation plan.
6. **Ship v0** in 2 weeks.

This brief is the contract between design and implementation. Make it good.

---

## 12. A note on Opus-specific behavior

You (Opus) are particularly good at:

- Holding a long brief like this one in working memory while you write.
- Producing structured, opinionated output without constant prompting.
- Catching your own inconsistencies across multi-doc deliverables.
- Writing Swift code that compiles, not pseudocode.

Lean into those strengths. If a section is hard, say so explicitly and explain your best guess. If you find a contradiction between the product spec and the technical reality (e.g. an Apple API doesn't exist the way the spec assumes), surface it as a question — don't silently paper over it. The user is sharp. They will catch a glossed-over issue. They will appreciate a direct "I couldn't verify this, here's what I found, here's my best guess."

**Now begin.** Read the three input files, then start with `SPEAK_ARCHITECTURE.md`.
