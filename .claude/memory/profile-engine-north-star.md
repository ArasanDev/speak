---
name: profile-engine-north-star
description: "speak's locked product direction — a local-first voice-driven fully customizable AI text engine (the Profile Engine), with immutable core/extension layering"
metadata: 
  node_type: memory
  type: project
  originSessionId: 7c3a8745-710d-4a05-871e-8dc689091fae
---

**Locked 2026-06-29 (human decision).** `speak` is becoming a **local-first,
voice-driven, fully customizable AI text engine** — the "Profile Engine." Spec:
`specs/profile-engine.md`; default prompts: `specs/profile-system-prompts.md`;
WHY: `product.md §6d`; roadmap "North star" section + PE/SM tasks.

**The one idea:** a Profile = name + system prompt + a few rules. Ship great
defaults; everything customizable ("default + customization version for
everything"). Agent Mode, per-app context, Transforms, code-aware are all
**instances of this one engine**, not separate features.

**Immutable layering (never invert):**
1. Base core (NEVER changes): double-press activate / single-press stop; raw
   voice → text ALWAYS available, no AI in path.
2. Default: `Clean` profile (on-device neat-writing); AI off ⇒ raw passthrough.
3. Extension: the Profile Engine.

**Two surfaces:** Dashboard → AI Studio *authors* profiles (gear bottom-left);
the Overlay is a real-time *control surface* to pick/steer the active profile
live (the overlay icon = live customization, NOT a settings duplicate). Novel
loop: stream → live AI preview → steer (tap/voice) → commit (only final AI text
pasted; raw never inserted).

**Hard constraint:** default model is a very small (~3B) on-device model (Apple
Foundation Models). Design every prompt for that — short imperative prompts,
few-shot examples, one job per profile, explicit output contracts, always
degrade to raw on failure. A small-models eval harness (golden fixtures,
on-device latency) makes tuning measured not guessed.

**Why:** cloud tools won't give private system-prompt control; local tools lack
this UX. speak sits in the gap — the moat.

**How to apply:** new features should be expressed as profiles/profile-knobs,
not new code paths. Never break the base-core guarantee. Relates to
[[agent-first-acceleration-model]] (orchestrate: design locked → fast worker
implements) and [[ux-voice-dictation-principles]].
