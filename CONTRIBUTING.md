# Contributing to `speak`

> **speak is agent-native.** Contributions are authored by agents — Claude
> Code, Codex, Devin, Cursor, whatever you drive — and directed/reviewed by
> humans. Point your agent at `AGENTS.md` (the operating manual) and
> `llms.txt` (the machine-readable index); it can navigate, implement, and
> self-verify from there. The human's job is directing intent and reviewing
> the result, not writing code.
>
> **Observing rather than contributing?** README → `docs/ui/philosophy.md` →
> `docs/progress.md` is the read path.

---

## Build and test

Requirements: macOS 26 (Tahoe), Apple Silicon, Xcode 26+.

```bash
# Install build tools (one-time; dev tooling only — not runtime deps)
brew install xcodegen swiftlint xcbeautify

# Build
make build        # xcodegen generate → xcodebuild → Speak.app + SpeakCore.framework

# Test
make test         # xcodebuild test (XCTest + Swift Testing); all must pass

# Lint
make lint         # swiftlint; force-unwrap / force-cast / force-try are errors

# Structural moat audit
make verify-moat  # 7/7 source-tree checks (MIT, no third-party imports, no egress, ...)

# Run
make run          # build + launch the menubar app

# The merge gate — build -> test -> lint -> verify-moat, in order
make gates
```

`make build` runs `xcodegen generate` automatically. A clean clone has no
`.xcodeproj` (it is git-ignored; `project.yml` is the source of truth).

**CI** (`.github/workflows/ci.yml`) is release-time, not per-push — speak is
local-first, so `make gates` on your Mac is the real gate. `moat-audit` runs
on pull requests only (it guards external contributions — a PR adding cloud
egress, telemetry, or a third-party dep fails it). `lint` runs on ubuntu in
parallel (swiftlint needs no Apple SDK). The `build-test` job (`macos-26`
runner — `FoundationModels`/`SpeechAnalyzer` only resolve on the macOS 26
SDK) runs on manual `workflow_dispatch` when cutting a release.

---

## Navigating the repo

| File | Purpose |
|---|---|
| `AGENTS.md` | Operating manual — the mission, hard rules, autonomous loop |
| `docs/progress.md` | Living state. Read first every session, update last. |
| `docs/roadmap.md` | Build order; dependency-ordered phases; done-when criteria |
| `docs/architecture.md` | How it is built — modules, types, Swift signatures |
| `docs/benchmark.md` | Definition of done — parity vs Wispr Flow (the frontier) |
| `docs/quality.md` | Tests, risks, ship checklist |
| `docs/human-verification.md` | Live-gated items that require a real Mac + permissions |
| `SPEC.md` | Consolidated human-readable spec (competitive positioning, personas, UX) |
| `specs/` | Point-in-time plans and the verification ledger |
| `research/` | Evidence archive — read-only; never the source of direction |

Do not treat `research/` as direction. It is historical reasoning; the
`docs/` set is the active source of truth.

---

## Architecture seams

Four build products, wired by XcodeGen from `project.yml`: `Speak.app` (SwiftUI
menubar shell), `SpeakCore.framework` (headless engine, no SwiftUI), `SpeakLLM.framework`
(the opt-in cloud cleanup engine, isolated in its own target so the moat audit can
honestly assert zero networking/auth symbols in `SpeakCore`/App/CLI), and the
`SpeakTests` bundle — plus two CLI tools, `speak` (`SpeakCLI`) and `speak-mcp`
(`SpeakMCP`). Every seam is a protocol (`Transcribing`, `LLMCleaning`,
`TextInserting`, `HistoryStoring`) — mock conformances make every seam
headless-testable. See `docs/architecture.md` for the full pipeline and module layout.

---

## Coding conventions

Follow the hard rules in `AGENTS.md §2`. SwiftLint enforces the mechanical rules: `make lint`.

---

## Commit discipline

One commit per completed roadmap task. Format:

```
[P<N>] <task>: <what changed>
```

Examples:
```
[P5] hotkey: CGEventTap double-tap Fn, DoubleTapDetector, HotkeyBinding Codable
[P9] history: SQLite HistoryStore, HistoryStoreTests (11 tests)
```

Never commit broken code or secrets. Keep the working tree clean before spawning
sub-agents or branching. The orchestrator reviews diffs and owns commits.

---

## Verification discipline

Code is not done when written — done when verified. Before marking a task complete:

1. `make build` exits 0, no new warnings.
2. `make test` — all tests pass; new code has tests.
3. `make lint` — no new serious violations.
4. `make verify-moat` — still 7/7.
5. The specific done-when criterion from `docs/roadmap.md` is met.
6. `docs/progress.md` is updated with what was done + any decisions made.

Live-gated criteria (paste into real apps, hotkey with real permissions) cannot
be verified headlessly. Mark them `[deferred — needs human verification]` and
add a row to `docs/human-verification.md`. Never mark them passed without a
real run.

---

## Proposing changes

### The pull request flow (agent-driven)

1. Direct your agent: fork, branch, implement. It runs `make preflight` —
   the same three checks CI runs on a PR (moat audit + lint + compile,
   ~2-3 min, no test suite).
2. The agent opens the PR. Three checks run automatically, in parallel:
   `moat-audit` (~30s), `lint` (~2min), `build` on macOS (~5-8min).
   Expect green/red in under 10 minutes.
3. A human reviews the PR — direction, taste, and whether the agent's
   claims match the diff. A maintainer runs `make gates` (full suite)
   locally before merge — the real gate, since speak is local-first.
4. Squash-merge keeps history linear.

Small fixes (typos, docs, small bugs) don't need an issue first. Anything
bigger — new surface, new engine conformer, changed public API — open an
issue to discuss before writing code; it saves everyone time.

For architectural or seam-level changes, read `docs/architecture.md` and open
a discussion or issue first. The seams are stable by design.

- `docs/product.md` is immutable — it defines the destination and is
  human-owned. Do not propose changes to it in a PR.
- For new platforms, new STT/cleanup engines, or anything that adds a runtime
  dependency, read `AGENTS.md §2` (the hard constraints) first.
- The `research/` directory is read-only evidence. Never turn it into direction.
