// SpeakTests/InputValidationFixTests.swift
//
// Regression tests for the validation-phase input-seam fixes (Batch C).
// Each test pins a confirmed bug from specs/validation-findings.md so it cannot
// silently regress. These are PURE, deterministic tests — no CGEventTap, no live
// run loop, no real Cmd+V.

import XCTest
import CoreGraphics
@testable import SpeakCore

// NOTE: modifierMask(forKeyCode:) tests (NEW-6, incl. the Option + fail-closed
// cases) live in HotkeyMonitorTests.swift's `ModifierMaskTests` to keep all
// modifier-mask coverage in one place.

// MARK: - C1: DoubleTapDetector desync after an out-of-band stop

/// After a session ends OUTSIDE the monitor's knowledge (Escape, CLI --stop,
/// error), `DoubleTapDetector.isCapturing` stays `true` unless reset. The next
/// double-tap is then swallowed — the user must tap a THIRD time. `notifySessionEnded()`
/// calls `reset()` on the run-loop thread to fix this; here we prove the pure
/// detector logic: the bug without reset, the fix with it.
final class DoubleTapDesyncTests: XCTestCase {

    private let window: TimeInterval = 0.4

    /// Reproduces the bug: without a reset after an out-of-band stop, the next
    /// double-tap does NOT start (it takes a third tap).
    func testDesyncWithoutResetSwallowsNextDoubleTap() {
        var d = DoubleTapDetector()
        // Double-tap to start a session.
        XCTAssertNil(d.register(tapAt: 0.0, window: window))
        XCTAssertEqual(d.register(tapAt: 0.1, window: window), .startCapture)

        // Session ends out-of-band (e.g. Escape) — detector NOT reset (the bug).
        // Next double-tap:
        XCTAssertEqual(d.register(tapAt: 1.0, window: window), .stopCapture,
                       "tap 1 returns .stopCapture to an already-idle engine (no-op)")
        XCTAssertNil(d.register(tapAt: 1.1, window: window),
                     "tap 2 only records — NO .startCapture → user must tap a third time (the bug)")
    }

    /// Verifies the fix: resetting after the out-of-band stop (what
    /// `notifySessionEnded()` does) makes the next double-tap start on the 2nd tap.
    func testResetAfterStopRestoresCleanDoubleTap() {
        var d = DoubleTapDetector()
        XCTAssertNil(d.register(tapAt: 0.0, window: window))
        XCTAssertEqual(d.register(tapAt: 0.1, window: window), .startCapture)

        // notifySessionEnded() → reset() on the run-loop thread.
        d.reset()

        // Next double-tap now behaves like a fresh gesture.
        XCTAssertNil(d.register(tapAt: 1.0, window: window),
                     "tap 1 is a clean first tap after reset")
        XCTAssertEqual(d.register(tapAt: 1.1, window: window), .startCapture,
                       "tap 2 within window → .startCapture (desync fixed)")
    }
}

// MARK: - C3: paste inter-event gap does not drop events

/// With a non-zero `pasteEventGap`, all four Cmd+V events must still be posted in
/// order (the gap must not skip or reorder events). Uses a 1 ms gap to stay fast.
final class PasteEventGapTests: XCTestCase {

    func testAllFourEventsPostedWithNonZeroGap() async throws {
        let recorder = PasteSideEffectRecorder()
        let writer = PasteboardWriter(
            isAccessibilityTrusted: { true },
            isFocusedFieldSecure: { false },
            settle: .zero,
            pasteEventGap: .milliseconds(1),   // non-zero, but fast
            writeClipboard: { recorder.recordClipboardWrite($0) },
            postEvent: { recorder.recordPostedEvent($0) }
        )
        do {
            try await writer.insert("gap test")
        } catch SpeakError.pasteboardBusy {
            return  // headless CI — CGEvent infra unavailable; acceptable
        }
        XCTAssertEqual(recorder.postedEventCount, 4,
                       "A non-zero inter-event gap must still post all 4 Cmd+V events")
    }
}
