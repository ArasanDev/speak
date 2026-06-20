# Plan: Wispr Flow Parity Map + Consolidated Human Spec for `speak`

> **Plan type**: enhancement (verified benchmark) + chore (doc synthesis)
> **Complexity**: complex (external verification + definition-of-done + synthesis)
> **Outputs**:
>   1. `docs/benchmark.md` — verified Wispr Flow parity map = the agent's
>      testable **definition of done** (agent-facing).
>   2. `SPEC.md` — human-readable consolidated product spec (sharing/onboarding).
> **Date**: 2026-06-20

---

## Task Description

`speak` is a pre-build, macOS-native, local-first, free, open-source voice
dictation app. Its `docs/` set is already agent-ready (the `AGENTS.md` operating
loop + 5 role-separated docs), but two things are missing for the stated goal —
*"the final product has to be as good as Wispr Flow"*:

1. There is **no concrete, verified definition of "as good as Wispr Flow."** The
   docs have a thin, unverified differentiation matrix, but nothing an agent can
   build *toward* and test *against*. "Be Wispr Flow" is not a buildable target;
   a feature-by-feature parity checklist is.
2. The product knowledge is **AI-ideated and split across 16 files** with no
   single human-readable reference for sharing/onboarding/pitching.

### Decisions confirmed with the user (2026-06-20)

- **Artifact philosophy**: for AI-agent development the right artifact is a
  *spec*, not a PRD — and specifically the **layered, per-task-loadable `docs/`
  loop**, which the project already has. We do NOT replace it.
- **Primary deliverable**: a **Wispr Flow parity map** added to `docs/` as the
  agent's definition of done. Verify Wispr's *actual current* feature set
  (not the model's memory). Fold in the foundational claim-verification.
- **Secondary deliverable**: keep `docs/` as the agent source of truth, AND
  generate one **human-readable `SPEC.md`** consolidating everything.

### The framing that makes "done = Wispr Flow" correct (not impossible)

`speak`'s moat is **local + free + open**. It is deliberately NOT a cloud app.
So the parity map must sort every category capability into **three buckets**,
not one:

- **MATCH** — core dictation experience `speak` must equal to be credible
  (transcription accuracy/latency, paste reliability, hotkey ergonomics,
  streaming overlay, app compatibility).
- **BEAT** — where `speak` wins by design (100% local, $0, MIT open source,
  no account/telemetry, SpeechAnalyzer-native).
- **SKIP (by design)** — features that require the cloud or are off-strategy
  (cloud sync, server-side AI commands, cross-device account) — each with a
  one-line "why not / where it could go later."

"Definition of done" = all MATCH rows pass + all BEAT rows hold + all SKIP rows
are consciously documented. This keeps the bar high *and* on-strategy.

### Three refinements from the 2026-06-20 discussion (load-bearing)

1. **Whole category, Wispr as the frontier.** Benchmark the *entire* advanced
   voice-dictation category (Wispr Flow, Superwhisper, Willow, MacWhisper,
   VoiceInk, FluidVoice, Aiko, TypeWhisper, …), not Wispr alone. Wispr is the
   **frontier reference** (most advanced, limit-pushing) so it sets the bar;
   the others reveal where the category as a whole is, and where `speak` can
   leapfrog. The benchmark snapshot is category-wide; the MATCH gate is set by
   the frontier.

2. **Capture the FULL vision — "the true speak" — then phase it.** The
   benchmark/spec describes the complete north-star product (what a category-
   leading `speak` looks like at full maturity), then assigns each capability a
   delivery phase (v0 / v0.1 / v1 / v2+). The vision is never shrunk to v0; v0
   is the *first credible slice* of the full thing. The loop builds toward the
   north star, not just the v0 checklist.

3. **No hardcoding — every value must trace to evidence or a decision.** The
   current docs carry arbitrary AI-ideated constants (400ms double-tap window,
   "last 50" history, 16-app matrix, latency budgets) with no stated *why*.
   These are **defects, not spec.** In the new artifacts every number derives
   from one of: (a) a measured/verified competitor value, (b) a cited platform
   constraint, or (c) an explicit `[decision]` with rationale. A bare constant
   with no upward trace fails review. Each value lives in **one** source-of-truth
   location; everywhere else references it (no duplicated magic numbers to drift).

### The loop's terminal success signal

The autonomous build loop (`/goal` + `/loop`, per `AGENTS.md` §4) does **not**
terminate on "P0–P14 checked." Its done-condition is the **benchmark
comparison**: all MATCH-gate rows pass *measured against the frontier* and all
BEAT claims hold. `docs/benchmark.md` is therefore the loop's objective function
and reward signal — the single thing each cycle is evaluated against.

---

## Objective

When complete, the repo contains:

- `docs/benchmark.md`: a feature-by-feature Wispr Flow ↔ `speak` parity map.
  Every row is a **MATCH / BEAT / SKIP** bucket with a **binary, testable**
  acceptance criterion for the MATCH rows (the agent's v0 done-gate), each Wispr
  fact tagged `[verified]`/`[inferred]`/`[unverified]` with a source.
- `SPEC.md` (repo root): a single human-readable spec consolidating product,
  market, UX, architecture, privacy, roadmap, risks, GTM, and the parity map.
- `specs/verification-ledger.md`: every load-bearing external claim (Wispr
  features + Apple platform + competitors) → verdict → source → correction.
- `docs/` build loop preserved; any correction forced onto the immutable
  `product.md` is deferred to the human via a corrections appendix.

---

## Problem Statement

- **No testable target.** An autonomous agent following `roadmap.md` can build
  P0–P14, but nothing tells it *"this is the quality/feature bar that means we
  shipped a real Wispr Flow alternative."* Without it, "done" is the roadmap's
  mechanical checklist, not a competitive product.
- **The bar itself is unverified.** The current Wispr Flow facts in the docs
  ($15/mo, "polishing not shipping in 2026", platform expansion) were generated
  by an open-source model. If they're stale or wrong, the parity map is built on
  sand — and so is the "why now" thesis.
- **Foundational tech claims unverified.** Same risk on `SpeechAnalyzer` /
  macOS 26 / paste protection (`architecture.md` §14). These gate whether the
  app can match Wispr's *latency and accuracy* at all.

## Solution Approach

Three-stage pipeline:

1. **Verify** (parallel) — (a) deep-research Wispr Flow's real current product;
   (b) verify the foundational Apple-platform claims; (c) verify the rest of the
   competitor matrix. Output: one Verification Ledger.
2. **Author the parity map** — a senior agent writes `docs/benchmark.md` from
   the verified Wispr feature set, sorting every capability into MATCH/BEAT/SKIP
   with testable criteria for MATCH rows.
3. **Author the human spec + review** — consolidate everything into `SPEC.md`
   (embedding the parity map), then adversarially review both new artifacts
   against the ledger.

---

## Relevant Files

- `AGENTS.md` — operating manual + hard constraints §2 (local/free/open moat).
  The parity map's BEAT bucket = these constraints made competitive. A new
  `docs/benchmark.md` should be added to the navigation table (§1) — a
  structural doc change, so flag for human approval.
- `docs/product.md` — differentiation matrix (§5), personas (§3), moats,
  scope-by-version (§8). Human-only edits → corrections go to the appendix.
- `docs/architecture.md` — §12 performance budgets (the latency bar for MATCH
  rows) + §14 claims-to-verify (foundational verification seed).
- `docs/roadmap.md` — P0–P14; `docs/benchmark.md` becomes the cross-cutting
  done-gate referenced at the v0 ship gate.
- `docs/quality.md` — §3 cross-app compatibility matrix + §8 risk register
  (Risk 1: SpeechAnalyzer WER vs Wispr; Risk 7: Wispr copies local-first) +
  §9 ship checklist. The parity map's MATCH criteria slot alongside these.
- `docs/progress.md` — current state (pre-build) + open questions.
- `research/CATEGORY_LANDSCAPE.md`, `research/SPEAK_DICTATION_STACKS.md` —
  competitor + market depth to mine for the matrix and `SPEC.md`.
- `research/SPEAK_PRODUCT_SPEC.md`, `research/spec.md`,
  `research/OPUS_BUILD_PROMPT.md` — prior spec attempts; mine for any Wispr
  detail or GTM content the docs dropped.
- `README.md` (root) — public positioning; keep consistent with `SPEC.md`.

### New Files
- `docs/benchmark.md` — **primary deliverable**: the verified Wispr parity map.
- `SPEC.md` — **secondary deliverable**: human-readable consolidated spec.
- `specs/verification-ledger.md` — working artifact: claims → verdicts → sources.

---

## Implementation Phases

### Phase 1: Verify (parallel) — establish the real bar
Three independent research streams: Wispr Flow's actual current product; the
foundational Apple-platform claims; the rest of the competitor matrix. No
authoring until the bar is real.

### Phase 2: Author the parity map (the definition of done)
Write `docs/benchmark.md` from verified data — MATCH/BEAT/SKIP buckets, testable
criteria on MATCH rows. This is the agent-facing primary output.

### Phase 3: Consolidate + review
Write the human-readable `SPEC.md` (embedding the parity map), then
adversarially review both new artifacts against the Verification Ledger.

---

## Orchestration & Attention Strategy (the orchestrator's self-prompt)

> This section is the orchestrator's operating contract for *this* plan. With
> 16+ overlapping, AI-ideated source files, the binding constraint is **finite
> attention**, not missing information. These rules keep the right things in the
> right context at the right time.

1. **Orchestrator holds the map, not the territory.** The orchestrator's context
   = `AGENTS.md` + `progress.md` + a one-line index of every other file + the
   live decision/verification ledger. The ~4,300 lines of `research/` and the
   full `docs/` bodies are **never loaded into the orchestrator** — they are
   routed as slices to sub-agents. Orchestrator attention is spent on routing,
   integration, and conflict resolution.

2. **One agent / one slice / one question.** Every sub-agent brief carries (a)
   the *minimum* file set it needs, (b) a single sharp question, (c) the output
   schema. No "read everything and figure it out." Concentrated attention →
   higher fidelity. (Charter principle #5.)

3. **Evidence → decision → derived-value, enforced in every brief.** Sub-agents
   are instructed that any number they emit must trace upward (measured value /
   platform constraint / `[decision]` + rationale). Orphan constants are flagged,
   not propagated. This is how "no hardcoding" is enforced operationally, not
   just aspirationally.

4. **The benchmark is the shared attention anchor.** Every authoring/review
   brief references one question — *"match or beat the frontier on this
   dimension?"* — rather than a sprawl of criteria. This is also the loop's
   reward signal downstream.

5. **Verify-then-attend.** Unverified claims are quarantined (`[unverified]`)
   and never handed to an author as ground truth. The Verification Ledger gates
   what the authors are allowed to treat as real.

6. **Write for cold re-entry.** Because `/loop` reloads fresh context each cycle,
   every artifact (`benchmark.md`, `progress.md`, the ledger) must let a
   zero-context agent reconstitute state in one skim: state at top, decisions
   logged with rationale, no implicit context. Writing for future-me's limited
   attention is part of the deliverable, not a nicety.

7. **Single source of truth per fact.** Each value/decision lives in exactly one
   place; all other references point to it. Minimizes both contradiction surface
   and re-read cost.

---

## `docs/benchmark.md` outline (authoring contract)

1. **Purpose** — "the testable definition of done: a real, category-leading
   local dictation app." How to read MATCH/BEAT/SKIP and the phase column.
2. **Category snapshot (verified)** — a short table across the whole category
   (Wispr Flow, Superwhisper, Willow, MacWhisper, VoiceInk, FluidVoice, Aiko,
   TypeWhisper, …): price, platforms, local/cloud, open-source, standout
   capability — each cell tagged + sourced. **Wispr Flow row is the frontier
   reference** that sets the MATCH bar.
3. **The parity matrix (north-star, then phased)** — one row per capability,
   columns:
   `Capability | Frontier behavior (Wispr) | Category norm | speak north-star
   target | Bucket (MATCH/BEAT/SKIP) | Phase (v0/v0.1/v1/v2) | Binary
   acceptance criterion | Source/derivation`.
   The matrix captures the **full vision** (every capability of the mature
   product); the Phase column sequences it. Capability families: transcription
   accuracy, latency, languages, hotkey/activation, streaming UI,
   paste/insertion reliability, app compatibility, text cleanup/formatting,
   voice commands/editing, dictionary/snippets, history, settings, onboarding,
   privacy posture, price, platform, distribution, extensibility.
4. **v0 MATCH gate** — the phase-v0 subset that MUST pass to ship a credible
   first slice (e.g. "median end-to-end latency ≤ frontier's *measured* latency
   × tolerance" — the tolerance is a `[decision]` with rationale, not a
   hardcoded number; "paste works in ≥ N/M apps" where N/M is *derived* from the
   compatibility study, reconciled with `quality.md` §3/§9).
5. **BEAT claims** — local/free/open/privacy, each with the "the cloud
   incumbents can't copy this without abandoning their revenue model" rationale.
6. **SKIP (by design)** — cloud-dependent / off-strategy features + why-not +
   possible future home (v1+ opt-in).
7. **Quality benchmark protocol** — how to *measure* WER and latency vs the
   frontier (test corpus, quiet/noisy, device set), so MATCH rows are verified
   empirically, not asserted. Ties to the Risk-1 decision rule in `quality.md`.
8. **Derivation ledger** — for every numeric target in the matrix, its source:
   measured value / platform constraint / `[decision]`+rationale. No orphan
   constants. (This is the anti-hardcoding artifact.)

**Tagging**: every competitive fact is `[verified]` (sourced), `[inferred]`, or
`[unverified]`. No untagged competitive claims; no untraced numbers.

---

## Load-bearing claims to verify (Phase 1 backlog)

**Stream A — Wispr Flow (assigned: verifier-wispr)** — the parity baseline:
- Current pricing & plans (the doc says $15/mo — confirm; check free tier).
- Platforms supported now (Mac/Windows/Linux/iOS) + the "expanding to
  Windows/Linux in 2026" claim.
- Core feature set: activation/hotkey model, languages, streaming, text
  cleanup/AI editing, commands, accuracy claims, latency claims, app
  integrations, history/sync, account model.
- Recent release direction (the "polishing not shipping features, March 2026 =
  notification UI + sleep recovery" claim) — verify or downgrade to `[inferred]`.
- Source: wisprflow.ai, its changelog/release notes, app store listing, recent
  reviews. Flag any suspiciously specific dated claim.

**Stream B — Apple platform (assigned: verifier-apple)** — make-or-break:
- `SpeechAnalyzer` exists, on-device, macOS 26+, Apple Silicon, API shape +
  partial/final results + locales. (developer.apple.com, WWDC25 session 277.)
- macOS 26 exists / shipped ~2025-Q4 / marketing name / API availability.
- macOS 26.4 **Paste Protection**: prompts on *read*, not write; the
  write+`Cmd+V` approach avoids it. (Treat the cited "Michael Tsai blog
  2026-04-09" as suspect; confirm from a primary source or mark `[unverified]`.)
- `CGEventTap` permission requirements; Fn = `kVK_Function`.
- Source latency/accuracy data if available (to set MATCH latency bar).

**Stream C — competitor matrix (assigned: verifier-competitors)** — context:
- Superwhisper ($9.99/mo), Aiko (free), VoiceInk (GPL), FluidVoice (GPL,
  pluggable engines), MacWhisper, TypeWhisper, Willow — existence + current
  price/license/local claims. WhisperKit repo + license. Ollama models.
- Source: each product's site / GitHub / store listing.

Shared ledger schema: `claim | verdict (confirmed/corrected/refuted/unverifiable)
| source URL | correction text`.

---

## Team Orchestration

- You operate as the team lead; you NEVER touch the codebase directly. Deploy
  members via `Task`/`Task*` tools and coordinate.
- No `.claude/agents/team/` roster exists here → all members are
  `general-purpose`, differentiated by role + model tier (charter routing).
- Record each member's agentId to resume with context.

### Team Members

- Builder
  - Name: **verifier-wispr**
  - Role: Deep-research Wispr Flow's actual current product (Stream A) — the
    parity baseline. Produces the Wispr section of the Verification Ledger.
  - Agent Type: `general-purpose`
  - Model: `sonnet` (judgment-heavy web research across changelog/reviews)
  - Resume: true

- Builder
  - Name: **verifier-apple**
  - Role: Verify foundational Apple-platform claims (Stream B).
  - Agent Type: `general-purpose`
  - Model: `sonnet`
  - Resume: true

- Builder
  - Name: **verifier-competitors**
  - Role: Verify the rest of the competitor/library matrix (Stream C).
  - Agent Type: `general-purpose`
  - Model: `haiku` (mostly fact-lookup against product pages/repos)
  - Resume: true

- Builder
  - Name: **author-benchmark**
  - Role: Write `docs/benchmark.md` — the MATCH/BEAT/SKIP parity map with
    testable MATCH criteria. The primary deliverable; hardest judgment.
  - Agent Type: `general-purpose`
  - Model: `opus`
  - Resume: true

- Builder
  - Name: **author-spec**
  - Role: Write the human-readable `SPEC.md`, embedding the parity map and
    consolidating the rest of the product story.
  - Agent Type: `general-purpose`
  - Model: `opus`
  - Resume: true

- Builder
  - Name: **reviewer**
  - Role: Adversarially fact-check both new artifacts against the ledger; verify
    bucket logic, testability of MATCH rows, tagging, no `docs/` violations.
  - Agent Type: `general-purpose`
  - Model: `sonnet`
  - Resume: true

---

## Step by Step Tasks

- Run `TaskCreate` for the full list first so all members see it.

### 1. Verify Wispr Flow's current product
- **Task ID**: verify-wispr
- **Depends On**: none
- **Assigned To**: verifier-wispr
- **Agent Type**: general-purpose
- **Parallel**: true
- Research and record (with sources) Wispr's current price/plans, platforms,
  full core feature set, accuracy/latency claims, and recent release direction.
- Verify or downgrade the "$15/mo" and "polishing not shipping in 2026" claims.
- Output: Wispr section of `specs/verification-ledger.md`.

### 2. Verify foundational Apple-platform claims
- **Task ID**: verify-apple
- **Depends On**: none
- **Assigned To**: verifier-apple
- **Agent Type**: general-purpose
- **Parallel**: true
- Verify Stream-B claims (SpeechAnalyzer, macOS 26/26.4 paste, CGEventTap).
- Treat the "Michael Tsai blog 2026-04-09" citation as suspect; confirm from a
  primary source or mark `[unverified]`.
- Output: Apple section of the ledger. **If `SpeechAnalyzer` or macOS 26 facts
  don't hold, STOP and surface — this invalidates the product thesis.**

### 3. Verify competitor & library matrix
- **Task ID**: verify-competitors
- **Depends On**: none
- **Assigned To**: verifier-competitors
- **Agent Type**: general-purpose
- **Parallel**: true
- Verify Stream-C product/library facts (price/license/local + WhisperKit repo
  + Ollama models). Output: competitor section of the ledger.

### 4. Author the Wispr parity map
- **Task ID**: author-benchmark
- **Depends On**: verify-wispr, verify-apple, verify-competitors
- **Assigned To**: author-benchmark
- **Agent Type**: general-purpose
- **Parallel**: false
- Write `docs/benchmark.md` per the outline above, using ONLY verified ledger
  facts. Every MATCH row gets a binary acceptance criterion; reconcile MATCH
  gates with `quality.md` §3/§9 and `architecture.md` §12 (don't duplicate —
  cross-reference). Tag every competitive fact.
- Add a line noting `docs/benchmark.md` should be registered in `AGENTS.md` §1
  navigation (structural change → flag for human, do not edit `product.md`).

### 5. Author the consolidated human spec
- **Task ID**: author-spec
- **Depends On**: author-benchmark
- **Assigned To**: author-spec
- **Agent Type**: general-purpose
- **Parallel**: false
- Write `SPEC.md` (root): vision, problem/why-now, market & competitive
  landscape (embedding the parity map), personas, product/UX, architecture
  summary (reference signatures, don't duplicate), privacy, scope/roadmap,
  risks, distribution/GTM, open questions, verification-ledger summary, and a
  "required `docs/` corrections" appendix. Single voice; every claim tagged.

### 6. Adversarial review & fact-check
- **Task ID**: review-artifacts
- **Depends On**: author-benchmark, author-spec
- **Assigned To**: reviewer
- **Agent Type**: general-purpose
- **Parallel**: false
- Verify: every competitive claim resolves to a ledger entry; every MATCH row is
  binary-testable; bucket assignments are defensible; all sections present; no
  untagged facts; `docs/product.md` (and other `docs/`) unmodified. Produce a
  blocking/nit defect list; blocking → resume the relevant author to fix.

### 7. Final validation
- **Task ID**: validate-all
- **Depends On**: verify-wispr, verify-apple, verify-competitors,
  author-benchmark, author-spec, review-artifacts
- **Assigned To**: reviewer
- **Agent Type**: general-purpose
- **Parallel**: false
- Run the Validation Commands; confirm Acceptance Criteria. Report counts:
  Wispr features mapped, MATCH/BEAT/SKIP split, claims verified vs corrected vs
  `[unverified]`, blocking defects remaining (must be 0).

---

## Acceptance Criteria

- [ ] `docs/benchmark.md` exists: a category-wide snapshot (Wispr as frontier),
      every capability sorted MATCH/BEAT/SKIP **with a delivery phase** so the
      full north-star vision is captured and sequenced (not shrunk to v0); every
      MATCH row has a binary acceptance criterion; every competitive fact tagged
      with a source.
- [ ] **No orphan constants**: every numeric target in `benchmark.md` (and any
      number the artifacts introduce) traces to a measured value, a cited
      platform constraint, or a `[decision]` + rationale in the derivation
      ledger. The reviewer fails the artifact on any untraced magic number.
- [ ] The MATCH gate is internally consistent with `quality.md` §3/§9 and
      `architecture.md` §12 (no contradictory numbers).
- [ ] `SPEC.md` exists, embeds the parity map, and is single-voice + fully
      tagged.
- [ ] `specs/verification-ledger.md` covers all Stream A/B/C claims with
      verdict + source.
- [ ] No claim survives as `[verified]` without a real primary source; failures
      corrected or downgraded.
- [ ] `docs/` files (esp. `product.md`) are unmodified; corrections (if any)
      live in the `SPEC.md` appendix + a flagged `AGENTS.md` nav addition.
- [ ] Reviewer's blocking-defect count = 0.

## Validation Commands

- `ls -1 docs/benchmark.md SPEC.md specs/verification-ledger.md` — artifacts exist.
- `grep -niE 'MATCH|BEAT|SKIP' docs/benchmark.md | wc -l` — bucket rows present.
- `grep -nE '\[verified\]|\[inferred\]|\[unverified\]' docs/benchmark.md | wc -l`
  — competitive facts are tagged (non-zero).
- `grep -ni 'michael tsai\|argmax-oss-swift' docs/benchmark.md SPEC.md specs/verification-ledger.md`
  — suspect citations were verified-or-downgraded, not copied through.
- `ls -la --time-style=+%s docs/product.md` (or `stat -f '%m' docs/product.md`)
  — confirm `product.md` mtime unchanged across the run (docs/ untouched).
  *(Repo not git-initialized; if `git init` is run first, use
  `git status --porcelain docs/` → expect no output.)*

## Notes

- **No code / no build toolchain** — documentation + web verification only.
- **Strategic guardrail**: "done = Wispr Flow" must never push the SKIP-bucket
  cloud features into v0 — that would trade away the local/free/open moat
  (`AGENTS.md` §2). The author keeps cloud-dependent parity in SKIP with a
  v1-opt-in note, not MATCH.
- **Escalation**: if Wispr's real product differs materially from the docs'
  assumptions (e.g., it added a free local tier, or dropped to a far lower
  price), the parity map's strategy section must surface it — it may shift
  positioning, not just a row.
- **After this plan**: the recommended build path is unchanged — `git init` +
  confirm Xcode toolchain (`progress.md` open question #1), then roadmap P0,
  now with `docs/benchmark.md` as the v0 done-gate.
