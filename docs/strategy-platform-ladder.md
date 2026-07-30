# Strategy: The Platform Ladder

**Status:** proposed · **Audience:** maintainer · **Binds:** nothing yet — this is
direction, not contract · **Last substantive change:** 2026-07-30

## 0. The decision this records

`speak` targets Apple Silicon Macs on macOS 26, exclusively, until it has real
traction there. Windows and Linux are deferred — not abandoned, deferred, with a
stated trigger for reconsidering. This document exists so that "when do we do
Windows?" has an answer that is a threshold rather than a mood.

## 1. Why the narrow target is the strategy, not a limitation

The temptation with an ambitious open-source project is to broaden early, because
breadth looks like ambition. Here it would be the opposite.

Every differentiator `speak` has is a direct consequence of the narrow target:

| Differentiator | What makes it possible |
|---|---|
| 100% on-device STT | `SpeechAnalyzer` — Apple, macOS 26, Apple Silicon |
| On-device AI neat-writing | Foundation Models — same constraint |
| Zero third-party deps | Only achievable because Apple ships both models |
| <15MB payload `[unverified]` | Competitors bundle 460–500MB because they ship their own models |
| Free forever, no accounts | No inference cost to recover |

Competitors charge $8–15/month because they pay for cloud inference. `speak` has no
such cost — but *only* on hardware where Apple gives the models away. Port to
Windows and every one of those rows breaks at once: a bundled model, a large
payload, third-party dependencies, and a per-user cost that has to come from
somewhere.

So the honest framing is: **this is not a Mac app that might go cross-platform. It
is an app whose entire value proposition is a bet on Apple's on-device stack.** A
Windows version is a different product that shares a name.

That is worth saying plainly in public, because it converts an apparent weakness
("Mac only") into the reason the thing can be free.

## 2. What "winning on Apple Silicon" has to mean

Vague ambition ("be #1") cannot be executed against. Concrete conditions:

**Product bar** — the `docs/benchmark.md` §4 MATCH gate and §3 BEAT rows pass, and
`docs/quality.md` §9 ships. Note that `make verify-moat` explicitly defers the rows
that matter most here — accuracy WER, live paste, hotkey false-trigger rate,
latency — to human dogfooding. Those are unverified today. No amount of
repository polish substitutes for them.

**Adoption bar** — a signed, notarized release a stranger can install without
building from source (roadmap P11). Until that exists, the addressable audience is
"people willing to install Xcode 26," which is not a user base.

**Credibility bar** — the privacy claim stays structurally enforced, not asserted.
`scripts/verify-moat.sh` + `MoatAuditTests.swift` are the moat. They are also the
single most defensible thing about the project and should be the loudest thing in
the README.

## 3. The trigger for reconsidering

Revisit cross-platform only when *all three* hold:

1. A notarized release exists and installs cleanly for non-developers.
2. The MATCH/BEAT gates pass with measured evidence, not inference.
3. Demand is observed rather than imagined — concrete inbound requests, not a
   guess that Windows users would want it.

Any earlier port spends the project's scarcest resource (maintainer attention) on
a second platform before the first one is finished. The failure mode is two
half-products instead of one that people love.

## 4. If and when the ladder is climbed

The architecture already anticipates this and should not be redesigned for it now.
`Transcribing` and `LLMCleaning` are protocol seams; `SpeakCore` is a headless
framework with the UI shell above it. A future port replaces the two seam
implementations and the shell, and keeps the engine.

What a port would have to solve — recorded so nobody rediscovers it later:

- **Model sourcing.** No free on-device STT or cleanup model is handed to you
  outside Apple's stack. Bundling one reintroduces payload, licensing, and update
  burden.
- **The input seam.** `CGEventTap` (hotkey) and `NSPasteboard` + Cmd+V (paste)
  are Mac-specific and permission-gated per platform.
- **The free promise.** If a port cannot be free and local, it should not ship
  under the same name. The promise is the product.

## 5. What this document is not

Not a commitment to ever ship Windows or Linux. Not a roadmap item. It is a
recorded decision with a stated trigger, so the question can be answered
consistently instead of relitigated.
