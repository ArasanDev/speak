---
name: project-p12-docs
description: P12 public docs (README, CONTRIBUTING, CHANGELOG) written and what was deferred
metadata:
  type: project
---

P12 public-facing docs written on 2026-06-21: `README.md` (full rewrite), `CONTRIBUTING.md` (new), `CHANGELOG.md` (new).

**Why:** v0 engine + UI are fully built (143 tests, make verify-moat 7/7) — the public face needed to reflect actual state, not the stale "pre-build, no code yet" skeleton.

**Key accuracy calls made:**
- Moat framing: the wedge is the *structural bundle* (local + MIT + offline + no-account + local history + lower latency), NOT "free" or "Fn hotkey" alone — Wispr has both.
- "Only free+local+OSS" claim from the old README is FALSE (Aiko, TypeWhisper, FluidVoice also qualify); the README now accurately states the structural bundle.
- Hardware mute (product.md §8 guarantee #4) has no implementation in the codebase — listed as a privacy posture/design guarantee, not a usable feature today.
- Latency figures cited with caveat: headless file-fed proxy (p50 ~42 ms first-partial), not user-facing e2e latency.
- Install: `brew install --cask speak` marked as the *planned* path (P11); build-from-source is the only current path.
- Demo GIF/screenshots: deferred, row added to `docs/human-verification.md` §5.

**How to apply:** When updating public docs, maintain these precision points. Don't reintroduce "only free+local+OSS" or claim hardware mute is built.

Related: [[project-v0-state]], [[feedback-moat-precision]]
