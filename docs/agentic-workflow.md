# `speak` — Agentic Build Workflow (HOW we build)

> **Status**: Standing operating manual for any agent (orchestrator or worker)
> building speak. Read alongside `AGENTS.md`. **Updated**: 2026-06-29.
>
> One sentence: **speak is a Mac-local build of a bleeding-edge-SDK app, so the
> Apple-Silicon Mac doing the build is the source of truth — not the cloud.**

---

## 0. Why this doc exists

speak imports `FoundationModels` and `SpeechAnalyzer` — frameworks that exist
**only on the macOS 26 SDK**. GitHub's hosted CI runners (Xcode 16.4 / SDK 15.5)
cannot compile the project at all (`error: no such module 'FoundationModels'`).
Therefore the usual "CI is the gate" assumption is **false here**. Every practice
below follows from that one fact.

This is a deliberate product constraint, not a limitation: speak targets the
**latest macOS on Apple Silicon** and leans into its newest on-device AI
frameworks. No back-deployment, no older-OS support. That *simplifies* the build
— one SDK, one arch — and the workflow should exploit the simplification.

---

## 1. The authority model (read this first)

| Authority | Role |
|-----------|------|
| **`make build` / `make test` / `make lint` on this Mac** | **THE merge gate.** Authoritative. Nothing merges unless these pass locally. |
| Local macOS 26 SDK (`swiftc -typecheck`) | The truth for any Apple-API claim. Past the model's training cutoff ⇒ memory is unreliable, the SDK is not. |
| GitHub Actions CI | **Best-effort mirror only.** Pinned to `macos-26`; may lag GitHub's image availability. A red CI never blocks a locally-green merge. |
| `make verify-moat` (Linux-portable) | Always-reliable structural gate (no Xcode needed). Runs in CI on `ubuntu-latest`. |

> **Rule:** if local gates are green and CI is red for an *environmental* reason
> (runner SDK too old, image unavailable), merge with `--admin` and note why.
> If CI is red for a *code* reason that also reproduces locally, it's a real bug
> — fix it, don't override.

---

## 2. Hard build practices (Mac-local specifics)

1. **Local gates are the contract.** No merge without `make build/test/lint`
   passing on this Mac. CI is advisory.
2. **Never tag an Apple-API claim `[verified]` from memory.** Confirm with
   `swiftc -typecheck` against the local SDK or the `apple-docs` MCP. If a
   `[verified]` claim contradicts a primary source, **stop and surface it**.
3. **Single target, no hedging.** One arch (arm64), one deployment target
   (macOS 26), no `#available` ladders, no back-deployment shims. Newest
   frameworks are fair game — that's the point.
4. **Dev code-signing must persist for TCC.** Build signed with the stable
   `speak-local-codesign` identity (`make dev-cert` once, then `make build`).
   Ad-hoc / changing signatures break the Accessibility + Microphone grants on
   every rebuild → Cmd+V paste silently no-ops. See `[[dev-codesigning-for-tcc]]`.
5. **`os.Logger` only, no `print`.** No force-unwrap / `try!` / `as!` outside
   tests (swiftlint enforces these as errors).
6. **Don't pipe `make test` through `tail`/`head`** — truncation hides the real
   `** TEST SUCCEEDED **` and mislabels error-path log lines as failures. Read
   the full output (or grep for the result line).

---

## 3. The loop (the unit of work)

Code is the contract; GitHub issues/PRs are the system of record.

```
known issue / next roadmap task
        │
        ▼
  gh issue  ──────────────►  branch  fix/<slug> or feat/<slug>
        │                        │
        │                        ▼
        │                 fast worker implements (edits only)
        │                        │
        │                        ▼
        │            ORCHESTRATOR reviews the diff
        │                        │
        │                        ▼
        │            local gates: build ✅ test ✅ lint ✅ moat ✅
        │                        │
        │                        ▼
        └──────────  commit (per task) → push → PR (Closes #N)
                                 │
                                 ▼
                       merge when gates green
                       (CI advisory; local authoritative)
```

- **One commit per completed roadmap task**: `[P<N>] <task>: <what changed>`.
- **Open a follow-up issue** for anything deferred during review (don't silently
  drop scope).
- **Never commit broken code or secrets.** Keep the working tree clean.

---

## 4. Model tiering (the acceleration lever)

| Tier | Who | Owns |
|------|-----|------|
| **Judgment** | Opus (orchestrator) | Design, spec-lock, diff review, the merge decision, Apple-API verification, commits. |
| **Volume** | Haiku · WSL2 MiniMax M3 (free) | Mechanical multi-file implementation from a precise brief. |

> No Sonnet middle tier currently (weekly limit). Route judgment → Opus,
> bulk code → fast worker. Topology (parallel vs serial) before model tier.

**Every worker dispatch carries a 5-part brief:** ROLE / GOAL / CONTEXT /
CONSTRAINTS / OUTPUT. No brief = no dispatch. A vague brief wastes a fast agent —
it runs fast in the wrong direction.

---

## 5. Worker constraints (non-negotiable)

- **Workers edit the main checkout directly.** This repo's `isolation:worktree`
  does **not** produce an isolated tree — so parallel file-mutating workers must
  be **serialized**, or given manually-created worktrees. See
  `[[orchestrator-runs-in-worktree]]`.
- **Workers never run git ops** (no commit, no `reset`, no branch). They edit;
  the orchestrator stages, reviews, and commits.
- **Workers never tag `[verified]`** — only the orchestrator does, after SDK
  confirmation.

---

## 6. Build sequencing (product-level)

**Completeness before polish.** Build every component correctly and fully first;
visual/contrast/typography is a separate, later pass. Polishing an incomplete app
wastes work. See `[[build-sequencing-completeness-first]]`.

---

## 7. CI shape (current)

`.github/workflows/ci.yml` has two jobs:
- **`moat-audit`** (`ubuntu-latest`): `make verify-moat` — always-reliable green
  gate, no Xcode needed.
- **`build-test-lint`** (`macos-26`): `make build/test/lint` — the full gate,
  best-effort, pinned to the only image with the macOS 26 SDK.

If GitHub's `macos-26` image is unavailable or lagging, the build job may fail
for environmental reasons. That does **not** block a locally-green merge (§1).
