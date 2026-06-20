---
name: fm-availability
description: Foundation Models availability on the dev Mac — gated off (Apple Intelligence not enabled), observed 2026-06-20
metadata:
  type: project
---

Foundation Models is **unavailable** on the dev Mac. Observed 2026-06-20 via `SystemLanguageModel.default.availability` returning `.unavailable(.appleIntelligenceNotEnabled)`.

**Why:** Apple Intelligence is not enabled in System Settings on this machine. The hardware may be eligible but the feature is off, or the model has not been downloaded.

**How to apply:** All live-cleanup tests (`testFillersOnlyProducesNonEmptyOutput`, etc.) will XCTSkip on this Mac. Cleanup quality is `[inferred]` pending P13 dogfood on a machine with Apple Intelligence enabled. This is expected behavior — the graceful-fallback path is verified; real cleanup quality is deferred. Do not treat skips as passes.
