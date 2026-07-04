// SpeakTests/PhaseARearmTests.swift
//
// Unit tests for Phase A re-arm logic:
//   1. TapRestartRateLimiter — pure value type, injectable timestamps.
//   2. Re-arm edge invariants — the untrusted→trusted transition that
//      should trigger a tap build (exercised via the pure state logic).
//
// These tests are headless — no live CGEventTap, no run loop dependency.
// The live re-arm (AX grant → tap arms within ~0.2 s) is [deferred — human
// verification required] per the standard deferred row.

@testable import SpeakCore
import XCTest

// MARK: - TapRestartRateLimiter Tests

final class TapRestartRateLimiterTests: XCTestCase {

    // Default limiter: 5 restarts / 2 s window (Loop OSS [decision]).
    private var limiter = TapRestartRateLimiter()

    override func setUp() {
        super.setUp()
        limiter = TapRestartRateLimiter()
    }

    // MARK: Basic allow / deny

    func testFirstAttemptAllowed() {
        let allowed = limiter.recordAttempt(now: 0.0)
        XCTAssertTrue(allowed, "First restart should always be allowed")
    }

    func testFiveAttemptsAllowed() {
        // 5 attempts within the 2 s window — all should be allowed.
        for idx in 0..<5 {
            let allowed = limiter.recordAttempt(now: Double(idx) * 0.1)
            XCTAssertTrue(allowed, "Attempt \(idx+1) should be allowed (cap not reached)")
        }
    }

    func testSixthAttemptDenied() {
        for idx in 0..<5 {
            _ = limiter.recordAttempt(now: Double(idx) * 0.1)
        }
        let denied = limiter.recordAttempt(now: 0.5)
        XCTAssertFalse(denied, "6th attempt within window should be denied (cap=5)")
    }

    // MARK: Window expiry

    func testAttemptsOutsideWindowAreAllowedAgain() {
        // Fill the cap at t=0..0.4
        for i in 0..<5 {
            _ = limiter.recordAttempt(now: Double(i) * 0.1)
        }
        // At t=2.5, the window (2 s) has expired for all previous attempts.
        let allowed = limiter.recordAttempt(now: 2.5)
        XCTAssertTrue(allowed, "After window expires, attempts should be allowed again")
    }

    func testPartialWindowExpiry() {
        // 3 attempts at t=0, 2 more at t=1.5 (the first 3 are now outside a 2s window at t=2.0)
        for _ in 0..<3 {
            _ = limiter.recordAttempt(now: 0.0)
        }
        for _ in 0..<2 {
            _ = limiter.recordAttempt(now: 1.5)
        }
        // At t=2.1, the 3 attempts at t=0 are outside window (2.1 - 0 > 2.0),
        // only the 2 at t=1.5 remain. Count=2, cap=5, so allowed.
        let allowed = limiter.recordAttempt(now: 2.1)
        XCTAssertTrue(allowed, "Entries outside window should be pruned (count was 5, pruned to 2)")
    }

    // MARK: Reset

    func testResetAllowsImmediateRestarts() {
        for i in 0..<5 {
            _ = limiter.recordAttempt(now: Double(i) * 0.1)
        }
        // Would be denied without reset.
        limiter.reset()
        let allowed = limiter.recordAttempt(now: 0.5)
        XCTAssertTrue(allowed, "After reset, attempts should be allowed again immediately")
    }

    func testResetAndRefillCap() {
        for idx in 0..<5 { _ = limiter.recordAttempt(now: Double(idx) * 0.1) }
        limiter.reset()
        for idx in 0..<5 { _ = limiter.recordAttempt(now: 10.0 + Double(idx) * 0.1) }
        let denied = limiter.recordAttempt(now: 10.5)
        XCTAssertFalse(denied, "Cap should be reinstated after reset+refill")
    }

    // MARK: Custom cap and window

    func testCustomCapOf2() {
        var limiter = TapRestartRateLimiter(maxRestarts: 2, windowSeconds: 1.0)
        XCTAssertTrue(limiter.recordAttempt(now: 0.0))
        XCTAssertTrue(limiter.recordAttempt(now: 0.1))
        XCTAssertFalse(limiter.recordAttempt(now: 0.2), "3rd attempt should exceed cap=2")
    }

    func testCustomWindow() {
        var limiter = TapRestartRateLimiter(maxRestarts: 1, windowSeconds: 0.5)
        _ = limiter.recordAttempt(now: 0.0)
        // At t=0.6, window=0.5 → previous entry expired
        let allowed = limiter.recordAttempt(now: 0.6)
        XCTAssertTrue(allowed, "Entry outside custom window should be pruned")
    }
}

// MARK: - Re-arm edge logic tests

/// Tests the pure boolean logic that drives the re-arm watchdog decision:
/// "should arm when: AX transitions untrusted→trusted AND armingDesired".
/// These are logic-level tests only; no HotkeyMonitor lifecycle is involved.
final class RearmEdgeLogicTests: XCTestCase {

    /// Simulates the watchdog tick decision: returns true iff arming should be triggered.
    ///
    /// This mirrors the logic in HotkeyMonitor.watchdogTick():
    ///   shouldArm = armingDesired && !isArmed && nowTrusted && !wasTrusted
    private func shouldTriggerArm(
        armingDesired: Bool,
        isArmed: Bool,
        nowTrusted: Bool,
        wasTrusted: Bool
    ) -> Bool {
        armingDesired && !isArmed && nowTrusted && !wasTrusted
    }

    func testAXGrantEdge_triggersArm() {
        // The canonical re-arm scenario: AX just became trusted.
        XCTAssertTrue(
            shouldTriggerArm(armingDesired: true, isArmed: false, nowTrusted: true, wasTrusted: false),
            "Untrusted→trusted edge with armingDesired should trigger arm"
        )
    }

    func testAlreadyTrusted_noRetrigger() {
        // AX was already trusted last tick — no edge, no re-arm.
        XCTAssertFalse(
            shouldTriggerArm(armingDesired: true, isArmed: false, nowTrusted: true, wasTrusted: true),
            "Already trusted (no edge) should not re-trigger arm"
        )
    }

    func testAlreadyArmed_noRetrigger() {
        // Tap already armed — no rebuild needed.
        XCTAssertFalse(
            shouldTriggerArm(armingDesired: true, isArmed: true, nowTrusted: true, wasTrusted: false),
            "Already armed should not rebuild the tap"
        )
    }

    func testArmingDesiredFalse_noArm() {
        // start() was not called — don't arm.
        XCTAssertFalse(
            shouldTriggerArm(armingDesired: false, isArmed: false, nowTrusted: true, wasTrusted: false),
            "armingDesired==false should prevent arm even if AX just became trusted"
        )
    }

    func testUntrustedRemains_noArm() {
        // AX is still not trusted — no edge.
        XCTAssertFalse(
            shouldTriggerArm(armingDesired: true, isArmed: false, nowTrusted: false, wasTrusted: false),
            "Still untrusted should not arm"
        )
    }

    func testRevocationEdge_noArm() {
        // AX was trusted but is now revoked (trusted→untrusted).
        // Not an arm event (teardown is handled separately).
        XCTAssertFalse(
            shouldTriggerArm(armingDesired: true, isArmed: false, nowTrusted: false, wasTrusted: true),
            "Revocation (trusted→untrusted) should not trigger arm"
        )
    }
}
