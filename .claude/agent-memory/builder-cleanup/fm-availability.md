---
name: fm-availability
description: Foundation Models IS available and running live on the dev Mac (confirmed 2026-06-30 via history DB); the real gap is a broken eval-harness env-var plumbing bug, not availability
metadata:
  type: project
---

Foundation Models is **available and running live** on the dev Mac. Confirmed 2026-06-30 by primary evidence: the app's history DB (`~/Library/Application Support/speak/history.sqlite`, table `history`) shows real dictations with `engineId = apple-speech-en-US+foundation-models`, `cleanedText ≠ rawText` (e.g. "I... I think, uh, so I'm trying to dictate a lot" → "I think I'm trying to dictate a lot"), `cleanupSeconds ≈ 0.79–0.85s`, through ~04:38 today.

**Stale prior reading (do NOT reuse):** a 2026-06-20 observation returned `.unavailable(.appleIntelligenceNotEnabled)`. It predates Apple Intelligence being enabled here. Never again claim "FM unavailable / tuning blind" — it is false.

**The real gap is a harness bug, not availability.** `make eval` and `make study` set `SPEAK_EVAL=1`/`SPEAK_STUDY=1` on the **xcodebuild command line**, but xcodebuild does NOT forward that into the **hosted unit-test process**. The live test guards on `ProcessInfo.processInfo.environment["SPEAK_EVAL"] == "1"` → sees nil → `XCTSkip`. Verified 2026-06-30: even `xcodebuild test TEST_RUNNER_SPEAK_EVAL=1 …` still skipped (the `TEST_RUNNER_` prefix injects into the UI-test runner, not this hosted unit test). Root cause: there is **no `.xctestplan`**, and the XcodeGen scheme `Speak.test` action defines **no `environmentVariables`**, so `SPEAK_EVAL` is never in the Test action's environment. **Net: the live FM scoring path has NEVER executed; the ledger has no measured numbers for that reason — not because FM is off.** Fix (flagged for builder-release, not applied): add `environmentVariables` to the XcodeGen scheme's test action or introduce an xctestplan, then re-run. See `research/small-model-prompting-eval.md` §0. Links [[session-lifecycle]].

Apple's published FM facts remain `[verified]`: 4096-token context window (Apple TN3193), ~3B params (WWDC25 s248/s286).
