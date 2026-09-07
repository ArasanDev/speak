# SM-2 Phase0b eval-metric redesign — review of `pe/sm-2-metric` (commit `366d01f`)

> **Research header** — Question: "does the `pe/sm-2-metric` branch's tokenizer/scorer
> redesign improve on master's eval metric, and is it safe to merge?" · Date: 2026-07-04
> · Status: **evidence**

> Read-only evidence + decision record. This branch predates the repo reorg and was
> never merged as a whole (a raw merge would have clobbered master's independently-
> evolved rubric-scorer and `EvalHarnessTests.swift`). Reviewed 2026-07-04 with a
> throwaway verification script (written, run, and deleted this session — not checked
> in) that re-implemented old-vs-new tokenizer/scoring side by side against real
cases pulled from `research/fix-fragment-ab-result.md` and the live SM-2 A/B run.

## Method
Wrote a standalone Swift script (`swift <file>.swift`, no Xcode project) containing:
old master `correctness()` next to the new edge-punctuation tokenizer, multi-reference
scorer, and `noUnspokenIdentifiers`. Ran both against concrete before/after examples.
Deleted the script after confirming results — this note plus the tests adopted into
`EvalScoringMetricRedesignTests.swift` are the durable record.

## Adopted directly onto master (verified real, low-risk, additive — no fixture-schema change)
1. **Edge-punctuation-normalizing Jaccard tokenizer.** Old tokenizer folded punctuation
   into words, so `"...pane."` ≠ `"...pane"`. Measured: a real fixture-shaped case scored
   **0.75** (below the 0.80 pass threshold) on a period-only mismatch; **1.0** after the fix.
   This was a real, live false-failure risk in `make eval`, not a hypothetical.
2. **`correctness(output:references:)` — multiReference scoring.** Old single-reference
   scoring imposes a "single-phrasing ceiling": a live SM-2 A/B output (`"Fix the paste
   issue after the first dictation."`) scored **0.56** against one accepted phrasing
   (below threshold) and **1.0** once the second accepted phrasing was included as an
   alternate reference. Confirms the redesign's own stated rationale.
3. **`noUnspokenIdentifiers` anti-hallucination guard.** Master had **zero** guard against
   an output inventing a file/function/symbol the speaker never said — a real risk for
   this product, since Agent-mode output feeds a downstream coding agent. Verified the
   guard passes legitimate identifier-ization ("capture session" → `CaptureSession`) and
   fails an invented `PasteboardWriter.swift`/`writeOnce()`.

Landed in `Speak/SpeakCore/Eval/EvalScoring.swift` + `Speak/Tests/SpeakTests/EvalScoringMetricRedesignTests.swift`.
Gates re-verified after landing: build ✅ / `make test` 600 tests, 6 skipped, 0 failures ✅ /
`make lint` 0 serious ✅ / `make verify-moat` 7/7 ✅.

## Reviewed, NOT adopted this pass — flagged as a dedicated follow-up
- **Exact-vs-Jaccard split by genre** (code/shell/raw → exact whole-string match;
  task/fix/ask/commit/write/note → Jaccard) and the **structural per-category checks**
  (`imperativeFirstLine`, `numberedListWhenMultiItem`, `preservesIdentifiers`, etc.) —
  master already has an independently-evolved, additive rubric system
  (`evaluateFixtureRubric` + `BuiltInFormatChecks`, merged separately at loop #38/#39)
  covering similar ground (`imperativeStart`, `endsWithQuestion`, `conventionalCommitsFormat`,
  `noFiller`, `noMarkdown`, `preservesTerms:X`, `maxSentences:N`). The two systems were
  **not reconciled** — adopting the branch's version wholesale risks duplicating or
  conflicting with the rubric checks already shipped. **Needs a dedicated task** to map
  branch-checks → existing-rubric-checks 1:1, keep whichever is stricter/better-named,
  and only then touch `eval-fixtures.json`'s schema (49-line diff) and rewrite
  `EvalHarnessTests.swift` (575-line diff) around the reconciled set.
- **`FoundationModelsCleaner.generate()` factoring** — a refactor extracting the single
  FM-call path into one function. Plausibly fine, but out of scope for an eval-metric
  review; re-evaluate when someone is actively touching `FoundationModelsCleaner.swift`.
- **The historical 20-fixture live-FM baseline numbers** (Agent 98.03%, Note 100%, Raw
  100%, Write 97.22%) — already recorded as provenance-only in
  `specs/verification-ledger.md` §5, explicitly marked not reproduced on this tree. No
  further action; do not cite those numbers as current `make eval` output.

## Bottom line
The `fix` fragment prompt decision (already adopted in `e4eef32`) was the right call —
confirmed by the earlier live A/B, not re-litigated here. Of the metric work left behind,
three pieces were real, verified, low-risk wins and are now live on master; the rest
(genre-split scoring + structural checks + fixture-schema rewrite) is real but larger
surgery that needs its own reconciliation pass against the rubric system already shipped
— tracked here rather than attempted piecemeal.
