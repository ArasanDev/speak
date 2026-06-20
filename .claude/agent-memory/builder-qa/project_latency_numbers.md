---
name: project-latency-numbers
description: Measured headless latency numbers from LatencyAndAccuracyTests.swift on the dev Mac (fixture-fed, no live mic/paste/FM).
metadata:
  type: project
---

## Measured headless latency (loop run #11, 2026-06-21)

**Context:** Fixture `hello_speech.caf` (1.3s, synthetic `say` speech, 16kHz mono Float32).
All numbers are file-fed (no mic), no paste, no FM cleanup. 5 trials after 1 warm-up.

**First-partial latency** (`L_partial`, benchmark.md §7 budget p95 < 200 ms):
- p50 = **42 ms** (budget: < 100 ms) ✓
- p95 = **43 ms** (budget: < 200 ms) ✓
- Status: **WITHIN budget** [verified — measured, headless proxy]

**Local pipeline latency** (headless slice of `L_e2e`, raw-fallback path, budget < 1.0 s median):
- median = **60 ms** (budget: < 1000 ms) ✓
- p95 = **63 ms**
- Status: **WITHIN budget** [verified — measured, headless proxy]
- NOTE: Excludes live paste (NSPasteboard + CGEvent) and live FM cleanup. Full stop→paste deferred.

**WER harness:** Implemented, unit-tested. Demo on fixture: "Cased in one, two, three." vs "Testing one two three" → high WER (expected for synthetic speech). Harness correct; full §6 corpus is data dependency.

**Why:** benchmark.md §7 requires measured numbers. These are the headless-measurable slice.

**How to apply:** Update progress.md with these numbers. Full L_e2e (incl. paste + FM) deferred to docs/human-verification.md.
