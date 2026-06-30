# CLAUDE.md — `speak`
macOS-native, local-first, free, open-source AI voice dictation: speech → AI-cleaned text → pasted at cursor, 100% on-device.

This file is the CC harness entry point. Read `AGENTS.md` next — it is the operating manual.

---

## Read first — every session
1. `AGENTS.md` — operating manual, hard rules, routing, the loop
2. `docs/progress.md` — current state; **rewrite last**
3. `docs/roadmap.md` — pick lowest-numbered dependency-ready task
4. `docs/benchmark.md` — the done-condition (objective function)

Load task-specific docs per the task: `docs/architecture.md` to implement, `docs/quality.md` to verify, `docs/product.md` for destination. `research/` is read-only evidence — never build direction from it. Verified facts: `specs/verification-ledger.md`.

---

## Commands
```
make build        # xcodegen generate → xcodebuild build
make test         # full suite (XCTest + Swift Testing)
make lint         # SwiftLint; force-unwrap/cast/try = errors
make verify-moat  # structural BEAT audit; no Xcode needed; re-runnable in CI
make run          # build then launch menubar app
make lsp          # configure buildServer.json for SDK-correct Swift semantics
make release      # sign + notarize + .dmg + Homebrew cask (stubbed until P11)
```

One test: `xcodebuild test -project Speak.xcodeproj -scheme Speak -derivedDataPath build/DerivedData -only-testing:SpeakTests/<Suite>/<testMethod>`

`Speak.xcodeproj` is git-ignored; `make` regenerates it via XcodeGen from `project.yml`.

---

## Hard rules (full list: `AGENTS.md §2–3`)
- **100% local.** No cloud audio, no telemetry, no accounts, works offline.
- **v0 = Apple frameworks only.** No third-party deps. `SpeechAnalyzer` + `Foundation Models` are Apple → allowed.
- **Never read the pasteboard** — only write (+ simulate Cmd+V).
- `os.Logger` only — no `print`. No force-unwrap / `try!` / `as!` outside tests. No global mutable state. Never block main thread.
- Tag claims `[verified]` / `[inferred]` / `[decision]` / `[unverified]`. Never tag an Apple-API claim `[verified]` from memory — confirm with `swiftc -typecheck` against local macOS 26 SDK.

---

## Stack
Swift 5.9+ / SwiftUI · macOS 26 (Tahoe) · Apple Silicon · not sandboxed in v0.
`SpeechAnalyzer` (STT) + `Foundation Models` (cleanup), both pluggable via `Transcribing` / `LLMCleaning`.
`CGEventTap` hotkey (double-tap Fn) · `NSPasteboard` write + Cmd+V · SQLite history · `os.Logger`.
Engine logic in `SpeakCore.framework`; App target is the SwiftUI shell. Full map: `docs/architecture.md`.
Tooling: Xcode 26+ · `xcodegen` + `swiftlint` via Homebrew. Agent team + skills: `docs/agent-tooling.md`.

---

## Done condition
v0 complete when: `benchmark.md §4` MATCH gate + `§3` BEAT rows + `quality.md §9` ship checklist all pass.
v0 = complete core (incl. AI neat-writing), not an MVP. v1/v2/v3+ = attractive/friendly/creative (`product.md §9`).

---

## Commit
`[P<N>] <task>: <what changed>` — one commit per completed roadmap task. Full rules: `AGENTS.md §7`.
