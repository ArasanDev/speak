# AGENTS.md
> Operating manual for all autonomous agents on this repo. Read at session start. Authority: overrides defaults; superseded only by primary sources ([verified] claims, swiftc output, local SDK).

---

## 1. Mission

`speak` = macOS-native, local-first, free, open-source human interface for
software agents. Its completed v0 foundation is voice dictation: speech→text +
AI neat-writing, both on-device and pluggable. The next product layer adds
provider-neutral agent input, attention, and response workflows. `speak` is not
an agent, chatbot, reasoning engine, or cloud service. Not cross-platform in v0.

v0 is complete when `benchmark.md` §4 MATCH gate + §3 BEAT rows + `quality.md` §9 ship checklist all pass. No deadlines. No effort estimates. Run the loop until those gates pass.

---

## 2. Hard Rules — inviolable

Violating any of these requires explicit human approval. Surface conflicts; never silently bypass.

1. **100% local by default.** No cloud audio. No telemetry. No accounts. No login. (Cloud STT = v1 opt-in only.)
2. **Two OS permissions only**: Microphone + Accessibility. `CGEventTap` uses `.defaultTap` → Accessibility-gated. Input Monitoring is NOT used in v0.
3. **No third-party dependencies in v0.** Apple frameworks only. `SpeechAnalyzer` + `Foundation Models` are Apple → allowed. WhisperKit/Ollama = v0.1+.
4. **Swift 5.9+ / SwiftUI. macOS 26.0 deployment. Apple Silicon only in v0.**
5. **Single Swift codebase.** No Rust core. No FFI. No cross-platform abstraction. [decision: `architecture.md` §1]
6. **Never read the pasteboard** — only write to it. macOS 26.4 paste-provenance check applies.
7. **Hardware mute cannot be bypassed.** When muted, no audio is captured.
8. **AI neat-writing is core, not optional.** Default engine = Apple `Foundation Models`. Fallback = raw transcript. Pluggable via `LLMCleaning`.
9. **No `print`.** Use `os.Logger` (OSLog). Define log categories in `SpeakCore/Logging/`.
10. **No force-unwrap, no `try!`, no `as!`** in production code. Use `guard let` / `throws`. Exceptions only in tests.
11. **No global mutable state.** All state owned by an actor or injected via SwiftUI environment.
12. **Never block the main thread.** Audio on background queues. UI on `@MainActor`.
13. **No magic numbers.** Every constant traces to a measured value, platform constraint, or `[decision]` in `benchmark.md` §7.
14. **Tag every factual claim.** See §9.

---

## 3. File authority hierarchy

When two sources conflict, the higher rank wins.

1. `swiftc -typecheck` against local macOS 26 SDK — absolute ground truth
2. `apple-docs` MCP (live Apple docs) — official, symbol-searchable
3. `[verified]` skill claim with source URL — trusted; re-fetch if > 2 weeks old
4. `AGENTS.md` (this file) — project operating rules
5. `docs/` files — design decisions, architecture, roadmap
6. `research/evidence/` — why-evidence archive; read-only; never the direction
7. Training memory — starting point for searches, never a fact to ship

`research/archive/` has been removed; it contained superseded reasoning, including a false claim (states Claude Code is Rust+WASM).

---

## 4. Loading protocol — every session

Run this sequence before touching any code.

1. Read `AGENTS.md` (this file) — constraints, conventions, routing.
2. Read `docs/progress.md` — current state, blocked tasks, open questions.
3. Read `docs/roadmap.md` — find the lowest-numbered dependency-ready undone task.
4. Load the task-specific doc(s): `architecture.md` to implement; `quality.md` to verify; `benchmark.md` to evaluate done.
5. Execute the task (code + tests together).
6. Verify: build clean → tests green → done-when met → no regressions → §2 honored.
7. Update `docs/progress.md` (done / blocked / next / decisions logged).
8. Commit if verifiably complete (see §8).
9. Return to step 3.

---

## 5. Codebase entry points

| What you need | Where to read |
|---|---|
| Product definition + version ladder | `docs/product.md` |
| Module map, types, call sequences | `docs/architecture.md` |
| Build order (dependency-ordered) | `docs/roadmap.md` |
| Definition of done (v0 gate) | `docs/benchmark.md` |
| Test gates, ship checklist | `docs/quality.md` |
| Current session state | `docs/progress.md` |
| Team, skills, MCP tools | `docs/agent-tooling.md` |
| Verified API facts (ledger) | `specs/verification-ledger.md` |
| Why a decision was made | `research/evidence/` (read-only) |

Do not read `research/sample-ideation.md` for product direction (it documents the abandoned `deepvoice` idea, not `speak`).

### Key build commands

| Command | What it does |
|---|---|
| `make build` | `xcodegen generate` → `xcodebuild build` |
| `make test` | Full XCTest + Swift Testing suite |
| `make lint` | `swiftlint` (force-unwrap/cast/try are errors) |
| `make verify-moat` | Standalone §2 hard-rule audit; no Xcode required |
| `make run` | Build then launch the menubar app |
| `make lsp` | Regenerate `buildServer.json` for SDK-correct Swift semantics |

Re-run `make lsp` after a clean clone or `project.yml` change, then reload the LSP. `Speak.xcodeproj` is git-ignored; `make build` regenerates it via XcodeGen.

---

## 6. Team routing

Route each seam's work to its specialist. Never have one agent touch all seams.

| Seam | Agent | Files owned |
|---|---|---|
| Engine core: session lifecycle, state machine, error model, logging | `builder-engine` | `SpeakCore/` (non-audio) |
| Audio capture + STT (`SpeechAnalyzer`, `DictationTranscriber`) | `builder-audio-stt` | `SpeakCore/Audio/`, `SpeakCore/Transcribing/` |
| AI neat-writing (`LLMCleaning`, `Foundation Models`) | `builder-cleanup` | `SpeakCore/Cleaning/` |
| Global hotkey (`CGEventTap`), pasteboard write, Cmd+V, permissions | `builder-input` | `SpeakCore/Input/`, `SpeakCore/Permissions/` |
| SwiftUI app shell: MenuBarExtra, onboarding, overlay, SQLite history | `builder-app` | `Speak/` (App target), `SpeakCore/Storage/` |
| Build system, CI, sign/notarize, Homebrew cask | `builder-release` | `project.yml`, `Makefile`, `.github/` |
| Tests, benchmarks, dogfood | `builder-qa` | `SpeakTests/`, `SpeakUITests/` |

---

## 7. The build loop

1. Pick the lowest-numbered dependency-ready task from `docs/roadmap.md`.
2. Load task-specific docs (`architecture.md` section for that task).
3. Research before coding: identify any claim marked `[inferred]` or `[unverified]` in the relevant skill. Verify against `swiftc -typecheck` or `apple-docs` MCP before writing code. See §3 for trust hierarchy.
4. Implement: code + tests together. No code without a test.
5. Test: `make test` — all green, no regressions.
6. Lint: `make lint` — zero swiftlint errors (force-unwrap/cast/try are errors).
7. Moat check (before each commit): `make verify-moat` — standalone audit of §2 hard rules; no build required, re-runnable.
8. Evaluate: task's "done when" criterion from `roadmap.md` — binary pass/fail.
9. Commit: see §8.
10. Update `docs/progress.md` — mark done, log decisions, note what's next.
11. Return to step 1.

**Act autonomously within the rails**: implementing a specified task, writing tests, fixing reproducible bugs, updating `progress.md`, refactoring within a module's public API, upgrading a skill's `[inferred]` tag to `[verified]` after confirming.

**Stop and ask before moving the rails**: changing `architecture.md` public API, reordering roadmap phases, adding or removing v0 scope, doing anything irreversible.

### Verification gate (before marking any task done)

- `xcodebuild build` exits 0, no warnings-as-errors.
- All existing tests green. New code has tests.
- The task's specific "done when" criterion is satisfied — not "basically works."
- `progress.md` notes no new regressions.
- `make verify-moat` passes (no §2 violations detected in source).

If you cannot verify (e.g., no mic access), say so explicitly in `progress.md`. Do not claim done what you cannot prove.

---

## 8. Commit convention

Format: `[P<N>] <task short name>: <what changed>`

Examples:
- `[P2] audio capture: AVAudioEngine 16kHz mono, mic permission flow`
- `[P3] STT: SpeechAnalyzer DictationTranscriber, streaming partial results`

Rules: one commit per completed roadmap task. Never commit broken code. Never commit secrets or large binaries. Agent commits autonomously; human reviews via `git log`.

---

## 9. Claim tagging

Tag every factual assertion about APIs, behavior, or external systems.

| Tag | Meaning | Example |
|---|---|---|
| `[verified]` | Confirmed via `swiftc -typecheck`, `apple-docs`, or primary source | `SpeechAnalyzer.DictationTranscriber [verified via apple-docs, 2026-06-10]` |
| `[inferred]` | Reasoned from context; not directly confirmed | `Buffer size 4096 [inferred from AVAudioEngine docs]` |
| `[decision]` | Deliberate design choice with rationale logged | `No sandbox in v0 [decision: pasteboard access requires it]` |
| `[unverified]` | Needs confirmation before shipping | `Cmd+V bypass on macOS 26.4 [unverified]` |

When a `[verified]` claim contradicts a primary source: stop, surface the conflict, do not paper over it.

---

## 10. Escalation

Stop and surface to the human when:

- A `docs/` decision contradicts a primary source you can verify (bring the contradiction).
- A hard rule (§2) blocks progress with no clean path around it.
- A public API in `architecture.md` needs changing.
- A roadmap phase needs reordering or scope change.
- You've failed the same task 2 times. Rewrite context, not the prompt.
- You're about to do something irreversible (delete data, rewrite a module, change license).

Bring: what you tried, what you found, what you'd do if forced to decide. Don't ask without context.

---

*Read `docs/progress.md` next. Then pick your task.*
