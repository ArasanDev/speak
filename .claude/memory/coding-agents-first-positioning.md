---
name: coding-agents-first-positioning
description: "Locked go-to-market: speak's near-term wedge is voice dictation FOR coding agents; overlay is the control surface; Mac devs are the audience"
metadata:
  node_type: memory
  type: project
  originSessionId: 6bb08f55-aed8-4783-ae45-70136bca48f6
---

The user locked the **next-stage positioning** (2026-06-29): speak stays a general
voice-dictation app, but the **near-term wedge / go-to-market is "voice dictation
FOR coding agents"** — dictating into the input layer of coding agents (Claude
Code / Cursor / terminal IDEs / etc.).

- **Audience bet:** the Mac ecosystem is ~80–90% developers; nail the
  developer-dictating-to-a-coding-agent flow and adoption follows. The user is the
  archetype: ~10 tabs open, all coding, much input typed into terminals/agents.
- **The overlay is the control surface.** The HUD that appears on double-press +
  speaking is where the user should "get the maximum" — profile/customization for
  the coding-agent target lives here. This elevates roadmap **PE-3/PE-4 (Overlay
  Tier 1/2/3)** in priority, framed around coding-agent dictation.
- **Don't narrow the product.** Solve coding-agent input *generally* (works for any
  agent's text field), not a brittle per-app hack. Push capability hard; coding is
  the *first* beachhead, not the ceiling. See [[profile-engine-north-star]].
- **Observability is a later layer, not now** — but build the **logging foundation
  well now** (clean `os.Logger` signal) so a full app/agent observability view can
  surface in the UI later, easily.

**Why:** maximize developer adoption by being the best voice→coding-agent input on
Mac, while keeping the general dictation core intact.

**How to apply:** prioritize the coding profiles (Code/CLI/Prompt/Commit) and the
overlay customization surface; keep solutions general; invest in structured logging
now even though the observability UI is deferred. Related:
[[ux-voice-dictation-principles]], [[build-sequencing-completeness-first]].
