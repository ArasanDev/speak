---
name: phase-a-rearm
description: Phase A dictation-flow spec — re-arm watchdog, non-blocking init, IM non-blocking, single-instance guard, tap-disabled watchdog, test coverage
metadata:
  type: project
---

Phase A of specs/dictation-flow.md implemented and verified (build/test/lint/moat green). 2026-06-21.

**Why:** The live bug was `DictationController.startMonitoring()` calling `monitor.start()` once at launch; on permission-denied it returned forever — granting AX afterward did nothing until relaunch. Phase A fixes the entire lifecycle.

**Key decisions and patterns:**

1. **Single-owner thread model** (advisor-recommended): the dedicated run-loop thread is the sole owner of `CFMachPort`/`CFRunLoopSource`/tap state. `init()` spawns it and returns immediately (no semaphore). `start()` only sets `armingDesired` flag + wakes the loop via `CFRunLoopWakeUp`. All tap mutations are on-thread.

2. **Re-arm watchdog**: `CFRunLoopTimer` at 100ms fires on the run-loop thread. While `armingDesired && !isArmed`, polls `AXIsProcessTrustedWithOptions([prompt:false])` silently. On untrusted→trusted edge: calls `buildTap()` on-thread. Once armed: timer continues (handles tapDisabled recovery too). `wasTrusted` flag for edge detection. `NSLock` for the shared flags.

3. **AsyncStream lifetime**: `AsyncStream.makeStream()` (Swift 5.9, SE-0388 [verified]) avoids the IUO `var cont: ...!` pattern that the moat scanner flags. Stream is created once in init, stable for monitor lifetime — consumers don't re-subscribe after re-arm.

4. **`armStateChanges: AsyncStream<Bool>`**: yields `true`/`false` when tap arms/disarms. `DictationController` consumes this on a Task to clear/set `permissionsNeeded` on `@MainActor`.

5. **Permission model** (spec §2): AX alone gates tap. IM is requested for registration only. `OnboardingStateMachine.blockingPermissions` now contains only `.microphone` and `.accessibility`. IM has its own step but `isComplete` is true when Mic+AX granted regardless of IM.

6. **Tap-disabled watchdog** (spec §3): `TapRestartRateLimiter` — pure value type, injectable timestamps, 5 restarts / 2s window (Loop OSS [decision]). `NSWorkspace.didWakeNotification` → schedules re-arm 3s after wake via non-repeating `CFRunLoopTimer` (AltTab pattern [decision]).

7. **Single-instance guard**: `NSRunningApplication.runningApplications(withBundleIdentifier: "com.speak.app")`, filter out self by processIdentifier, activate + terminate if another found. Runs before `DictationController` construction.

8. **CoreFoundation added to moat allowlist** in `MoatAuditTests.swift` (CFRunLoop/CFRunLoopTimer). Previously only needed CoreGraphics.

**API verifications (2026-06-21):**
- `CFRunLoopTimerCreate` + `CFRunLoopTimerCallBack` + `CFRunLoopAddTimer` [verified: swiftc -typecheck macOS SDK]
- `NSWorkspace.didWakeNotification` on `NSWorkspace.shared.notificationCenter` [verified: AppKit docs — NOT NotificationCenter.default]
- `NSRunningApplication.runningApplications(withBundleIdentifier:)` [verified: AppKit]
- `AsyncStream.makeStream()` [verified: Swift 5.9+, SE-0388]
- `AXIsProcessTrustedWithOptions` with `[kAXTrustedCheckOptionPrompt: false]` — silent poll, safe at 100ms cadence [verified: ApplicationServices SDK]

**Test coverage:**
- `PhaseARearmTests.swift` (NEW): 17 tests — `TapRestartRateLimiter` (pure, injected timestamps) + re-arm edge-logic invariants
- `OnboardingFlowTests.swift`: updated for Phase A (IM non-blocking); 4 new tests, 3 updated assertions
- Key test: `inputMonitoringMissing_withCompletedFlag_isComplete()` asserts `isComplete==true` when only IM is missing — the discriminating Phase A invariant

**How to apply:** When touching HotkeyMonitor — remember the single-owner pattern (no touching tap state off the run-loop thread). When touching OnboardingStateMachine — remember IM is non-blocking; only Mic+AX in `blockingPermissions`. Never add `var cont: ...!` IUO in production code — use `AsyncStream.makeStream()` instead.
