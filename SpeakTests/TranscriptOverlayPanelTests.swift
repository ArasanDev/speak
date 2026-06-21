// SpeakTests/TranscriptOverlayPanelTests.swift
//
// H2 regression guard: `TranscriptOverlayPanel` focus-steal prevention flags.
//
// PURPOSE:
//   These tests assert the panel's critical load-bearing configuration flags are
//   set as documented in `TranscriptOverlayPanel.swift`. This is a CONSTRUCT-AND-
//   ASSERT guard — it verifies the flags *are set on the object*, not that the OS
//   actually honours them at runtime. Live behaviour proof (focus not stolen during
//   real dictation) is covered by manual dogfooding, not automated tests.
//
// APPROACH:
//   Construct a `TranscriptOverlayPanel` with a fresh `OverlayViewModel` and
//   assert each flag at the Objective-C/AppKit level immediately after init.
//   The panel is never shown or connected to a real screen — construction alone
//   is enough to verify the flags.
//
// TAGS: H2 (acceleration-plan.md), TranscriptOverlayPanel §FOCUS-STEAL PREVENTION
//       + §COLLECTION BEHAVIOR, benchmark.md §3 (overlay doesn't steal focus)
//
// [decision: MainActor-isolated because NSPanel construction touches AppKit;
//  all AppKit window creation must happen on the main thread per macOS convention.]

import XCTest
import AppKit
@testable import Speak   // H2: requires TEST_HOST=Speak so the App module is importable

@MainActor
final class TranscriptOverlayPanelTests: XCTestCase {

    // MARK: - Fixture

    /// A freshly-constructed panel. Created once per test via setUp so each test
    /// gets a clean instance and there is no shared mutable state between tests.
    private var panel: TranscriptOverlayPanel!

    override func setUp() async throws {
        try await super.setUp()
        panel = TranscriptOverlayPanel(overlayModel: OverlayViewModel())
    }

    override func tearDown() async throws {
        panel = nil
        try await super.tearDown()
    }

    // MARK: - Style mask (§FOCUS-STEAL PREVENTION layer 1)

    /// Assert `.nonactivatingPanel` is in the styleMask — the primary mechanism
    /// that prevents the system from activating this window on click.
    func testStyleMask_containsNonactivatingPanel() {
        XCTAssertTrue(
            panel.styleMask.contains(.nonactivatingPanel),
            "TranscriptOverlayPanel must have .nonactivatingPanel in its styleMask. " +
            "This is the primary focus-steal guard (§FOCUS-STEAL PREVENTION layer 1)."
        )
    }

    // MARK: - canBecomeKey / canBecomeMain (layers 5 + 6)

    /// Assert the panel cannot become the key window (cannot receive keyboard events).
    func testCanBecomeKey_isFalse() {
        XCTAssertFalse(
            panel.canBecomeKey,
            "TranscriptOverlayPanel.canBecomeKey must be false — the panel must " +
            "never intercept keyboard events (§FOCUS-STEAL PREVENTION layer 5)."
        )
    }

    /// Assert the panel cannot become the main window.
    func testCanBecomeMain_isFalse() {
        XCTAssertFalse(
            panel.canBecomeMain,
            "TranscriptOverlayPanel.canBecomeMain must be false — the panel must " +
            "never become the main window (§FOCUS-STEAL PREVENTION layer 6)."
        )
    }

    // MARK: - Collection behaviour (§COLLECTION BEHAVIOR)

    /// Assert the panel joins all Mission Control spaces so dictation HUD is
    /// always visible regardless of which space the user is on.
    func testCollectionBehavior_canJoinAllSpaces() {
        XCTAssertTrue(
            panel.collectionBehavior.contains(.canJoinAllSpaces),
            "TranscriptOverlayPanel must set .canJoinAllSpaces so the HUD is " +
            "visible across all Mission Control spaces."
        )
    }

    /// Assert the panel is visible when a full-screen app is active.
    func testCollectionBehavior_fullScreenAuxiliary() {
        XCTAssertTrue(
            panel.collectionBehavior.contains(.fullScreenAuxiliary),
            "TranscriptOverlayPanel must set .fullScreenAuxiliary so dictation " +
            "works in full-screen apps."
        )
    }

    /// Assert the panel is stationary during Mission Control / Exposé sweeps
    /// so it does not interfere with the user's window management.
    func testCollectionBehavior_stationary() {
        XCTAssertTrue(
            panel.collectionBehavior.contains(.stationary),
            "TranscriptOverlayPanel must set .stationary so the HUD does not " +
            "move during Mission Control sweeps (§COLLECTION BEHAVIOR [decision] spec §4)."
        )
    }

    /// Assert the panel is excluded from Cmd+` window cycling.
    func testCollectionBehavior_ignoresCycle() {
        XCTAssertTrue(
            panel.collectionBehavior.contains(.ignoresCycle),
            "TranscriptOverlayPanel must set .ignoresCycle so the HUD is excluded " +
            "from Cmd+` window cycling (§COLLECTION BEHAVIOR [decision] spec §4)."
        )
    }
}
