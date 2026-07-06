# Constraint Split for Agent dictations: CS-1 rejected → CS-2 architecture validated, parked

> **Status**: `[decision 2026-07-06]` CS-1 (single-prompt) explored, measured, **rejected**
> (over-trigger). CS-2 (two-pass) built and measured: **architecture validated, but not
> shipped** — blocked by on-device 3B extraction *fidelity*, not by the design. Revisit when
> a stronger local model is available (WWDC26 provider API). Full arc below.
> WHY this lives here: `research/` is read-only evidence; this is a design + a measured
> engineering decision for a v-next task.

---

## The idea (converged from a 3-pass Fable design exploration)

`speak` is becoming "the input layer for the agentic era" (`product.md §6c`). A spoken
instruction to a coding agent buries its **exclusions** mid-sentence ("add the button but
**don't touch the database** and make sure tests still pass"), where both the agent and the
speaker reviewing the paste can miss them. Two independent creative lenses — a UX lens
("The Seal + DON'T slot") and an intelligence lens ("Constraint Split") — converged on the
same mechanism: split **action** from **hedges**, surfacing prohibitions as an explicit
trailing `Constraints:` segment in the Agent output.

Design shape explored (CS-1, single-prompt): one shared `constraintClause` appended to the
`.task` and `.fix` `AgentCategory` fragments in `PromptBuilder`, with a symmetric contract
("emit exactly when a restriction was stated; otherwise add nothing"), plus two rubric
checks (`hasConstraintsBlock`, `noConstraintsBlock`) and golden fixtures.

---

## What the live eval measured (Foundation Models on-device 3B, greedy/deterministic)

Baseline (master): **Agent 97.39%**, 16/17 fixtures pass (the one pre-existing failure is an
unrelated `ask` case that answers instead of preserving the question).

| Iteration | Agent score | Outcome |
|---|---|---|
| Baseline (no CS-1) | **97.39%** | 16/17 pass |
| CS-1 v1 (symmetric contract, newline block) | 87.40% | regression |
| CS-1 v2 (trigger-word list, inline-accepting check) | 85.71% | worse regression |

### Root cause — the labeled block is net-negative on this model

1. **`.fix` over-triggers (real product regression, not a rubric artifact).** On hedge-free
   inputs the model invents/restates a constraint — e.g. `fix the paste bug` →
   "… Constraints: **Must still fix the bug.**" In v2 the model echoed the clause's own
   trigger words ("must still"). This is genuinely worse text to paste into an agent.
2. **`.task` under-labels.** The model *does* preserve the exclusions — but as plain
   trailing imperatives ("Do not touch the existing theme constants. Make sure the tests
   still pass."), **not** under a `Constraints:` label. The guardrails were never lost.
3. **The premise is partly false for this profile.** The base Agent prompt *already*
   preserves prohibitions as explicit sentences (the untouched `UserService` fixture keeps
   "maintain the public interface" at baseline). Forcing a **label** adds little and costs
   over-triggering. CS-1 also violated the small-model "one job per prompt" rule by asking
   the cleanup prompt to both rewrite the task **and** split constraints.

Guards were deliberately **not** loosened to hide the `.fix` over-trigger — that would game
the measurement against this project's "tuned by measurement, not opinion" ethos.

---

## Re-scoped next step (v-next, not a prompt-only slice)

The UX lens's original form is the one that respects the small-model rule: a **separate,
one-job extraction pass** — a second inference ("List ONLY explicit prohibitions the speaker
stated, each as one line; if none, output NONE"), run alongside cleanup, whose non-NONE
output is appended as a labeled block and shown as a distinct DON'T slot in the overlay.
One job per call; degrades cleanly on NONE/parse-failure.

---

## Resolution — CS-2 (two-pass): architecture validated, parked `[decision 2026-07-06]`

Built the two-pass form **inside `FoundationModelsCleaner`** (not `CaptureSession`, so the
eval harness measures it directly). Three ingredients made it robust where CS-1 failed:

1. **Deterministic prohibition-marker pre-gate** (`hasProhibitionMarker`, pure Swift). The
   extraction model is invoked ONLY when the raw transcript contains an explicit marker
   (`don't`, `do not`, `without`, `leave … alone`, `keep unchanged`, `must still`, `still
   pass`, `backwards compatible`, …). Hedge-free dictations never reach the model, so it
   **cannot over-trigger** — the exact failure that sank CS-1 is structurally impossible,
   not merely discouraged. Also skips the second inference on the common case (latency).
2. **One-job extraction session.** On gated-in input, a fresh `LanguageModelSession` whose
   only job is: list explicit restrictions separated by `; `, else output `NONE`. Restriction/
   extraction is what small models do well; `NONE` is an easy, explicit exit.
3. **Deterministic Swift formatting** (`mergeConstraints`, pure). The model returns only the
   list; Swift owns the label + trailing-block form (`…task.\n\nConstraints: a; b`). This
   sidesteps CS-1's other failure — the 3B wouldn't reliably emit the `Constraints:` label
   or a newline. Any extraction error/timeout ⇒ `cleaned` unchanged (a missing block never
   costs a dictation). Gated to Agent `.task`/`.fix`; every other path is byte-identical.

### What CS-2 solved — and what it didn't (honest measured result, live eval, 3B, greedy)

**Solved (validated):**
- **Over-triggering — completely.** The deterministic pre-gate means hedge-free dictations
  never reach the extraction model. Every hedge-free negative fixture appends no block. CS-1's
  fatal flaw is structurally impossible here.
- **Formatting.** Swift owns the label + trailing-block form deterministically.
- **Pareto-safe on recall (proven).** CS-2 never touches the cleanup body — `clean()` runs the
  unchanged cleanup prompt, then *appends*. Proof: the original 17 fixtures score **identically
  to baseline** (16/17, same pre-existing `ask` failure — zero regression). So when extraction
  drops a constraint, output == baseline (no worse); when it succeeds, a constraint the body
  lost is recovered (better). The only worse-than-baseline path is hallucination.
- **Latency.** p50 0.437 s vs 0.415 s baseline — the pre-gate skips the second call on the
  common (markerless) case; p95 0.973 s includes the triggered cases, under budget.

**The blocker — 3B extraction fidelity (why it is parked):**
- **Recall is ~50% and unstable** on multi-constraint inputs. With honest `preservesTerms`
  content assertions on the 4 positives, only 2 of 4 pass. HotkeyMonitor — a *single*
  constraint — extracted correctly in one run and dropped entirely in the next after a minor
  prompt tweak. One tuning change fixed `migrate`'s hallucination but broke HotkeyMonitor
  (whack-a-mole on a model that can't be grid-searched).
- **Non-zero fabrication path.** One run produced `keep the public API unchanged` for a
  dictation that said "keep it backwards compatible" — a fabricated guardrail, which for a
  coding agent is actively harmful.
- A guardrail feature's whole value is trust. ~50% recall + a fabrication path fails that bar
  *regardless* of Pareto-safety. "Never worse than baseline" is not the bar for "never lose
  your guardrail." So it is **not shipped enabled.**

Numbers seen across runs (97.98% structural-only / 91.92% content-honest) are NOT "the model
got better/worse at its job" — they are the new fixtures entering/leaving the mean. The honest
one-line result: *original 17 non-regress; over-trigger solved; new-capability content correct
on 2 of 4 hard cases, unstable.*

### Revisit trigger
The two-pass **architecture is validated and reusable** — deterministic pre-gate + one-job
extraction + Swift formatting + graceful degrade. Only model fidelity blocks. Re-enable when a
stronger on-device model is available (WWDC26 `LanguageModelSession` provider API, V1-13, or a
larger local model). At that point the wiring is a small re-apply; the eval fixtures + honest
content checks are the ready-made acceptance gate. The **overlay DON'T-slot** (the UX lens's
steerable chip) is the natural UI layer once fidelity clears the bar.

### Optional interim (user's call)
Because CS-2 is Pareto-safe-on-recall, it *could* ship **disabled by default** as a best-effort
surfacer (never worse than baseline; occasionally recovers a guardrail). That trades a settings
flag + a non-zero fabrication risk for opportunistic recall. Recommendation: **park** until
fidelity is trustworthy rather than ship a half-reliable guardrail. Left to the human.
