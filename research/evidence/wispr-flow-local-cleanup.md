# Wispr Flow deconstructed: local-first cleanup is the winnable path

> **Research header** — Question: "How does Wispr Flow achieve its STT/cleanup
> quality, and which parts can speak replicate locally on Apple Silicon with a
> small on-device model?" · Date: 2026-08-19 · Status: **evidence**

> Read-only evidence + direction flags. Documents the verified Wispr Flow
> architecture and flags the local-first product direction. Direction flags are
> **NOT applied** — per access policy, `docs/` and `specs/` supersede this file,
> and any change to a spec/architecture requires human approval first.

---

## 1. What Wispr Flow actually does (verified)

### 1.1 It is a two-stage pipeline, not one magic STT model

Wispr's quality comes from a cloud pipeline with two distinct stages, and the
second stage is where the "polish" lives:

1. **ASR** — context-conditioned speech recognition.
2. **Cleanup** — a separate fine-tuned LLM that formats and structures the raw
   transcript.

Their own engineering blog lists both goals together:
- "The world's best ASR models (context aware, personalized, and code-switched)"
- "Cloud based speech processing infrastructure" — `[verified]` wisprflow.ai, 2025-09-11.

The Baseten case study names the cleanup stage directly: "fine-tuning Llama models
for transcript cleanup tasks." `[verified]` baseten.co customer case study.

> **The key finding for speak:** Wispr does **not** rely on the ASR to emit clean
> text. A fine-tuned LLM does the cleanup. This validates speak's existing
> two-stage shape — `SpeechAnalyzer` (ASR) → `FoundationModelsCleaner` (cleanup).

### 1.2 The cleanup stage is the "magic"

Filler removal, punctuation, capitalization, self-correction resolution, and
style matching all happen in the **cleanup LLM**, not the recognizer. Wispr's
own docs state the difference from "traditional speech-to-text": it is "optimized
to understand what people say, and output text in their style." `[verified]` api-docs.wisprflow.ai.

This is a **transform on text**, not open-ended generation. That matters because
it is the exact class of task a small model does well when prompted strictly.

### 1.3 Latency is engineered at p99, on rented GPUs

- End-to-end **< 700 ms** at **p99** (not p50). `[verified]` baseten.co.
- ASR inference < 200 ms, LLM inference < 200 ms, network < 200 ms. `[verified]` wisprflow.ai.
- The fine-tuned Llama generates **100+ tokens in < 250 ms** via TensorRT-LLM on
  AWS GPU deployments. `[verified]` baseten.co.

This latency is a cloud-GPU artifact, not an architectural requirement of the
transform itself. It is why Wispr's quality feels instant — but it costs audio
egress, a subscription, and a mandatory account.

### 1.4 Personalization and correction learning

Two compounding advantages that are orthogonal to model quality:
- Capturing user edits and learning which corrections to apply (and when), then
  training an LLM to follow them precisely. `[verified]` wisprflow.ai.
- Token-level style formatting: dash vs comma, capitalization in specific contexts,
  per-recipient tone. `[verified]` wisprflow.ai.

Both are "learn the user's writing style," not "better transcription." They are
the highest-leverage moat Wispr has — and they are learnable locally.

---

## 2. The local-achievability thesis

Wispr uses cloud for **business/product** reasons (subscription revenue, GPU scale
for 1B users, team/enterprise compliance posture) — **not** because the core
transform fundamentally requires a server.

The actual task is narrow:
- Remove disfluencies (um, uh, false starts).
- Fix punctuation, capitalization, and obvious spelling.
- Resolve self-corrections ("go to the the store" → "go to the store").
- Preserve every remaining word verbatim.

This is a **simple, deterministic-leaning text transform** — not reasoning, not
summarization, not translation, not open-ended generation.

Three facts make it locally winnable:
1. **Apple Silicon has a Neural Engine** and runs Apple Foundation Models
   on-device with no account, no key, no download. `[verified]` architecture.md §10a.
2. **Modern small LLMs (~3B class) do narrow transforms reliably when given a
   strict mandate.** `[inferred]` — consistent with small-model prompting
   literature; see small-model-prompting-eval.md.
3. **The product belief is that ~90% adequacy is reachable** because the task is
   simple. `[unverified]` — not yet measured against a target corpus; it is a
   testable hypothesis, not an established fact.

> The honest caveat: Wispr's fine-tuned Llama is **better at style reproduction**
> than a general-purpose 3B model prompted in zero-shot. Local-first wins on
> privacy/cost/offline; it does **not** automatically win on raw cleanup quality
> until we measure it. The path is prompt strictness first, then — if needed — a
> specialized on-device model behind the same `LLMCleaning` seam.

---

## 3. The core insight: prompt it as a **transcriber**, not an editor

The dominant failure mode is asking the model to "improve," "polish," "refine,"
or "reconstruct" text. To an RLHF-trained model, "improve" means paraphrase,
condense, reorder, and drop words — exactly the over-editing we observed live
(history rows like `"Create the new PRT." → "PRT"`).

The fix is a **strict, narrow mandate**:

> You are a transcriber. Clean the spoken transcript by removing disfluencies and
> false starts and by fixing punctuation, capitalization, and spelling. Do not
> paraphrase, condense, reorder, summarize, or improve. Keep every remaining word
> verbatim.

This is the same insight the research surfaced: small models degrade sharply on
multi-instruction prompts and on "improve the text" framing, but handle a single
named task with an explicit output contract reliably.

---

## 4. Direction flags (NOT applied — require human approval before building)

1. **Collapse the cleanup intensity ladder to two levels** (basic + intermediate).
   The current 4-level scale (none/light/medium/high) invites over-editing at the
   upper end. Proposed:
   - **Basic** — disfluency removal + punctuation only.
   - **Intermediate** — + capitalization, spelling, light self-correction.
   - Drop `.high` aggressive restructuring for v0; it is the source of the worst
     content-destruction failures.
   - This is a spec/architecture change (`CleanupLevel` in `Cleaner.swift`,
     `SettingsStore`, `CleanupStyle` UI, W4.1 decision). Flagged, not applied.

2. **Make every prompt assert the transcriber role.** Loop #82 already reworked
   the default `.styled(.default, .medium)` path to preservation-first. Extend the
   same wording discipline to `.high`, `.professional`, `.toneAdjust`, and the
   profile path so no mode ever invites paraphrase.

3. **Test the model directly to characterize behavior.** We have `make eval`
   (fixtures) and `make history-eval` (real raw→cleaned pairs). Add a single-prompt
   interactive probe (`scripts/probe-cleanup.swift`) so a strict-prompt candidate
   can be A/B-tested against real dictations in minutes, not through a full build
   cycle.

4. **Close the benchmark loop on a fixed corpus.** `benchmark.md` §6 already
   defines a ~20-clip corpus and WER gate. Run it and record measured numbers —
   raw-ASR WER plus cleanup content-retention — instead of `[inferred]` claims.

5. **Re-verify the competitor claim.** `docs/competitors.md` currently states STT
   is "OpenAI Whisper via Wispr servers." Wispr's own blog describes proprietary
   context-conditioned ASR. Flag for re-verification before quoting externally.

---

## 5. What this means for the product

Wispr is not "STT so good." It is "ASR + a fine-tuned cleanup LLM + personalization
+ aggressive p99 GPU latency." speak already has the correct two-stage shape and
the local-first moat Wispr cannot copy.

The improvement lever is **not** a bigger cleanup model or more cleaning levels.
It is **strict transcriber prompting** and **minimal scope** — two levels, verbatim
preservation, no "improve the text." The current ~3B on-device model is very likely
sufficient for that narrow task; the measurement loop (`make history-eval` +
benchmark corpus) will prove or refute it.
