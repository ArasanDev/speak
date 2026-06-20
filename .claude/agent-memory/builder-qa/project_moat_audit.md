---
name: project-moat-audit
description: Status of the benchmark.md §3 BEAT row structural-moat audit and verification tests added in loop run #11.
metadata:
  type: project
---

## Moat audit implementation (loop run #11, 2026-06-21)

**Fact:** Automated verification tests added for the benchmark.md §3 BEAT moat rows.

**Files created:**
- `SpeakTests/MoatAuditTests.swift` — 9 XCTest audit tests, all PASS
- `SpeakTests/LatencyAndAccuracyTests.swift` — 2 latency measurement tests + WER harness (10 tests total)
- `scripts/verify-moat.sh` — standalone shell audit (7/7 PASS, no Xcode needed)
- `Makefile` — added `make verify-moat` target

**Test count:** 68 prior → 83 now (15 new), 5 XCTSkip (pre-existing live-FM), 0 failures.

**Why:** Per task spec: turn autonomously-verifiable BEAT rows from asserted to measured/audited.

**How to apply:** When running `make test`, MoatAuditTests runs automatically. When wanting a fast pre-build check without Xcode, run `make verify-moat`. Both are re-runnable and wired into CI.
