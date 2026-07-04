---
name: build-sequencing-completeness-first
description: "User's locked work ordering — complete every component correctly first, visual/contrast polish second"
metadata: 
  node_type: memory
  type: feedback
  originSessionId: 6bb08f55-aed8-4783-ae45-70136bca48f6
---

The user locked the build sequence (2026-06-29): **completeness before polish.**

1. Build every component correctly and fully first — no stubs, no half-wired panes.
2. Visual appeal / contrast is a SEPARATE, LATER pass — explicitly deferred.

**Why:** the user judges basic functionality "okay and already available" and wants
structural completeness nailed before spending effort on aesthetics. Polishing an
incomplete app wastes work.

**How to apply:** when prioritizing, finish/correct functional components before any
contrast/typography/visual work. When the polish pass comes, target WCAG AA (4.5:1 text,
3:1 UI), adapt to light+dark via macOS semantic colors, never signal state by color alone
(keep the SF-Symbol pairing), and keep accents muted per the calming [[monaco-font-theme]].
Related: [[ux-voice-dictation-principles]], [[profile-engine-north-star]].
</content>
</invoke>
