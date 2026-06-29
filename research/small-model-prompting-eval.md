# Small-Model Prompting + Eval for speak's Agent Mode

> **Status**: Read-only evidence (research round, 2026-06-30). Author: builder-cleanup.
> **Scope bound**: only what changes our *prompts* or our *eval*. Does NOT touch
> specs, prompts, or fixtures — every proposed change in §4 is **flagged, not applied.**
>
> **The frame** (held in every section): speak's **Agent mode** turns dictated
> speech into a well-formed **instruction FOR a downstream coding agent**, performed
> by a **small ~3B on-device model** (Apple Foundation Models). "100% coding eval"
> means the cleanup emits an instruction the *downstream* agent can act on — NOT the
> 3B model writing code. Every recommendation here must be **executable by a ~3B model**;
> frontier-only advice is rejected on sight and called out where it appears.
>
> **Tag legend**: `[verified]` = primary source (Apple docs / measured) · `[inferred]`
> = reasoned from a source but not measured on *our* device · `[decision]` = a team
> choice in the code · `[unverified]` = no primary source / not measured.

---

## 0. The one thing to read first (the reality filter)

**Foundation Models IS available and running live on the dev Mac — but the eval
harness has never actually scored it, because of a build-config plumbing bug.**
Both halves are verified primary evidence (2026-06-30):

- `[verified]` **FM runs live, daily.** The app's history DB
  (`~/Library/Application Support/speak/history.sqlite`, table `history`) shows real
  dictations cleaned by Foundation Models through ~04:38 today: `engineId =
  apple-speech-en-US+foundation-models`, `cleanedText ≠ rawText` (e.g. *"I... I think,
  uh, so I'm trying to dictate a lot."* → *"I think I'm trying to dictate a lot."*),
  `cleanupSeconds ≈ 0.79–0.85 s`. (The earlier `appleIntelligenceNotEnabled` reading
  was 2026-06-20 and is **stale** — it predates Apple Intelligence being enabled here.)
- `[verified]` **The live eval path has never run.** I executed `SPEAK_EVAL=1 make eval`
  from the repo root: `testLiveFoundationModelsEvaluation` **XCTSkipped** with
  *"Set SPEAK_EVAL=1…"*. Root cause: `make eval` sets `SPEAK_EVAL=1` on the **xcodebuild
  command line**, which xcodebuild does **not** forward into the **hosted unit-test
  process**; the guard `ProcessInfo.processInfo.environment["SPEAK_EVAL"] == "1"` sees
  `nil`. I re-ran with `TEST_RUNNER_SPEAK_EVAL=1` — **still skipped** (that prefix
  injects into the UI-test *runner*, not this hosted unit test). There is **no
  `.xctestplan`**, and the XcodeGen scheme's `test` action defines **no
  `environmentVariables`**, so the flag is never in the Test action's environment.
  `make study` (SM-1's `FoundationModelsStudyTests`, `SPEAK_STUDY=1`) has the identical
  bug — **which is exactly why `verification-ledger.md` has no measured FM numbers.**

So the gap is **narrow and fixable**, not fundamental. We are **not** tuning blind: the
app cleans text with FM every day. We simply have never captured *measured* per-category
eval numbers, because the gate that would write them silently skips. Two unblocks, both
cheap and both **flagged, not applied** here (this is a research round):
1. **Fix the harness env-var plumbing** (add `environmentVariables: { SPEAK_EVAL: "1" }`
   to the XcodeGen scheme's test action, or add an `.xctestplan`), then re-run `make eval`.
   *(build-config change — route to builder-release.)*
2. With the live path running, replace the `[inferred]` per-category quality claims
   below with `[verified]` measured numbers (pass rate, p50/p95, failure modes).

Until #1 lands, Apple's *published* facts (model size, 4096 context window, few-shot
guidance) are `[verified]`; their **measured impact on speak's instruction quality
stays `[inferred]`** — gated by a one-line build-config fix, not by hardware.

---

## 1. What a ~3B on-device model can / can't reliably do for speech→agent-instruction

Grounded in the SM-1 *intent* (measured FM limits) — but flagged where SM-1 never
actually produced a measurement (§0).

**The model (Apple Foundation Models):**
- `[verified]` **~3B parameters**, on-device, Apple-silicon + Neural Engine, offline.
  (Apple ML Research; WWDC25 s286/s248.) This is the immutable design constraint:
  "hundreds of billions of parameters" server behavior is **not** available to us.
- `[verified]` **4096-token context window**, hard. Exceeding it throws
  `GenerationError.exceededContextWindowSize`; the printed number lies but the limit
  is always 4096. macOS/iOS 26.4 adds `SystemLanguageModel.contextSize` to budget
  against it. (Apple **TN3193**; Apple Developer Forums 790736/806542.)
- `[verified]` Apple ships **Guided Generation** (`@Generable` / guided decoding) for
  constrained structured output — strings, numbers, arrays, custom structs. (WWDC25 s248/s301.)

**What ~3B can reliably do for our transform** (`[inferred]` — consistent with the
3B-class literature; NOT measured on our device):
1. **Filler removal + punctuation + capitalization** on short dictations. This is the
   `Clean`/`write` profile core and the most reliable thing a small model does — it is
   local, low-reasoning, high-frequency in instruction-tuning data.
2. **Light reformatting to a fixed shape** when the shape is named explicitly and
   demonstrated: numbered list, bullet list, `type: summary` commit line. 3B-class
   instruct models (Qwen2.5-3B, SmolLM3-3B, Phi-4-mini) are documented "few-shot
   learners" that follow a *single* explicit format. (Top-SLM-2025 survey; arXiv 2507.01810.)
3. **Verbatim preservation of spans** (identifiers, paths, flags) **when instructed
   positively** and when the span is short. This is the `Code`/`CLI`/`agent` core.
4. **One transformation per pass.** `profile-engine.md §6.3` ("one job per profile")
   is correct and matches the evidence: small models degrade sharply when asked to
   detect-intent *and* reformat *and* translate at once.

**What ~3B can't reliably do** (`[inferred]`; these are the failure modes to design
*around*, and the reason Agent mode must stay a *formatting* transform, not reasoning):
- **Multi-instruction following.** Reliability drops as the number of simultaneous
  constraints rises — measured broadly across model scales, worse the smaller the
  model. (arXiv 2509.21051 "When Instructions Multiply"; 2512.14754.) Our prompts
  that stack 4–5 clauses (preserve identifiers + convert spoken code + remove filler +
  don't explain + output-only) sit exactly in the risky zone.
- **Resisting the conversational reflex.** RLHF-tuned small models answer questions
  they were told to only reformat. The codebase already mitigates this with positive
  framing + `<transcript>` XML wrapping `[decision]` (`FoundationModelsCleaner.swift`),
  which is the right *kind* of fix — but it is **unmeasured on-device** (§0).
- **Correctness↔format gap on structured output.** Small models often produce
  *semantically* right output in the *wrong* shape (extra preamble, quotes, fences,
  a trailing "Let me know if…"). This is documented specifically at small scale.
  (arXiv 2507.01810; "When Correct Isn't Usable" 2605.02363.) It is why our
  `formatChecks` exist — and why Guided Generation (§4) is attractive.
- **Long-input fidelity.** Quality degrades with input length even below 4096 tokens;
  long rambling dictations are where a 3B model drops detail. Chunking matters
  (`profile-engine.md §6.6`).

**Frontier-trap rejections** (advice that would *not* survive on our 3B — do not adopt):
chain-of-thought / "think step by step" reasoning before answering (latency + the
model narrates its reasoning into the output); self-critique/reflection passes;
long system prompts with many conditional rules; asking the model to *choose* the
category itself rather than being handed it. All assume frontier instruction-following.

---

## 2. Prompt-construction techniques that survive ~3B (with citations)

Each is executable by Foundation Models today and consistent with both Apple's own
guidance and the 3B literature.

| Technique | Rule | Evidence |
|---|---|---|
| **Short, single-task prompts** | One job, stated as a clear command. "The model performs best given a single specific task in detail." | Apple WWDC25 s248 `[verified]` |
| **Few-shot, but <5** | 1–2 (max ~4) `spoken→written` pairs beat paragraphs of rules for a small model. Apple: "give the model **less than five examples**… write them directly into your prompt." | Apple WWDC25 s248 `[verified]`; SLM few-shot survey `[inferred]` |
| **Explicit output contract** | End every prompt with an output-only clause ("Output ONLY the result — no preamble, quotes, or explanation"). Small models chatter by default. | "Correct isn't Usable" 2605.02363 `[inferred]`; matches `profile-engine.md §6.4` |
| **Structural boundary for data** | Wrap the dictation in a delimiter (`<transcript>…</transcript>`) so the model treats it as data to edit, not a turn to answer. | codebase `[decision]`; general prompt-injection-boundary practice `[inferred]` |
| **Deterministic shape > open reasoning** | Prefer fixed structures (lists, `type: summary`) the model fills in over free reasoning it can botch. | `profile-engine.md §6.5` `[decision]`; SLM structured-output work `[inferred]` |
| **Name + demonstrate the format** | State the format AND show one example of it. Naming alone underperforms naming+example at 3B. | arXiv 2507.01810 `[inferred]` |
| **Bound input length / chunk** | Cap tokens; chunk long dictations. Core transform (system prompt + few-shot + one utterance) fits 4096 easily; `contextInputs` injection (currentFile/clipboard/long selection) is what risks overflow. | Apple TN3193 `[verified]`; impact `[inferred]` |
| **Guided Generation for structured categories** | For list/commit/structured output, constrain decoding via `@Generable` instead of hoping the model formats correctly. | Apple WWDC25 s248/s301 `[verified]`; fits structured output, **not** free-form prose |

**Two open A/B questions** the literature does *not* settle for *our* model — flag as
experiments (§4), runnable once the harness scores the live model (the §4.9 fix; FM
itself is available today, §0):
- **Negation style.** Apple says "use ALL CAPS for negations (DO NOT…)"; the codebase
  `[decision]` says positive framing + XML *beats* negation for small models. Both are
  plausible, **neither is measured on-device.** Do not adjudicate by authority — A/B it.
- **Few-shot count.** Apple says <5 helps. Optimal count *per category* (0 vs 1 vs 2 vs 3)
  is unmeasured. A/B per category against fixtures.

---

## 3. The eval fork — and why the *metric*, not the model, caps the pass rate

### Recommendation: ship (a) now; (b) is a future tier, not v0.

- **(a) Instruction-formatting quality** — expected output is a well-formed instruction
  string, scored by the harness (`SpeakCore/Eval/EvalScoring.swift`) as it works today.
  This is what we have, it is deterministic, offline, and re-runnable. **Adopt it.**
- **(b) End-to-end** — actually run a downstream coding agent on the cleaned instruction
  and check the resulting code/action. This is the right *north-star definition* of
  "the instruction made the agent succeed," but it is **heavy, nondeterministic, and
  frontier-agent-dependent** — exactly the trap the brief warns against. The judge of
  success becomes another (likely frontier) model or a code-execution harness; results
  vary run to run; it cannot gate a local `make eval`. **Defer to a future tier (§3.3).**

But "(a) as-is" is *not* the full answer, because the brief's real question is the
**path to ~100%** — and the thing capping our pass rate today is **neither the prompt
nor the 3B model. It is the metric.**

### 3.1 The Jaccard-single-reference ceiling (the key finding)

`correctness()` is token-overlap Jaccard ≥ 0.80 against **one** reference string.
A perfectly correct paraphrase from a 3B model **fails** this gate. Worked example
from our own fixtures (`eval-fixtures.json`, agent/commit):

- expected: `fix: paste not working after first dictation`
- a perfectly valid model output: `fix: paste fails after the first dictation`
- intersection = 5 tokens, union = 9 tokens → **Jaccard = 0.56 → FAILS the 0.80 gate.**

So chasing "100%" against this metric means **training the prompt to parrot one exact
phrasing** — undesirable (it overfits the prompt to the fixture) and largely
unreachable (paraphrase is correct behavior). The path to "100% coding eval" is
therefore **metric redesign per category**, not more prompt tuning:

### 3.2 Per-category metric redesign (the concrete path to a *legitimate* ~100%)

| Category | Expected output kind | Correct metric | Can 100% be legit? |
|---|---|---|---|
| `code` | exact code (`userName = getCurrentUser()`) | `equalsExpected` / normalized-exact (already used) | **Yes** — deterministic |
| `shell` | exact command (`ls -la`) | `equalsExpected` / normalized-exact (already used) | **Yes** — deterministic |
| `task` | numbered/structured plan | **structural** checks: imperative summary first line; numbered list when ≥2 items; identifiers preserved | Yes, as "100% structurally adequate" |
| `fix` | one imperative line | structural: starts-with-capital, imperative verb first, identifiers preserved; multi-reference Jaccard | Yes, as adequacy |
| `ask` | one question | structural: ends-with-`?`, identifiers preserved; multi-reference | Yes, as adequacy |
| `commit` | Conventional Commit | structural: `type(scope)?: summary`, type ∈ {feat,fix,docs,refactor,test,chore}, ≤72 chars; multi-reference | Yes, as adequacy |

The pattern: **deterministic categories → exact match (legit 100%); generative
categories → structural/rubric checks + multiple acceptable references + (optionally)
an LLM-judge adequacy score.** Then "100%" means "100% *adequate*," which is honest
and measurable, instead of "100% identical to one phrasing," which is neither.

> **Verify-before-you-build note**: before expanding fixtures, confirm a *correctly
> reworded* output would pass at 0.80. The commit example shows it does not — so the
> metric is the blocker, and metric work must land **before** prompt tuning, or SM-2
> will tune prompts to game Jaccard rather than to write better instructions.

### 3.3 Minimal sketch of (b) if/when we want end-to-end

Keep it offline-first and bounded: (1) a tiny set of `instruction → repo-fixture`
cases; (2) feed the *cleaned instruction* to a coding agent in a sandbox (e.g. a
scripted local agent or, opt-in, a cloud one — never in the default `make eval`,
never touching the moat); (3) score by a deterministic post-condition (a test passes,
a file diff matches) rather than an LLM judge where possible. This is a **separate
opt-in target** (`make eval-e2e`), gated behind a flag, explicitly outside the v0
local-only moat. Do not build it for v0.

---

## 4. Proposed deltas (flagged — NOT applied)

Bounded strictly to "changes our prompts or our eval." Each is an experiment or a
mechanical change, none is committed here.

**Eval design (the higher-leverage half — do these first):**
1. **Add a `multiReference` field to fixtures** (list of acceptable expected strings;
   score = max Jaccard over the set). Removes the single-phrasing ceiling for
   generative categories. *(eval change)*
2. **Add structural format checks** the harness lacks: `imperativeFirstLine`,
   `endsWithQuestion`, `conventionalCommit` (type ∈ allowed set, ≤72 chars),
   `numberedListWhenMultiItem`, `preservesIdentifiers:[…]`. `EvalScoring.swift` already
   has the registry pattern (`BuiltInFormatChecks`) — these are additive. *(eval change)*
3. **Split the pass rule by category**: deterministic (code/shell) → `equalsExpected`;
   generative → structural + multiReference (+ optional judge). *(eval change)*
4. **(Optional, opt-in) LLM-judge adequacy score** for generative categories, behind a
   flag, never in the default offline run. Rubric-based, single axis ("is this an
   adequate instruction for a coding agent?"), with order-shuffling to limit judge bias.
   (G-Eval / LLM-as-judge best practices, Montecarlo/Arize 2025.) *(eval change)*
5. **Per-category fixtures**: expand from 1–2 each to ~5–8 per category. The seven
   agent categories already exist in `eval-fixtures.json` (code/shell/task/fix/commit/ask);
   frame this as **expand-and-add-references**, not invent-from-scratch. *(fixture change — flagged)*

**Prompt construction (gated on the §4.9 harness fix — A/B, do not guess):**
6. **A/B negation style**: positive-framing+XML `[decision]` vs Apple's ALL-CAPS DO-NOT,
   scored on the agent fixtures. Let measurement, not authority, decide. *(prompt experiment)*
7. **A/B few-shot count per category**: 0/1/2/3 examples, pick the per-category optimum
   under the latency budget. *(prompt experiment)*
8. **Guided Generation (`@Generable`)** for the structured categories (task list,
   commit message) so format compliance is *enforced by decoding*, not hoped for.
   Caveat: fits structured output, **not** free-form prose — keep `Clean`/`write` on
   free-text. *(prompt + cleaner change — flagged)*

**Operational (the actual unblock):**
9. **Fix the eval-harness env-var plumbing** so the live FM path stops skipping (§0):
   add `environmentVariables: { SPEAK_EVAL: "1" }` to the XcodeGen scheme's `test`
   action (and `SPEAK_STUDY` for `make study`), or add an `.xctestplan`. Then re-run
   `make eval`/`make study` and write the measured numbers (per-category pass, p50/p95,
   failure modes) into `verification-ledger.md` — closing the real SM-1 gap. Until this
   lands, §4 items 6–8 cannot be evaluated and every quality claim stays `[inferred]`.
   *(build-config change — route to builder-release.)*

---

## 5. The single biggest measured-limit constraint

**It is the 3B instruction-following ceiling — unmeasured for now only because of a
build-config bug, not because FM is unavailable. Not the 4096-token window.**

- The 4096-token context window is real and `[verified]` (Apple **TN3193**), but it is
  **not binding** for the core transform: system prompt + 1–4 few-shot pairs + one
  dictation fits comfortably. It only bites under heavy `contextInputs` injection
  (`currentFile`, `clipboard`, long `selection`) — a real but secondary risk to budget
  with `SystemLanguageModel.contextSize` (26.4+).
- The **binding** constraint is the **3B instruction-following ceiling**: multi-instruction
  reliability, the conversational-reflex, and the correctness↔format gap on *our* stacked
  prompts (§1). FM is available and cleans text live (§0), so this is measurable **today** —
  the only thing in the way is the eval harness silently skipping (the env-var plumbing
  bug, §0/§4.9). So these limits are `[inferred]` *for now* but become `[verified]` the
  moment the one-line build-config fix lands and `make eval` scores the live model. We are
  **not** tuning blind — we just haven't wired the measurement gate to fire.

Everything in §3–§4 is bounded by this: we can fix the metric (deterministic, needs no
model) and design the experiments now, but we **cannot pick winning prompts until the
harness actually scores the live model.** Fixing the env-var plumbing (§4.9) is the
prerequisite for every prompt claim becoming `[verified]`.

---

## 5a. Future lever — Apple "Core AI" (`apple/coreai-models`), macOS 27+ / v1+

If the general-purpose ~3B Foundation Models model proves too weak for
coding-instruction cleanup even after prompt + metric tuning, there is a **forward
escape hatch that stays 100% on-device**: Apple's **Core AI** runtime
(`apple/coreai-models`, https://github.com/apple/coreai-models) lets you export an
arbitrary Hugging Face model to a `.aimodel` and run it on-device.

- **Strategic relevance**: a code-specialized small model (e.g. a 3B–4B code/instruct
  model) exported to `.aimodel` could be slotted behind our existing `LLMCleaning` seam
  as one more `ModelChoice.pluggable` engine — **no egress, no account, moat intact** —
  giving us a domain-specialized cleaner without abandoning local-first.
- **`[unverified]` / scope guard**: Core AI targets **macOS/iOS 27+**. speak v0 targets
  **macOS 26** and ships on Apple Foundation Models. So this is a **v1+ option, NOT a v0
  lever** — flag it, do not build it now. It also does not change any §3/§4 finding: the
  Jaccard-metric fix and the prompt experiments apply regardless of which on-device model
  backs the seam.
- **Sequencing**: only pursue if measured eval (post §4.9 fix) shows the general FM model
  *structurally* can't clear the coding categories — a bigger/specialized model is the
  last lever to pull, after metric redesign and prompt tuning, because it costs the most
  (model export, size on disk, latency).

---

## 6. Sources (URL · date · what it grounds)

Apple primary (model facts, prompting guidance, context window — `[verified]`):
- Apple ML Research, *Introducing Apple's On-Device and Server Foundation Models* — https://machinelearning.apple.com/research/introducing-apple-foundation-models (2025-06) — ~3B on-device model, architecture.
- WWDC25 s248, *Explore prompt design & safety for on-device foundation models* — https://developer.apple.com/videos/play/wwdc2025/248/ (2025-06) — "<5 examples," single-task, ALL-CAPS negation, Guided Generation.
- WWDC25 s286, *Meet the Foundation Models framework* — https://developer.apple.com/videos/play/wwdc2025/286/ (2025-06) — framework overview, on-device LLM.
- WWDC25 s301, *Deep dive into the Foundation Models framework* — https://developer.apple.com/videos/play/wwdc2025/301/ (2025-06) — Guided Generation / structured output.
- Apple Developer Technote **TN3193**, *Managing the on-device foundation model's context window* — https://developer.apple.com/documentation/technotes/tn3193-managing-the-on-device-foundation-model-s-context-window (2026) — **4096-token** window, `exceededContextWindowSize`.
- InfoQ, *Apple Improves Context Window Management for its Foundation Models* — https://www.infoq.com/news/2026/03/apple-foundation-models-context/ (2026-03) — `contextSize` property, 26.4 token budgeting.
- Apple, *Core AI models* — https://github.com/apple/coreai-models (2026) — export Hugging Face models → `.aimodel`, run on-device; macOS/iOS 27+ (grounds §5a).

Primary evidence gathered this round (live, on this Mac — `[verified]`):
- App history DB — `~/Library/Application Support/speak/history.sqlite` (queried 2026-06-30) — live FM cleanup rows (`engineId apple-speech-en-US+foundation-models`, `cleanedText ≠ rawText`, `cleanupSeconds ≈ 0.79–0.85 s`); grounds §0 "FM runs live."
- `SPEAK_EVAL=1 make eval` + `TEST_RUNNER_SPEAK_EVAL=1` runs (2026-06-30) — `testLiveFoundationModelsEvaluation` XCTSkipped both times; `Makefile` `eval`/`study` targets + XcodeGen `project.yml` scheme (no `environmentVariables`, no `.xctestplan`); grounds §0/§4.9 the env-var plumbing bug.
- Apple Developer Forums 790736 / 806542 — https://developer.apple.com/forums/thread/790736 — 4096 limit behavior, printed-number caveat.

Small-model prompting + structured-output + instruction-following literature (`[inferred]`):
- *Top Small Language Models in 2025* (Qwen2.5-3B, SmolLM3-3B, Phi-4-mini) — https://peaklightai.medium.com/top-small-language-models-in-2025-your-complete-guide-85a0de4fefe7 (2025) — 3B-class capabilities, few-shot.
- *Evaluating Structured Output Robustness of Small Language Models*, arXiv 2507.01810 — https://arxiv.org/html/2507.01810v1 (2025-07) — small-model format compliance, naming+example > naming.
- *When Correct Isn't Usable: Structured Output Reliability in Small LMs*, arXiv 2605.02363 — https://arxiv.org/html/2605.02363 (2026) — correctness↔format gap, output-only contract.
- *When Instructions Multiply*, arXiv 2509.21051 — https://arxiv.org/pdf/2509.21051 (2025-09) — multi-instruction following degrades, worse at small scale.
- *Revisiting Reliability of LMs in Instruction-Following*, arXiv 2512.14754 — https://arxiv.org/pdf/2512.14754 (2025-12) — instruction-following reliability.
- *Zero-Shot and Few-Shot Learning Techniques* — https://www.rohan-paul.com/p/zero-shot-and-few-shot-learning-techniques (2025) — few-shot for small models.

Eval methodology (LLM-as-judge / rubric — grounds §3.3, §4.4 `[inferred]`):
- *LLM-As-Judge: 7 Best Practices & Evaluation Templates*, Monte Carlo — https://montecarlo.ai/blog-llm-as-judge/ (2025) — judge rubric design.
- *Rubric-Based Evaluations & LLM-as-a-Judge* (G-Eval lineage) — https://medium.com/@adnanmasood/rubric-based-evals-llm-as-a-judge-methodologies-and-empirical-validation-in-domain-context-71936b989e80 (2025) — rubric scoring, order-shuffle bias mitigation.
- *When "Better" Prompts Hurt: Evaluation-Driven Iteration*, arXiv 2601.22025 — https://arxiv.org/html/2601.22025v1 (2026) — generic-vs-task-specific prompt tradeoff; reproducible local eval.
- Arize, *LLM as a Judge — Primer and Pre-Built Evaluators* — https://arize.com/llm-as-a-judge/ (2025) — judge evaluators.
</content>
</invoke>
