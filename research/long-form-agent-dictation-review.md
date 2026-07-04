# Long-form agentic dictation — prompt-optimization review (2026-07-04)

> Read-only evidence + decision record for the change landed this loop to
> `DefaultProfiles.agent.systemPrompt`. All numbers below are LIVE Foundation Models
> runs on this dev Mac (Apple Intelligence enabled, greedy decoding — same plumbing
> as `research/fix-fragment-ab-result.md`), not simulated.

## The question
Production's Agent system prompt hardcoded **"Remove filler. 1–3 sentences maximum."**
That cap was never validated against the actual medium this product exists for: a
developer thinking out loud to an agentic coding tool — ideation, brownfield context,
multi-step asks, debugging narratives, course-corrections. Typed input is naturally
compressed (typing is effortful); spoken input naturally carries far more — reasoning,
rejected alternatives, scope, hedges. A fixed sentence cap throws that away regardless
of whether the content was worth keeping. The `fix`/`shell`/`code`/`commit` Agent
sub-categories are a genuinely different, terse medium (single spoken micro-command)
and were correctly left untouched — this review is scoped to the `task`/`ask` path,
which carries all long-form reasoning dictation.

## Method
5 fixtures — deliberately NOT simple fix/review one-liners — written to cover the real
shape of agentic-coding dictation: feature ideation, brownfield context-dump, an
out-of-order multi-step ask, a debugging narrative, and a mid-task course-correction.
Each run through 3 initial candidates on the identical live path (same model, same
greedy decoding, same XML transcript wrap as production):
- **CURRENT** — production Agent system prompt + task category, exactly as shipped.
- **DENSITY** — remove disfluency only; preserve every reason/constraint/rejected
  alternative; no sentence cap.
- **STRUCTURED** — DENSITY + permission to use numbered lists for genuinely distinct
  multi-item asks.

Harness: `Speak/Tests/SpeakTests/LongFormAgentDictationABTests.swift`, gated
`SPEAK_EVAL=1` (Eval scheme), kept as a rerunnable regression check (FixABTests
precedent), not deleted.

## What the first live run showed
| Case | CURRENT lost | DENSITY recovered it? | STRUCTURED recovered it? |
|---|---|---|---|
| ideation | "not replacing it" (additive, not a rewrite), "no fancy charts," "v1/rough — don't over-polish" | ✅ yes | ✅ yes |
| brownfield-context | the existing `PinnedContextStore`/PE-3.2 component to reuse | ❌ no (all 3 candidates dropped it) | ❌ no |
| multi-step-out-of-order | explicit priority order ("knobs bug first") | ✅ yes | ❌ no (dropped priority) |
| debugging-narrative | (both fine here — short, correct) | = CURRENT | ⚠ turned a hedged guess ("my guess, could be wrong") into 6 stated-as-fact steps — worse, and 3x slower for no gain |
| course-correction | **"Stop, don't implement the caching layer"** — a retraction, silently dropped | ❌ no (also dropped it) | ✅ yes (only candidate that caught it) |

**No single candidate won outright.** DENSITY fixed 2 of CURRENT's 4 real losses;
STRUCTURED uniquely fixed the retraction case but was consistently 30–200% slower and
actively hurt the debugging-narrative case by overstating certainty. This is the
"sweet spot" problem stated precisely: preserving everything is not a length policy,
it's several distinct failure modes that need distinct handling.

**Latency, since the user separately flagged "cleanup sometimes takes a long time":**
CURRENT 0.47–1.45s; DENSITY comparable (0.44–1.70s); STRUCTURED consistently the
slowest (up to 1.53s on a case that should be near-instant). Longer/forced-structure
instructions cost real wall-clock on-device — a genuine tradeoff, not a rounding error.

## Follow-up: fixing the retraction gap without STRUCTURED's cost
Added a 4th, targeted candidate — DENSITY + one explicit rule: *"if the speaker
retracts/cancels/says stop-don't-wait about something said earlier, state it
explicitly and first, never drop it silently."* Verified live, isolated: fixed the
course-correction case (1.5s, prose form, not forced into a list) without inheriting
STRUCTURED's false-certainty problem on the debugging-narrative case (not retested
directly, but the fix is additive-only — a retraction rule, not a restructuring rule
— so it does not touch the debugging case's failure mode).

## Adopted
`DefaultProfiles.agent.systemPrompt` now ships DENSITY + the retraction rule (verbatim
in `PromptBuilder.swift`/`DefaultProfiles.swift`). Verified on the full **production
path** (system prompt + the profile's actual few-shot examples, not the isolated
instruction) — this mattered: the two pre-existing few-shot examples are both short,
and initially pulled the ideation case back down to 46 words, silently dropping the
"v1/rough" and "no fancy charts" constraints again, DESPITE the new instruction text.
**Few-shot examples are the strongest steering lever for this model (confirmed
empirically, not just per the file's own docstring) — instruction wording alone was
not sufficient.** Fixed by adding a third example to `DefaultProfiles.agent.examples`
that anchors "a short input stays short, a dense input keeps ALL its stated
constraints" (a settings-tab request with a rejected UI option + a v1-scope note).
Re-verified after that addition: ideation 63 words (recovered both dropped
constraints), course-correction 133 words (recovered the "Stop..." retraction, full
reasoning chain intact, latency ~2s).

Gates after landing: build ✅ / `make test` 603 tests (9 skipped: 6 pre-existing +
3 new SPEAK_EVAL-gated), 0 failures ✅ / `make lint` 0 serious ✅ / `make verify-moat`
7/7 ✅.

## NOT adopted / open — flag honestly
- **The brownfield-context identifier-dropping failure is unresolved.** All 4
  candidates (including the shipped one) dropped the `PinnedContextStore`/PE-3.2
  reference when it appeared inside a long hedged aside ("I remember there's already
  a thing... but I don't think it's wired up"). The base prompt already says
  "preserve every identifier... exactly as spoken" and it still gets dropped for
  identifiers embedded in uncertain/parenthetical speech specifically. This looks like
  a genuine on-device 3B model limitation under hedged phrasing, not a prompt-wording
  gap — prompt tweaks alone did not fix it in this pass. Needs its own investigation
  (a stronger structural instruction, or a post-hoc verification pass) before claiming
  it's solved.
- **Latency cost is real and now ~2x CURRENT** (0.7–1.5s → ~1.5–2s observed) for
  long-form dictation. Acceptable for now (still sub-2s, and the point of long-form
  dictation is depth over speed) but worth watching in P13 dogfood — if this is the
  "sometimes it is taking a long time" the user is already noticing, the fix is NOT to
  re-shorten the prompt (that regresses the whole point of this change) but to
  investigate session-reuse (see the course-correction fixture itself — the user's
  own proposed fix: measure whether `LanguageModelSession` creation, not generation, is
  the actual slow part, before building anything).
- **STRUCTURED (forced numbered lists) was rejected as a default** — real downside
  (false certainty on hedged content, worst latency) for a benefit (priority-order
  clarity) that the retraction-style prose rule covers well enough. Not deleted from
  the harness; kept as a candidate for future comparison if a case emerges where prose
  genuinely can't carry an out-of-order multi-item ask clearly.
