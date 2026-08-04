# SM-2 / D1 — the `fix` fragment A/B (live Foundation Models, decided by reading outputs)

> **Research header** — Question: "which `fix`-category system-prompt fragment
> (A: bug-report framing vs B: imperative + anti-invention guard) produces better
> live Foundation Models output?" · Date: 2026-06-30 · Status: **evidence**

> **Status**: `[verified]` live run 2026-06-30, greedy decoding (deterministic), Agent
> profile · fix category · medium intensity. Harness: `FixABTests` under the `Eval`
> scheme (SPEAK_EVAL=1 reaches the runner). Raw log: scratchpad `fixab.log`.
> Both candidates ran through the **identical** production prompt — only the fix
> category fragment was swapped (string substitution), so the comparison is fair.

## The two candidates
- **A (current production, "bug-report")** — `"Output ONLY a structured bug report:
  state what is broken and where. Do not propose a fix or suggest a solution."`
  Chosen earlier because imperative framing was believed to make the 3B *pre-solve*.
- **B (D1 proposal, "imperative" + F3 anti-invention guard)** — `"Rewrite the spoken
  words as a single clear imperative instruction telling the coding agent what to fix
  and where. Do not write the fix, propose a solution, or add any file, function,
  error, or detail the speaker did not say."`

## The outputs (raw → A → B)

| # | spoken (raw) | A (bug-report) | B (imperative) |
|---|---|---|---|
| 1 | fix the bug in capture session where paste only works the first time | Fix the bug in capture session where paste only works the first time. | *(identical)* |
| 2 | um the the paste isn't working after the first dictation can you fix that | The paste isn't working after the first dictation. | Fix the paste issue after the first dictation. |
| 3 | there's a crash when i open the history pane fix it | Crash when opening the history pane. | Fix the crash when opening the history pane. |
| 4 | the login button on the settings page doesn't do anything fix it | Login button on the settings page does not do anything. | Fix the login button on the settings page. |
| 5 | fix the off by one in the loop counter | Fix the off-by-one error in the loop counter. | Fix the off by one in the loop counter. |
| 6 | something's wrong with the audio it cuts out sometimes please fix | Audio issue: Audio cuts out occasionally. | Fix the audio issue so it doesn't cut out. |

## What the data says

1. **The original fear did NOT reproduce.** In NO case did B (imperative) write a fix,
   propose an implementation, or pre-solve. The "imperative makes the 3B solve it"
   finding that justified fragment A does not hold under greedy decoding + the F3 guard.
   This **clears the D1 risk** the user flagged.
2. **Neither candidate hallucinated.** No invented file paths, function names, errors,
   or symptoms in either column. F3 (preserve-don't-invent) held for both.
3. **B is consistently a well-formed agent directive** ("Fix X where Y") — exactly what
   Agent mode should emit FOR a downstream coding agent. **A is inconsistent in form**:
   a verb-less fragment (#3, #4), a label format with a duplicated word (#6:
   "Audio issue: Audio cuts out…"). A reads like a sticky note, not an instruction.
4. **Mild trade-off:** B lightly abstracted symptoms twice (#2 "paste isn't working" →
   "paste issue"; #4 dropped "doesn't do anything"). A preserved those phrasings better —
   but at the cost of non-directive, inconsistent shape. This is lossiness, not invention.

## Recommendation (user decides — this was the "decide by live A/B" checkpoint)
**Switch the `fix` fragment to B (imperative).** It produces a consistent imperative
instruction, never pre-solved (the one risk that mattered), never invented, and matches
the Agent-mode contract (speech → instruction FOR an agent). A's bug-report framing
yields inconsistent, sometimes malformed fragments. If symptom-preservation is judged
more important than directive form, keep A — but the evidence favors B.
