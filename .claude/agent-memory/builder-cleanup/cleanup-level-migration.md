---
name: cleanup-level-migration
description: CleanupLevel enum changed from 3 cases (basic/balanced/thorough) to 4 (none/light/medium/high) in W4.1 — rawValues changed, migration notes
metadata:
  type: project
---

W4.1 extended `CleanupLevel` from 3 to 4 cases. The mapping:
- old `basic` → new `light` (rawValue: "light")
- old `balanced` → new `medium` (rawValue: "medium") [new default]
- old `thorough` → new `high` (rawValue: "high")
- new `none` → no model call; engine skips LLM pass entirely

**Why:** market converging on None/Light/Medium/High (Wispr Auto Cleanup pattern); "none" is the transparency moat signal.

**Migration:** old stored rawValues (basic/balanced/thorough) no longer decode; SettingsStore.cleanupLevel getter falls back to `.medium`. Pre-release clean break — no migration shim. [decision W4.1]

**How to apply:** W3 Settings UI wiring targets `.none/.light/.medium/.high` — not the old 3-level set. When auditing SettingsStore tests, the default is now `.medium` (not `.balanced`). `CleanupLevel.allCases.count == 4` (not 3).

**Optional.none collision:** `CleanupLevel.none` is a genuine enum case but collides with Swift's `Optional.none`. In tests, always use `CleanupLevel.none` (fully qualified) to avoid the ambiguity.

Related: [[session-lifecycle-decision]]
