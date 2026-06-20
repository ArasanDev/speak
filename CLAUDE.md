# CLAUDE.md — `speak` (repo dir: `deepvoice`)

This repo builds **`speak`**: a macOS-native, **local-first, free, open-source AI
voice dictation app** — speech → text, then the AI writes it neatly, pasted at
the cursor, 100% on-device. (The directory is named `deepvoice` for historical
reasons; the product is `speak`. The abandoned `deepvoice` coding-agent idea is
archived in `research/sample-ideation.md` — do not build it.)

This file is the entry point. The real detail lives in `AGENTS.md` + `docs/`.
Read those; don't duplicate them here.

---

## Read first, every session (the loading protocol)

1. **`AGENTS.md`** — the operating manual: mission, hard constraints, the loop.
2. **`docs/progress.md`** — current state. **Read first, rewrite last.**
3. **`docs/roadmap.md`** — pick the lowest-numbered dependency-ready task.
4. **`docs/benchmark.md`** — the definition of done (the loop's objective function).

Load other `docs/` per the task (`architecture.md` to implement, `quality.md` to
verify, `product.md` for the destination). Verified facts are in
`specs/verification-ledger.md`. `research/` is read-only evidence — never build
direction from it.

---

## What "done" means — there is NO deadline

This is an autonomous, agent-driven build. The loop runs across as many cycles as
it takes (hours or days) until the **complete product** exists. "Done" is defined
by testable criteria, never by dates/effort/hours:

> **v0 is complete when** `benchmark.md` §4 MATCH gate + §3 BEAT rows +
> `quality.md` §9 ship checklist all pass.

v0 = the complete core (incl. AI neat-writing), not an MVP. v1/v2/v3+ make it
attractive/friendly/creative (`product.md` §9).

---

## Hard rules (full list: `AGENTS.md` §2–3 — never trade these away)

- **100% local by default.** No cloud audio, no telemetry, no accounts, works offline.
- **v0 = Apple frameworks only, no third-party deps.** `SpeechAnalyzer` (STT) and
  `Foundation Models` (cleanup) are Apple frameworks → allowed. Ollama/WhisperKit
  are v0.1+ *alternatives*, never the default dependency.
- **AI neat-writing is core**, not optional. Default cleanup = on-device
  `Foundation Models`, pluggable via `LLMCleaning`, with a raw-transcript fallback.
- **Never read the pasteboard** — only write (+ simulate Cmd+V). (Test the paste
  path empirically at P6 — the bypass is `[unverified]`; macOS 26.4 added a
  Terminal paste-provenance check.)
- `os.Logger` only — **no `print`**. No force-unwrap / `try!` / `as!` outside tests.
- No global mutable state; never block the main thread.
- **No magic numbers**: every constant traces to a measured value, a platform
  constraint, or a `[decision]` in `benchmark.md` §7.
- Tag claims `[verified]` / `[inferred]` / `[decision]` / `[unverified]`. If a
  `[verified]` claim contradicts a primary source, **stop and surface it**.

---

## Commands

> Repo is **pre-build**; Phase 0 establishes these (Makefile/justfile + CI). Verify
> the toolchain before P0: `xcodebuild -version`, `swift --version`. The repo is
> not yet a git repo — run `git init` first.

- **Build**:   `make build`   — xcodebuild: `speak.app` + `SpeakCore.framework`
- **Test**:    `make test`    — xcodebuild test (XCTest + XCUITest)
- **Lint**:    `swiftlint`
- **Release**: `make release` — Developer ID sign + notarize + `.dmg` + Homebrew cask

---

## Commit discipline (full: `AGENTS.md` §7)

Commit per completed roadmap task: `[P<N>] <task>: <what changed>`. Never commit
broken code or secrets. Keep the working tree clean.

---

## Stack at a glance (full: `architecture.md`)

Swift 5.9+ / SwiftUI · macOS 26 (Tahoe) · Apple Silicon. `SpeechAnalyzer` (STT) +
`Foundation Models` (cleanup), both pluggable. `CGEventTap` hotkey (double-tap Fn,
customizable) · `NSPasteboard` write + `Cmd+V` paste · SQLite history · `os.Logger`.
Single Swift codebase; engine logic in `SpeakCore.framework` (the portability seam).
MIT · Homebrew Cask + `.dmg`, not sandboxed in v0.
