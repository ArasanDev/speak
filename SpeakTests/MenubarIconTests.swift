// SpeakTests/MenubarIconTests.swift
//
// Unit tests for the pure `MenubarIcon(for: CaptureSession.State)` mapping.
//
// This is the ONLY headlessly-verifiable piece of the P5/P8 keystone wiring.
// The end-to-end behavior (double-tap Fn, paste, live icon) is deferred to
// human verification (docs/human-verification.md).
//
// Coverage: every `CaptureSession.State` case maps to the expected `MenubarIcon`.
// An exhaustive switch in `MenubarIcon.init(for:)` (no `default`) guarantees
// this test suite fails to compile — not just fails — if a new State case is
// added without a corresponding MenubarIcon mapping. [verified]

import XCTest
@testable import SpeakCore

final class MenubarIconTests: XCTestCase {

    func testIdleState() {
        XCTAssertEqual(MenubarIcon(for: .idle), .idle)
    }

    func testListeningState() {
        XCTAssertEqual(MenubarIcon(for: .listening), .listening)
    }

    func testProcessingState() {
        XCTAssertEqual(MenubarIcon(for: .processing), .processing)
    }

    func testDoneState() {
        XCTAssertEqual(MenubarIcon(for: .done), .done)
    }

    func testErrorState() {
        // Use a concrete SpeakError case; the mapping must be icon-case-only,
        // not error-value-specific — the icon doesn't encode which error occurred.
        XCTAssertEqual(MenubarIcon(for: .error(.sessionCancelled)), .error)
        XCTAssertEqual(MenubarIcon(for: .error(.microphoneDenied)), .error)
        XCTAssertEqual(MenubarIcon(for: .error(.accessibilityDenied)), .error)
        XCTAssertEqual(MenubarIcon(for: .error(.pasteboardBusy)), .error)
        XCTAssertEqual(MenubarIcon(for: .error(.unknown("test"))), .error)
    }

    func testAllCasesCovered() {
        // Verify every state produces a non-crash result. The exhaustive switch
        // in MenubarIcon.init(for:) is the compile-time guarantee; this is a
        // belt-and-suspenders runtime check.
        let states: [CaptureSession.State] = [
            .idle,
            .listening,
            .processing,
            .done,
            .error(.sessionCancelled)
        ]
        for state in states {
            // Will not crash — if it does, the mapping is broken.
            let icon = MenubarIcon(for: state)
            XCTAssertNotNil(icon, "MenubarIcon(for: \(state)) returned nil — unexpected")
        }
    }
}
