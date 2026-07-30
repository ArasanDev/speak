# Spec: Input — Felt Speed

Status: **active** · Owner: input slice · Depends on: `specs/wispr-input-layer-taste.md`, `specs/frontend-identity.md` (frozen)

## 1. The problem, stated honestly

`speak` produces better text than Wispr Flow and is the only one of the two that is
100% on-device. It still *feels* slower, and felt speed is what people judge.

| | Wispr Flow | `speak` today |
|---|---|---|
| Speech → text appears | ~1–2s | ~5–10s (Foundation Models cleanup) |
| Masking of that gap | none needed | none present |

`docs/progress.md` Loop #13 classifies the cleanup latency as "known limitation, not
a blocker." **That classification is wrong at the product level.** It is the single
largest felt-quality deficit in the input layer.

The gap cannot be closed by making the model faster — a larger model makes per-token
latency worse, and we want the larger model. It must be **masked**. Masking is
architecturally available to us and *not* to Wispr: their transcript round-trips a
network boundary, so they have no partials to reveal. We run on-device and already
stream partials through `AsyncStream`. We hold the one card they cannot play.

## 2. Objective

The user must never watch a spinner for text we already have.

**Done condition:** from end-of-speech, the user sees final-quality-looking text in
their target app in **under 1.2s**, and the cleaned text replaces it without ever
showing a flicker, a duplicate, or a partially-overwritten word.

## 3. Design — optimistic paste, then refine

Today: `stop → cleanup (5–10s) → paste`. The raw transcript exists at `stop`. We are
sitting on it for up to ten seconds to avoid showing an imperfection.

Change to a two-phase commit:

1. **Phase 1 — optimistic paste (immediate).** On stop, paste the raw transcript at
   the cursor via the existing `PasteboardWriter` path. The user is unblocked
   instantly and can keep working.
2. **Phase 2 — refinement (when cleanup returns).** Replace exactly the range Phase 1
   wrote with the cleaned text. Nothing else on screen may be touched.

### 3.1 The hard constraint on Phase 2

We cannot read the pasteboard (hard rule) and we cannot read the target app's text.
So Phase 2 must be **bounded and reversible or it must not happen.** Required
guarantees, in priority order:

- **Never corrupt the user's document.** If we cannot prove the Phase-1 text is still
  the selection we wrote, we **abandon** Phase 2 and leave the raw text in place.
  A slightly-unpolished sentence is an acceptable outcome; an eaten paragraph is not.
- Phase 2 is skipped entirely if the user typed, clicked, or changed focus after
  Phase 1. Detect via focus/app change and keystroke activity through the existing
  `CGEventTap` seam — no new taps, no new permissions.
- Phase 2 has a **deadline**. If cleanup has not returned within `refinementDeadline`
  (default 12s), the raw text stands permanently and we log it.

### 3.2 Settings surface

One user-visible knob, defaulting **on**:

> **Paste instantly, polish after** — text appears the moment you stop speaking, then
> upgrades itself a second later. Turn off to wait for the polished version.

Off ⇒ exactly today's behaviour. This is the escape hatch and it must work.

### 3.3 If §3.1's safety bar cannot be met

Then Phase 2 is dropped and the slice degrades to **progressive reveal in the
overlay** instead: the overlay shows the raw transcript immediately, marked as
settling, and the *single* paste happens on cleanup. That still removes the blank
wait, still beats today, and carries zero corruption risk. **Ship the degraded form
rather than an unsafe Phase 2.** This is a design decision, not a fallback to
negotiate.

## 4. Non-goals for this slice

- No change to cleanup quality, prompts, or the `LLMCleaning` protocol.
- No new overlay visual language. `specs/frontend-identity.md` is **frozen**:
  `onAir` appears **iff the microphone is capturing** and a 32-case test pins it.
  Refinement is not capture — it must not light `onAir`.
- No work on end-of-utterance waveform feedback or the mode pill. Separate slices.

## 5. Verification

- Unit: the two-phase controller emits paste-once on Phase 1, and replaces-or-abandons
  on Phase 2 across every abandonment trigger (focus change, keystroke, deadline,
  cleanup failure, cleanup returning text identical to raw).
- Unit: refinement never sets `onAir`.
- `make gates` clean: build, test, lint, verify-moat.
- Dogfood: 10 real dictations, measured stop→visible-text latency, logged in
  `docs/progress.md`. Prose is a hypothesis; the measurement is the evidence.
