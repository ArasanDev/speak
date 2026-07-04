---
name: deep-research-workflow-design
description: "Locked model routing for lean-research workflow — Opus for scope, Haiku for parallel gather, Sonnet for synthesis"
metadata: 
  node_type: memory
  type: feedback
  originSessionId: 1d9f3f33-eabd-4163-9240-e3b601caa5cf
---

Model routing for deep-research workflow (decided 2026-06-30):

- **Scope**: Opus — highest-leverage single call, defines all downstream angles. Bad scope = wasted fleet.
- **Search / Fetch / Verify**: Haiku — mechanical parallel work, no judgment needed.
- **Synthesize**: Sonnet — synthesis requires judgment: dedup, confidence-tag, coherent prose from raw findings.

**Why:** Judgment only at the design point (scope). Execution is always Haiku.

**How to apply:** Any workflow following this pattern: Opus for the one agent that defines structure/direction, Haiku for everything that executes within that structure.

**Script location:** ~/.claude/projects/.../workflows/scripts/deep-research-wf_f5d5af01-44f.js (already updated)

**Planned improvements:**
- 2-pass verify: Haiku quick-filter (no web search) → targeted web-search only for surviving central claims
- Cross-source confidence boost: claims in 3+ sources skip verify entirely
- Claim classifier before verify: route by type (numerical/factual/opinion) to right tier
