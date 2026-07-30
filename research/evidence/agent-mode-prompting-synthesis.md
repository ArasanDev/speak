# Synthesis — Agent-Mode Prompt Optimization (SM-2), research-first

> **Research header** — Question: "how do the instruction-anatomy and small-model-eval
> pillars combine into a sequenced plan for SM-2 Agent-mode prompt optimization?" ·
> Date: 2026-06-30 · Status: **evidence** (cited by `AGENTS.md`)

> **Status**: orchestrator synthesis of two research pillars (2026-06-30). Read-only
> evidence + a PROPOSED sequenced plan. No prompts/specs/fixtures changed yet — this is
> the checkpoint artifact. Inputs: `research/coding-agent-instruction-anatomy.md` (the
> TARGET, pillarA) + `research/small-model-prompting-eval.md` (the ENGINE, pillarB).
> Every load-bearing claim below was re-verified against the code by the orchestrator.

## The frame (unchanged, now sharper)
speak's **Agent mode** turns dictated speech → a well-formed **instruction FOR a coding
agent** (Claude Code / Cursor / Aider), produced by a **small ~3B on-device model**
(Apple Foundation Models). "100% coding eval" ≠ the 3B writing code — it = the cleanup
emitting an instruction the *downstream* agent acts on correctly.

## What the two pillars independently agree on
**Fix the measurement and the metric BEFORE touching prompts.** Tuning prompts against
today's harness would optimize the wrong target. Both pillars reached this from
different directions.

---

## The three verified findings that reframe SM-2

### F1 — The live eval has NEVER run (harness env-var bug). `[verified]`
`make eval` sets `SPEAK_EVAL=1` on the **xcodebuild** process, but
`testLiveFoundationModelsEvaluation` (`EvalHarnessTests.swift:397`) reads it from the
**xctest runner** process, which doesn't inherit it (`project.yml` has no scheme
`environmentVariables` / no test plan). Result: the live Foundation Models path
**always XCTSkips**. SM-0/SM-1 "live FM eval" was never exercised — `make eval` only
ran the deterministic Mock path. This is why `verification-ledger.md` has zero measured
FM numbers despite **FM running live in the app daily** (history DB: real dictations
cleaned through ~04:38 today, `engineId apple-speech-en-US+foundation-models`,
`cleanedText ≠ rawText`, ~0.8 s). *The model works; the harness just never reached it.*

### F2 — The metric caps the pass rate, not the model or the prompt. `[verified by example]`
`EvalScoring.correctness()` = token-Jaccard ≥ 0.80 vs **one** reference. A correct
paraphrase fails:
`fix: paste not working after first dictation` vs a valid `fix: paste fails after the
first dictation` → Jaccard 0.56 → FAIL. So "chasing 100%" against this metric =
training prompts to **parrot one phrasing** (overfit + largely unreachable). Legit 100%
needs **per-category metric redesign**.

### F3 — A ~3B is a COMPOSER: preserve specifics, forbid invention. `[inferred, repo-grounded]`
All external "be specific — name the file/test/error" advice is for a *human* composing
or a *frontier* model *receiving*. Our model can only carry forward specifics the
speaker uttered; inventing a path/error/test = **hallucination that poisons the agent
with false context**. No current fixture catches this (an invented path still scores on
Jaccard). The prompt direction inverts the literature: **command preservation, forbid
invention.**

### Bonus bug — `fix` fragment contradicts its own fixture. `[verified]`
`PromptBuilder.swift:146` frames the output as `"This is a bug report … structure it
clearly."` but the `fix` fixture expects an imperative `"Fix the bug in CaptureSession…"`.
(pillarA's directional finding is correct; its verbatim quote of the fragment was
inaccurate — edit from the code.)

---

## The eval fork — resolved
- **(a) instruction-formatting quality** (well-formed instruction string, scored
  locally, deterministic, offline) → **SHIP THIS**, with the redesigned per-category
  metric (F2). This is v0.
- **(b) end-to-end** (run a real coding agent on the cleaned instruction, check the
  result) → the true north-star definition, but heavy, nondeterministic,
  frontier-agent-dependent; **defer to an opt-in `make eval-e2e` future tier**, never in
  the default local moat.

---

## PROPOSED sequenced plan (the checkpoint — nothing applied yet)

**Phase 0 — deterministic infra (no model-guessing; highest leverage; do first)**
- **0a. Fix the harness env plumbing (F1).** Add scheme `environmentVariables {SPEAK_EVAL:1}`
  (or an `.xctestplan`) so the live FM path actually runs. *Unblocks all measurement.*
- **0b. Metric redesign (F2).** `multiReference` fixtures (score = max Jaccard over a set);
  per-category structural checks (`imperativeFirstLine`, `endsWithQuestion`,
  `conventionalCommit`≤72 + allowed types, `numberedListWhenMultiItem`,
  `preservesIdentifiers:[…]`); split pass rule — **deterministic categories (code/shell/
  commit) → exact match; instruction categories (task/fix/ask) → structural + multiRef**.
- **0c. Adversarial anti-hallucination fixtures (F3).** Terse dictation → equally terse
  expected; fail any run that injects unspoken paths/identifiers/errors.
- **0d. Expand fixtures** to ~5–8/category, seeded from pillarA's `spoken→ideal` examples
  (+ the salvaged sm2 set in scratchpad).

**Phase 1 — measure (now possible; FM is live)**
- Run the live eval → write baseline per-category pass / p50 / p95 / failure modes into
  `verification-ledger.md`. *Closes the real SM-1 gap; turns `[inferred]`→`[verified]`.*

**Phase 2 — prompt deltas (gated: each must PASS the live eval, not just read well)**
- **D1 `fix`** (highest leverage + riskiest): report-framing → imperative + "don't
  prescribe the implementation." **Reverses an empirical SM-2 decision** (imperative once
  made the 3B pre-solve) — prove it on-device or revert.
- **D2 `task`**: preserve enumeration (numbered list) + stated acceptance criteria.
- **D3** cross-fragment **preserve-not-invent** guard (base prompt) (F3).
- **D4 `commit`**: annotate lowercase as house-style; optionally allow `type(scope):`.
- **D5 `code`**: inject a language signal (or restrict fixtures to language-stable
  notation) — `equalsExpected` can't match one string across languages.

**Strategic escape hatch (not v0):** if measured 3B can't hit target on the generative
categories, **Apple Core AI** (`apple/coreai-models`, macOS 27+) can host a
code-specialized small model on-device via the pluggable `LLMCleaning` seam — 100% local.
v1+ only (we target macOS 26).

## Open decisions for the human
1. **Sequencing**: do Phase 0 (infra/metric) before any prompt edits? (Strongly
   recommended — else tuning games Jaccard.)
2. **Eval fork**: confirm (a)-now / (b)-deferred.
3. **D1 risk**: OK to attempt the `fix` rewrite knowing it reverses a prior empirical
   finding and must pass live eval?
4. **Who builds it**: Phase 0 is deterministic Swift (harness + scoring + fixtures) →
   one strong agent; Phase 2 is measure-driven prompt iteration → owner with live FM.
