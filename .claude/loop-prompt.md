# speak — autonomous loop prompt

You are an agent running one loop cycle on the `speak` macOS dictation app
(repo: `deepvoice/`). The product is a local-first, free, open-source voice
dictation app for macOS. The build loop runs until `benchmark.md` §4 MATCH +
§3 BEAT + `quality.md` §9 ship checklist all pass.

---

## Load order (do this first, every cycle — non-negotiable)

1. `AGENTS.md` §0–4 — mission, constraints, conventions, loop
2. Last 80 lines of `docs/progress.md` — current state, handoff banner, what's next
3. `docs/roadmap.md` — find the next undone dependency-ready task
4. The relevant skill(s) from `.claude/skills/` for that task

---

## Research-first protocol — run this BEFORE writing any code

Your training data has a knowledge cutoff. Anything Apple-framework-related
post-2025, any third-party package version, any external API — your training
memory is a hypothesis, not a fact. The protocol below turns hypotheses into
verified knowledge before they become bugs.

### Step 1 — Knowledge gap detection

Before touching a single file, ask yourself:
- Does this task use an Apple framework updated at WWDC26 (SpeechAnalyzer, Core AI,
  Foundation Models, AppIntents, ActivityKit)?
- Does it integrate a third-party package (WhisperKit, MLX, Sarvam, Ollama)?
- Does a skill exist for this seam? If yes, are its key claims `[verified]`?
  If the claims are `[inferred]` or `[unverified]`, verify them before using them.

If any answer is yes → research before coding. Every minute of research saves
two cycles of debugging a wrong API shape.

### Step 2 — Choose the right tool for the knowledge you need

| What you need | First tool | Fallback |
|---|---|---|
| Apple framework API shape | `apple-docs` MCP (search by symbol) | `swiftc -typecheck` probe |
| WWDC session content | WebSearch `WWDC26 [Framework] site:developer.apple.com` | WebFetch the session page URL |
| Swift package current API | WebFetch `github.com/<org>/<repo>/blob/main/README.md` at current tag | WebSearch `[Package] [version] swift API` |
| Third-party service API | WebFetch the official docs URL (from the skill) | WebSearch `[service] API documentation 2026` |
| SDK symbol existence | `swiftc -typecheck -sdk "$(xcrun --show-sdk-path)" -target arm64-apple-macosx26.0` | This IS ground truth — no web result overrides it |

### Step 3 — Search patterns that find authoritative sources

Apple APIs:
```
"DictationTranscriber" site:developer.apple.com
WWDC26 SpeechAnalyzer DictationTranscriber custom vocabulary
"import CoreAI" swift macos26
```

Swift packages:
```
WhisperKit 1.0.0 transcribe API site:github.com/argmaxinc
MLX Swift MLXLLM generate streaming
```

Third-party services:
```
Sarvam AI saaras v3 API request format 2026
Ollama api/chat endpoint JSON schema
```

**Trust order**: official Apple docs > WWDC session transcript > GitHub repo >
engineering blog. Never: training memory alone for any API that could have
changed since 2025.

### Step 4 — Update the skill after verifying

After confirming any claim:
- `[unverified]` → `[verified via swiftc]` or `[verified from: <URL>]`
- `[inferred]` → `[verified]` if confirmed; add source URL
- If the real API differs from the skill — **update the skill first, then write code**

This is the compounding step. Your verification is a gift to every future agent
working this seam. Leave the skill more accurate than you found it.

---

## Pick

Find the lowest-numbered `[ ]` task in `docs/roadmap.md` whose dependencies are
`[x]`. That is your task. If the task is marked `[~]` (in progress), continue it.

If multiple tasks are independent (different files, no shared seams), consider
fanning out to specialist agents from `.claude/agents/team/`:
- `builder-engine` — `SpeakCore/Engine/`
- `builder-audio-stt` — `SpeakCore/Audio/`, `SpeakCore/STT/`
- `builder-cleanup` — `SpeakCore/Cleanup/`
- `builder-input` — `SpeakCore/Hotkey/`, `SpeakCore/Paste/`, `SpeakCore/Permissions/`
- `builder-app` — `App/`, `SpeakCore/Storage/`
- `builder-release` — `project.yml`, `Makefile`, CI
- `builder-qa` — `SpeakTests/`, benchmarks, dogfood

Parallel agents: create explicit `git worktree add .wt/<name> -b <branch>` dirs
first. **Never commit from a subagent — the orchestrator reviews the diff and commits.**

Load the relevant skill before dispatching each agent — specialists should read
their skill before the first tool call.

---

## Execute

For each task:
1. Read the relevant `docs/` files (`architecture.md` for impl, `quality.md` for verify)
2. Read the skill(s) — check claim tags, verify `[unverified]` ones before using them
3. Read the surrounding source code before writing any new code
4. Implement + write tests together (tests are not optional)
5. Run all four gates:

```sh
make build        # must exit 0, no new warnings
make test         # must exit 0, 0 failures
make lint         # must exit 0, 0 serious violations
make verify-moat  # must be 7/7
```

6. Verify the specific `done-when` criterion from `roadmap.md` (binary pass/fail)
7. Update `docs/progress.md` (see below)
8. If all gates green + done-when met → commit: `git commit -m "[P<N>] <task>: <what changed>"`

---

## Update docs/progress.md

Update at the end of every work cycle. Structure:
- **Current Phase** — what phase/wave are we in
- **Done (this session)** — specific, citable changes with file:line refs
- **In Progress** — what's actively running, including any worktrees
- **Blocked** — what's blocked and why
- **Next Up** — the exact next task(s)
- **Open Questions** — unresolved, must not rot

Rule: "Worked on hotkey" is useless. "`HotkeyMonitor` now detects double-tap Fn
within 400ms; flaky on external keyboards — open Q#3" is useful.

---

## If blocked

1. Apply the research-first protocol above — most blocks are wrong API assumptions
2. Re-read the relevant `docs/` section (the answer is usually there)
3. Verify against the local SDK: `swiftc -typecheck` is the ground truth oracle
4. Use `apple-docs` MCP or WebSearch for post-2025 knowledge
5. Log it as an open question in `progress.md` with exactly what you searched and found
6. Pick the next unblocked task — **never stall waiting**

---

## Hard rules (never trade, never negotiate)

- 100% local: no cloud audio, no telemetry, no accounts
- v0 = Apple frameworks only — no third-party deps (WhisperKit/Ollama are v0.1+)
- `os.Logger` only — no `print` anywhere in production code
- No force-unwrap / `try!` / `as!` outside test files
- No global mutable state; no blocking the main thread
- Never read the pasteboard — only write to it
- Tag every API claim: `[verified]` / `[inferred]` / `[decision]` / `[unverified]`
- A `[verified]` claim that contradicts a primary source → stop and surface it
- Use `import CoreAI` for new ML work, not raw `import CoreML` (WWDC26)

---

## Verification backbone

The hierarchy of truth (trust in this order):
1. `swiftc -typecheck` against the local macOS 26 SDK — absolute ground truth
2. `apple-docs` MCP — official Apple symbol documentation
3. `[verified]` claims in the skill library — verified by a prior agent, cite the source
4. Official package README / docs at the current release tag
5. WebSearch results from developer.apple.com, official GitHub repos
6. `[inferred]` claims in the skill library — a hypothesis, must verify before shipping
7. Training memory — a starting point for searches, never a finishing point for code

```sh
# Verify any Apple API symbol:
swiftc -typecheck -sdk "$(xcrun --show-sdk-path)" -target arm64-apple-macosx26.0 probe.swift
```

---

## Done criteria (v0 complete when ALL pass)

- `make verify-moat` → 7/7 (structural BEAT rows, automated)
- `make test` → 0 failures, all existing XCTSkip documented
- `benchmark.md` §4 MATCH gate rows all checked `[verified]`
- `quality.md` §9 ship checklist: all rows resolved

End of loop prompt. Start with the load order, then the research-first protocol.
