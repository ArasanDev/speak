# AI Processing Pipeline — Principled Architecture

**Status:** [proposal — ideation for owner review; no code changes implied]
**Scope:** `SpeakCore/Cleanup/`, the `runCleanup` path in `CaptureSession`, and the
SpeechAnalyzer → cleaner boundary. Extends `foundation-models-cleanup-evolution.md`
(which spec'd prompt modernization + `@Generable` — the file split landed, the
guided types did not) and `cleanup-architecture-gaps.md` (the ranked gaps this
design closes).

---

## 1. What we actually have (the unfair advantages)

Three assets no cloud dictation app has:

1. **SpeechAnalyzer streaming partials with finalization boundaries.** The STT
   layer knows which text is *volatile* (may still revise) and which is *final*
   (stable). We already exploit this for the overlay and for progressive
   cleanup — the coordinator only ingests `isFinal` chunks.
2. **A ~3B model on the Neural Engine, zero network, zero marginal cost.**
   The constraint is capability-per-token, not money — so the doctrine is
   *small prompt, tight scope, many cheap passes* rather than *one big prompt*.
   Latency is the enemy; context budget is precious; hallucination risk is the
   correctness floor.
3. **The whole Mac.** `NaturalLanguage`, `Foundation`'s linguistic APIs, the
   Accessibility context we already hold, and SQLite history (2,285 real
   dictations — an eval corpus nobody else has).

## 2. Design principles

**P1 — Deterministic before model.** Any transformation that can be done
*correctly* without judgment is code, not prompt. The model only does what
needs judgment: disfluency resolution, self-correction resolution, tone,
restructuring. Every clause removed from the prompt is attention returned to
a 3B model, and every rule moved into code is a failure mode deleted.

**P2 — The pipeline is a declared, ordered, testable object.** Today the
pipeline is implicit — six stages scattered across `CaptureSession`
(`expander`, `voiceCommandPreprocessor`), `FoundationModelsCleaner`
(`TranscriptChunker`, per-chunk `DeveloperAcronymNormalizer`, stitched
re-normalize — note the **double application**), and `extractTargetTranscript`.
Nobody can point at "the pipeline" — it isn't a value. The design: stages are
named, ordered, and individually testable; what runs for a given dictation is
inspectable.

**P3 — Level is pipeline configuration, not prompt wording.** Today
`.light`/`.medium`/`.high` differ only in instruction text. A principled
ladder selects *which stages run* and *how many model passes* — the levels
are sets of transformations, monotonically compositional: light ⊂ medium ⊂ high.

**P4 — Work overlaps speech.** The streaming coordinator is the flagship
felt-latency trick — cleanup finishes ~when capture does. The design should
make overlap structural: anything computable incrementally is computed
incrementally.

**P5 — Typed at the edges, honest at the seams.** Model output is structured
(`@Generable` — already spec'd, unbuilt) or treated as untrusted text through
a post-filter. The raw transcript is never destroyed — every stage carries
provenance forward: `raw → expanded → command-stripped → cleaned → delivered`.

**P6 — Everything is measured.** Per-dictation capture of: the rendered prompt,
the raw model response, per-stage timings. This closes G4 (eval can't diff
what we sent vs. received) and makes prompt engineering empirical instead of
vibes — we have `history.sqlite` as ground truth.

**P7 — Prompt budget doctrine.** Clause ordering by leverage: persona/guard →
task → few-shot → freshest instruction last → transcript last. Default knob
values contribute *zero* tokens (already true — keep it invariant). Every
clause earns its tokens; Apple's own guidance: imperative verbs, numbered
steps, no negative hedging, no inapplicable conditionals.

## 3. The declared pipeline

```
                              deterministic                          model                      deterministic
                              ┌──────────────────────────┐   ┌──────────────────────┐   ┌──────────────────────┐
 SpeechAnalyzer ──final──→ [expand snippets]            │   │                      │   │                      │
   chunks        ────────→ [voice-command parse+strip]  │──→│  per-chunk:          │──→│  extract/validate    │
                              [normalize lexicon]        │   │  prompt → respond    │   │  → stitch → normalize│
                              [chunk on stable bounds]   │   │  (streamed → overlay)│   │  → provenance header │
                              └──────────────────────────┘   └──────────────────────┘   └──────────────────────┘
                                                                         │
                                                          CleanupContext flows through:
                                                          { raw, expanded, chunks, responses,
                                                            renderedPrompt, timings, cleaned }
```

Concretely: a `CleanupStage` protocol (`run(_ ctx: inout CleanupContext)`) and
a `CleanupPlan` = ordered stage list resolved once per dictation from
`(mode, level, profile)`. `runCleanup` becomes `plan.execute(on: ctx)`.
Non-breaking migration: the plan defaults to today's exact stage order.

## 4. Level as pipeline configuration

| Level | Pre stages | Model passes | Post stages | Latency budget |
|---|---|---|---|---|
| `none` | none (passthrough) | 0 | none | 0 — never calls the model |
| `light` | expand, normalize | 1 light prompt (punctuation + fillers only) | extract, stitch | target < T_light |
| `medium` | expand, command-strip, normalize, chunk | per-chunk pass, streamed during capture | extract, stitch, normalize | overlapped — ~0 at stop |
| `high` | same as medium | per-chunk pass **+ a consolidation pass** over the stitched text (paragraph structure, cross-chunk coherence) | extract, stitch, normalize | the only level paying a second pass — acceptable because user asked for it |

The interesting consequence: `.high` becomes a two-pass design — chunk-local
cleanup (prevents over-editing) then a global consolidation (which today's
single pass can't do because chunk boundaries hide cross-chunk redundancy).
`.light` becomes the fast path where deterministic stages do more of the work.

## 5. Untapped platform capabilities, ranked

1. **`session.transcript`** — the rendered instructions + prompt + raw
   response per call. Observability for free. Closes G4; feeds the eval
   harness (#40). Cheapest high-value change.
2. **`@Generable CleanedTranscriptPayload`** — spec'd in the evolution doc
   (`editPlan` scratchpad + `text` field), never built. Shrinks
   `extractTargetTranscript` from "salvage layer" to "safety net" and gives the
   model a reasoning channel that isn't the output. Closes the preamble-chatter
   failure class structurally rather than by regex.
3. **`session.streamResponse`** — stream the cleaned text into the `.processing`
   overlay instead of a spinner + settling reveal. Felt-speed: the user watches
   their words get polished in place.
4. **SpeechAnalyzer segment metadata** — finalized chunks arrive with timing;
   if `SFTranscriptionSegment.confidence` is reachable through our
   `TranscriptChunk` seam, low-confidence regions can get gentler cleanup
   (don't hallucinate-fix what STT didn't hear). [unverified — needs a probe]
5. **NaturalLanguage `NLTagger`** — sentence-boundary detection is more robust
   than `NSString.enumerateSubstrings(.bySentences)` for the chunker; lemma/POS
   tagging gives a deterministic filler-word detector for `.light`.
6. **Tool calling (`Tool` protocol)** — the model could look up acronym/vocab
   entries on demand instead of prompt-injecting a 50-term list. [inferred —
   probably over-engineered for a 3B model; revisit only if vocab lists grow]

## 6. Prompt-engineering doctrine (codified from what works here)

- Persona is *task-shaped*, not character-shaped: "expert verbatim
  transcription editor" names the job, not a personality.
- Numbered imperative steps > prose paragraphs (Apple guidance, verified in
  the current `transcriptGuard`).
- Few-shot examples are the strongest steering lever for ~3B — and they're
  *contaminating* when they fight the category (the SM-2 commit/shell/code
  suppression rule is already the proof).
- The freshest instruction wins — `customInstructions` appends last for a
  reason; keep that invariant.
- Tail-positioned task reminder (`userTurnTask`) suppresses the chat reflex
  right where generation starts.
- The `<transcript>` data-wrapper + sanitize/unescape pair is the injection
  boundary — model output is never trusted verbatim (also the G5 `<think>`-tag
  strip point).

## 7. What this is NOT

- No new dependencies, no new permissions, no cloud path. Every stage is local.
- No multi-agent fan-out, no planner. A dictation is a bounded text transform,
  not an agentic workflow — parallelism comes from chunk overlap, not agents.
- No second model. One SystemLanguageModel, many small passes.
- The `.styled`/legacy `CleanupMode` cases stay — the plan resolves to them.

## 8. Migration path (each step independently shippable)

1. **M1 — `CleanupContext` + declared stage list** (refactor, zero behavior
   change): extract the implicit stage order into a `CleanupPlan` the session
   executes. Fixes the double `DeveloperAcronymNormalizer` application as a
   side effect.
2. **M2 — transcript capture** (observability): record rendered prompt + raw
   response + timings into `HistoryEntry` (or a side-channel debug log). Closes
   G4 — eval becomes real.
3. **M3 — `@Generable` payload** (correctness): guided `CleanedTranscriptPayload`
   per the evolution spec; `extractTargetTranscript` becomes the fallback.
4. **M4 — level→plan mapping** (the Strength row's engine): `.high` gains the
   consolidation pass; `.light` documents its deterministic-first stance.
5. **M5 — `streamResponse` into the overlay** (felt speed): the processing
   lane shows live polish instead of a spinner.
6. **M6 — confidence-adaptive cleanup** (if the STT seam exposes it) —
   [unverified until probed].

## 9. Open questions for the owner

- **Two-pass `.high`?** The consolidation pass is the real "strong" in your
  Raw → Light → Medium → High ladder — it's the only level that re-reads the
  whole text. Worth the ~1s extra on the biggest rambles?
- **`.light` determinism depth** — how far should the deterministic-first
  doctrine go? A regex/NL filler pass could cover punctuation + fillers with
  *zero* model calls for the simplest dictations, but risks mechanical
  artifacts (missing Oxford commas, wrong question marks). The safer first cut
  keeps the model pass and just shrinks its prompt.
- **Streaming the polish** — `streamResponse` during `.processing` is the
  biggest felt-quality win after the tally lamp, but it means the overlay shows
  *unfinished* cleaned text. Acceptable — or does provisional cleaned text read
  as flicker?
