---
name: feedback-concurrent-worktree
description: phase0b-style worktrees may be mutated by other agents concurrently; verify a red test is yours before escalating, and expect the orchestrator to integrate+dedup your diff
metadata:
  type: feedback
---

When assigned a dedicated worktree (e.g. `deepvoice-wt/phase0b`), do NOT assume you are the sole writer. In the SM-2 Phase0b run, a second agent was flipping the `fix` prompt fragment to imperative + adding `FixABTests.swift` in the SAME tree while I did the metric redesign; the orchestrator then committed the combined work and DEDUPLICATED my parallel A/B harness (`runFixAB`, PromptBuilder `categoryFragmentOverride`) in favor of the already-committed `FixABTests`, keeping my metric core + cleaner eval entry.

**Why:** A `git status` that was clean at session start went to "all committed" mid-task; a test I thought I broke (`testAgentCategoryFragmentsAppendedForAgentOnly` expecting "bug report") was actually failing because of the OTHER agent's fragment flip, and was fixed by the fragment owner — not me. Subagent `isolation:worktree` does not guarantee an isolated tree here (see [[orchestrator-runs-in-worktree]]).

**How to apply:**
- Before escalating a failing gate, pull the COMPLETE failure list (XCTest `' failed ('` AND Swift Testing `✘` formats — they differ) and triage each as mine / cross-lane / environment-flaky. Don't `head` past the `linkd.autoShortcut` / "simulated STT" noise.
- Do NOT revert another lane's change or "fix" their stale test to make your gate green — surface it to team-lead; the decision may not be final.
- Pin A/B candidates as explicit literal strings, never `nil → production fragment`, which can drift under you.
- Expect your uncommitted diff to be reviewed, integrated, and possibly partially deduped by the orchestrator who owns commits.
