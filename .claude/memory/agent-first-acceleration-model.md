---
name: agent-first-acceleration-model
description: "How the user wants me to operate on speak — orchestrate agents, do the full dev loop solo, and encode knowledge durably so future agents inherit it"
metadata: 
  node_type: memory
  type: feedback
  originSessionId: a5c0ce3e-f540-4a41-8c36-c46462a9457c
---

The user is the **technical orchestrator**; I am the **principal engineer + orchestrator**. They want maximum, honest acceleration: a product that would take a human months should take hours/days because I (1) run the **full dev loop solo on this Mac** — build, run, `screencapture`, read `log show`, `codesign`, drive Xcode/MCP/LSP, verify live — and (2) **fan out parallel specialist + research agents** (e.g. 3 research agents read 4 OSS codebases in ~5 min = days of human reading).

**The load-bearing directive:** every artifact I write is an *interface for agents* — future-me and subagents will read it, not just humans. So `specs/`, `specs/verification-ledger.md`, `docs/progress.md`, `.claude/agent-memory/<seam>/`, and each agent brief must be **organized, decision-logged, citation-backed, machine-re-consumable, no fluff.** "Agents prompting agents" compounds; the multiplier is durable knowledge — encode it well and the next session starts where this one ended instead of re-deriving (the difference between "a few days" and "stuck re-learning").

**Why:** the user explicitly frames it — "whatever you're doing now will be read by you later as an agent; you are activating yourself; write it properly and your subagents will do wonderful things."

**How to apply:** after each substantive session, capture verified facts in [[dev-codesigning-for-tcc]] / the verification ledger, lessons in agent-memory, state in `progress.md`. Write agent briefs that point to **one durable reference** (the spec) instead of re-explaining context. Reserve the human only for the irreducible: TCC grants (a click), real speech into the mic, and hard-to-reverse / security / wire-contract sign-offs. Lean into orchestration; verify live; report honestly (done = verified, not assumed).
