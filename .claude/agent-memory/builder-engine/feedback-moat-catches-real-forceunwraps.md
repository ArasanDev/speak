---
name: moat-catches-real-forceunwraps
description: MoatAuditTests.testNoForceUnwrapInProductionCode is a regex-heuristic scanner distinct from SwiftLint's force_unwrapping rule — it caught a genuine force-unwrap (`errText!`) I wrote in ShortcutsCLIExecutor.swift that I hadn't noticed.
metadata:
  type: feedback
---

While building `Speak/SpeakCore/VoiceActions/ShortcutsCLIExecutor.swift` (H-1),
I wrote `(errText?.isEmpty == false ? errText! : nil) ?? "exit code ..."` —
logically safe (guarded by the ternary condition) but still a literal `!`
force-unwrap, which is banned in production code per AGENTS.md §3. `make test`
failed on `MoatAuditTests.testNoForceUnwrapInProductionCode()` (a plain-string
scan for `word-char` immediately followed by `!`), not on `make lint`/SwiftLint.

**Why this matters:** I did not catch this myself in a self-review pass before
running the gates — the moat test caught it. Rewrote with
`errText.flatMap { $0.isEmpty ? nil : $0 } ?? ...` to avoid the unwrap entirely.

**How to apply:** always run the full gate sequence (`make build && make test &&
make lint && make verify-moat`) before declaring a task done, even when a change
"looks obviously safe" — `make test` (via `MoatAuditTests`) is a second,
independent enforcement layer beyond SwiftLint's `force_unwrapping` opt-in rule,
and it caught something a quick self-read missed. Don't skip straight to lint
and assume it's the only gate that checks this rule.
