---
name: orchestrator-runs-in-worktree
description: "This session's orchestrator cwd IS a git worktree; subagent isolation:worktree does not give isolated trees"
metadata: 
  node_type: memory
  type: feedback
  originSessionId: 9167b3d9-9742-4572-8e93-16d55f6b35eb
---

In the `speak`/deepvoice build, the orchestrator's own primary working dir is a git
worktree (e.g. `.claude/worktrees/agent-<id>`), not the main checkout. Consequence:
subagents spawned with `isolation: worktree` did NOT get their own isolated trees —
they committed onto the orchestrator's worktree branch, stacking commits linearly.

**Why:** When I'm already inside a worktree, spawned agents operate in/around that
same worktree rather than fresh ones.

**How to apply:** Do NOT rely on subagent `isolation: worktree` for parallel-safety
of file-mutating agents in this setup. Either (a) `git worktree add` explicit dirs
yourself and tell each agent its absolute path, or (b) serialize tasks that touch
overlapping files. Always verify with `git worktree list` + per-commit `git show
--stat` that commits landed where expected and didn't cross-contaminate (concurrent
`git add -A` in one tree can sweep another agent's files). Run git/make from the
main checkout (`/Users/tamil/Developers/deepvoice`), not the worktree cwd.

Related: [[agent-first-acceleration-model]], [[dev-codesigning-for-tcc]].
