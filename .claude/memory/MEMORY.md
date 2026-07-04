# Memory index — speak (deepvoice)

One line per memory; the recall layer loads this each session.

- [Agent-first acceleration model](agent-first-acceleration-model.md) — how the user wants me to operate: orchestrate, solo the dev loop, encode knowledge for future agents
- [Dev code-signing for TCC](dev-codesigning-for-tcc.md) — cert-sign via Signing.xcconfig or permission grants break every rebuild; Xcode≠make DerivedData gotcha
- [Monaco font theme](monaco-font-theme.md) — speak's UI typographic theme is Monaco (native macOS mono), user's locked calming design choice
- [Orchestrator runs in worktree](orchestrator-runs-in-worktree.md) — subagent isolation:worktree gives no isolated tree here; create worktrees manually or serialize file-mutating agents
- [UX voice dictation principles](ux-voice-dictation-principles.md) — 10 core design principles for speak from modern voice dictation, privacy-first, and AI transparency research (WWDC 2025-2026 aligned)
- [Profile Engine north star](profile-engine-north-star.md) — locked product direction: local-first voice-driven customizable AI text engine; core/extension layering; small-model constraint; two-surface model
- [Coding-agents-first positioning](coding-agents-first-positioning.md) — near-term wedge: voice dictation FOR coding agents; overlay = control surface; Mac-devs audience; log now, observability UI later
- [Build sequencing: completeness first](build-sequencing-completeness-first.md) — complete every component correctly before any visual/contrast polish; WCAG targets for the later pass
- [make run / stale instance](make-run-stale-instance.md) — speak is a menubar app; `open` won't relaunch it. Use make run/doctor/logs/history or you verify stale code
- [speak Agent profile strategy](speak-agent-profile-strategy.md) — Agent profile = CC meta-prompt generator + UserPromptSubmit hook for context; speak outputs short precise imperatives only
- [deep-research workflow design](deep-research-workflow-design.md) — Opus for scope only, Haiku for all parallel work + synthesis; 2-pass verify planned
