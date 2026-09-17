# `speak` docs — index

> **Purpose**: Map of every file in `docs/` — where to go for what, grouped by audience and by task. · **Audience**: contributor, maintainer, AI agent · **Status**: living — new index, add an entry whenever a doc is added or renamed · **Last reviewed**: 2026-07-30 (reviewed today)

This is a map, not a rulebook — one line per doc. If you're new here, read in the order below.

## Start here (the mandated reading order, per `CLAUDE.md`)

Every session starts with `AGENTS.md` (the operating manual, one level up), then:

1. [`progress.md`](progress.md) — current state; the living file, rewritten every loop
2. [`roadmap.md`](roadmap.md) — pick the lowest-numbered dependency-ready task
3. [`benchmark.md`](benchmark.md) — the objective function: when is a task actually "done"

## By audience

**End user** — you don't need `docs/`. See the root `README.md`.

**Contributor** (building a feature)
- [`architecture.md`](architecture.md) — the HOW: tech stack, module layout, key Swift types, state machines
- [`roadmap.md`](roadmap.md) — build order, done-when criteria per phase
- [`quality.md`](quality.md) — test coverage expectations, risk register, ship gates
- [`ui/philosophy.md`](ui/philosophy.md) — **read first for any UI work** — the design philosophy: instrument-not-app, the three load-bearing rules, per-surface ideas, the never list
- [`ui/foundations.md`](ui/foundations.md) — design tokens, motion grammar, accessibility rules
- [`ui/surfaces-v0.md`](ui/surfaces-v0.md) — v0 surface-by-surface UI catalog
- [`ui/surfaces-future.md`](ui/surfaces-future.md) — v1/v2/v3+ UI exploration (do not implement yet)
- [`agentic-workflow.md`](agentic-workflow.md) — the agentic build loop, if you're an AI agent doing the building

**Maintainer** (deciding direction, shipping, positioning)
- [`product.md`](product.md) — the destination: what `speak` is/isn't, moats, the v0→v3+ version ladder
- [`competitors.md`](competitors.md) — Wispr Flow and category comparison, for positioning/README claims
- [`strategy-platform-ladder.md`](strategy-platform-ladder.md) — why Apple-Silicon-only *is* the strategy, and the stated trigger for reconsidering Windows/Linux
- [`release.md`](release.md) — sign/notarize/package walkthrough for `make release`
- [`human-verification.md`](human-verification.md) — the live, human-only verification checklist
- [`progress-archive.md`](progress-archive.md) — historical loop log (sessions #1–#25), archived from `progress.md`

**AI agent** (any task)
- [`agent-tooling.md`](agent-tooling.md) — the build harness: standing team, skills, MCP servers
- [`agentic-workflow.md`](agentic-workflow.md) — authority model, the work loop, model tiering

## By task

- **I want to understand the architecture** → [`architecture.md`](architecture.md)
- **I want to know what's next** → [`roadmap.md`](roadmap.md), then [`progress.md`](progress.md) for what's in flight
- **I want to run the benchmark / know if we're done** → [`benchmark.md`](benchmark.md)
- **I want to verify my work** → [`quality.md`](quality.md) (automatable) + [`human-verification.md`](human-verification.md) (live-only)
- **I want to know what `speak` is for and isn't** → [`product.md`](product.md)
- **I want to design or touch a UI surface** → [`ui/philosophy.md`](ui/philosophy.md) (the why — read first) + [`ui/foundations.md`](ui/foundations.md) (tokens/rules) + [`ui/surfaces-v0.md`](ui/surfaces-v0.md) (current) or [`ui/surfaces-future.md`](ui/surfaces-future.md) (later)
- **I want to cut a release** → [`release.md`](release.md)
- **I want to know how competitors stack up** → [`competitors.md`](competitors.md)
- **I want to know when we'd do Windows/Linux** → [`strategy-platform-ladder.md`](strategy-platform-ladder.md)
- **I want to know how agents are equipped to build this** → [`agent-tooling.md`](agent-tooling.md) + [`agentic-workflow.md`](agentic-workflow.md)
- **I'm looking for old history not in `progress.md` anymore** → [`progress-archive.md`](progress-archive.md)

## Other

- `assets/` — image/asset workspace. `hero-image-prompt.md` holds the generation prompts for all repo imagery (`docs/assets/speak-hero.png`, social card, product shot). `docs/assets/demo.gif` is still pending (referenced by the root README).
