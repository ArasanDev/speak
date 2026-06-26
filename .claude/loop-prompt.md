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

---

## Execute

For each task:
1. Read the relevant `docs/` files (architecture.md for impl, quality.md for verify)
2. Read the surrounding source code before writing any new code
3. Implement + write tests together (tests are not optional)
4. Run all four gates:

```sh
make build        # must exit 0, no new warnings
make test         # must exit 0, 0 failures
make lint         # must exit 0, 0 serious violations
make verify-moat  # must be 7/7
```

5. Verify the specific `done-when` criterion from `roadmap.md` (binary pass/fail)
6. Update `docs/progress.md` (see below)
7. If all gates green + done-when met → commit: `git commit -m "[P<N>] <task>: <what changed>"`

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

1. Re-read the relevant `docs/` section (the answer is usually there)
2. Verify the claim against a primary source: `swiftc -typecheck` against the
   local SDK, or use the `apple-docs` MCP. The local SDK is the cutoff-proof oracle.
3. Log it as an open question in `progress.md`
4. Pick the next unblocked task — **never stall waiting**

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

---

## Verification backbone

Apple API questions (SpeechAnalyzer, Foundation Models, CGEventTap):
```sh
swiftc -typecheck -sdk "$(xcrun --show-sdk-path)" -target arm64-apple-macosx26.0 probe.swift
```
Or use the `apple-docs` MCP (`apple-docs` in `.mcp.json`). Never trust training
memory for post-2025 Apple API shapes.

---

## Done criteria (v0 complete when ALL pass)

- `make verify-moat` → 7/7 (structural BEAT rows, automated)
- `make test` → 0 failures, all existing XCTSkip documented
- `benchmark.md` §4 MATCH gate rows all checked `[verified]`
- `quality.md` §9 ship checklist: all rows resolved

End of loop prompt. Start with the load order above.
