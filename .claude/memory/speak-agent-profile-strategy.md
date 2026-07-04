---
name: speak-agent-profile-strategy
description: "Locked strategic direction for speak's Agent profile — meta-prompt generation for CC, two-layer architecture with UserPromptSubmit hook"
metadata: 
  node_type: memory
  type: project
  originSessionId: 1d9f3f33-eabd-4163-9240-e3b601caa5cf
---

Speak's Agent profile is NOT a text cleaner — it is a **meta-prompt generator for coding agents**.

**Architecture (locked 2026-06-30):**
- Speak (on-device 3B): voice → short, precise, imperative text. Nothing else.
- CC UserPromptSubmit hook: injects project context (docs/progress.md + git branch + CLAUDE.md) into every prompt automatically.
- Speak does not need project awareness — the hook handles it on the CC side.

**What speak's Agent/CC output should look like:**
- One imperative sentence (the task)
- Exact technical names preserved (grep-safe)
- Constraint if stated: "Constraint: do not modify X"
- Nothing else — CC has tools, it finds context itself

**What speak does NOT need to produce:**
- Project background (hook injects it)
- File paths it doesn't know (CC searches)
- Loop structure (CC handles autonomously)

**Why:** CC's philosophy = "minimal input → maximum inference." The UserPromptSubmit hook solves the new-session problem (works from turn one, reads files).

**Next build:** (a) redesign Agent profile system prompt as CC meta-prompt generator, (b) write UserPromptSubmit hook at ~/.claude/hooks/user-prompt-submit.sh

**Why:** [[coding-agents-first-positioning]] — this is the vertical wedge. Optimizing speak's output for CC = capturing developer market.
