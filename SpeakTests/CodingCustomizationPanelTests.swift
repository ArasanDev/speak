// SpeakTests/CodingCustomizationPanelTests.swift
//
// P-Code: tests for `CodingCustomizationPanel` — the second, dynamically-sized panel
// opened from the base HUD's "Code" Agent category.
//
// PURPOSE:
//   - CONSTRUCT-AND-ASSERT guards on the focus-steal flags and z-order level, mirroring
//     `TranscriptOverlayPanelTests`.
//   - Pure-function tests for `anchoredOrigin(baseFrame:contentSize:gap:)`, the anchoring
//     math that keeps this panel horizontally centered on and directly above the base HUD
//     panel's frame — the same "pure function over CGRect" pattern used by
//     `TranscriptOverlayPanel.indexOfScreen`.
//
// Live panel visibility / resize behaviour (actual window-server effects) is
// [unverified — requires human dogfood], matching the convention set by the other
// overlay panel test files in this suite.

import AppKit
@testable import Speak
import XCTest

@MainActor
final class CodingCustomizationPanelTests: XCTestCase {

    // MARK: - Fixture

    private var panel: CodingCustomizationPanel!

    override func setUp() async throws {
        try await super.setUp()
        panel = CodingCustomizationPanel(overlayModel: OverlayViewModel())
    }

    override func tearDown() async throws {
        panel = nil
        try await super.tearDown()
    }

    // MARK: - Focus-steal guards (same contract as TranscriptOverlayPanel)

    func testStyleMask_containsNonactivatingPanel() {
        XCTAssertTrue(
            panel.styleMask.contains(.nonactivatingPanel),
            "CodingCustomizationPanel must have .nonactivatingPanel in its styleMask."
        )
    }

    func testCanBecomeKey_isFalse() {
        XCTAssertFalse(panel.canBecomeKey, "CodingCustomizationPanel.canBecomeKey must be false.")
    }

    func testCanBecomeMain_isFalse() {
        XCTAssertFalse(panel.canBecomeMain, "CodingCustomizationPanel.canBecomeMain must be false.")
    }

    // MARK: - Collection behavior

    func testCollectionBehavior_canJoinAllSpaces() {
        XCTAssertTrue(panel.collectionBehavior.contains(.canJoinAllSpaces))
    }

    func testCollectionBehavior_fullScreenAuxiliary() {
        XCTAssertTrue(panel.collectionBehavior.contains(.fullScreenAuxiliary))
    }

    // MARK: - Z-order (STACKING contract)

    /// This panel must sit strictly above `.popUpMenu` (CaretOverlayController's level) —
    /// the highest existing overlay panel level — so it always wins z-order ties per the
    /// documented stacking contract in `CodingCustomizationPanel.swift`.
    func testLevel_isAbovePopUpMenu() {
        XCTAssertGreaterThan(
            panel.level.rawValue, NSWindow.Level.popUpMenu.rawValue,
            "CodingCustomizationPanel must sit strictly above .popUpMenu so it is never " +
            "occluded by CaretOverlayController's panel."
        )
    }

    /// This panel must also sit strictly above `.floating` (TranscriptOverlayPanel's level).
    func testLevel_isAboveFloating() {
        XCTAssertGreaterThan(
            panel.level.rawValue, NSWindow.Level.floating.rawValue,
            "CodingCustomizationPanel must sit strictly above .floating so it is never " +
            "occluded by the base HUD panel."
        )
    }

    // MARK: - anchoredOrigin(baseFrame:contentSize:gap:) — pure, testable over CGRect

    /// The panel's x-origin must horizontally center it on the base frame's mid-x.
    func testAnchoredOrigin_centersHorizontallyOnBaseFrame() {
        let baseFrame = CGRect(x: 100, y: 24, width: 340, height: 136)
        let contentSize = CGSize(width: 400, height: 200)
        let origin = CodingCustomizationPanel.anchoredOrigin(
            baseFrame: baseFrame, contentSize: contentSize, gap: 12
        )
        let expectedX = baseFrame.midX - contentSize.width / 2
        XCTAssertEqual(origin.x, expectedX, accuracy: 0.001)
    }

    /// The panel's y-origin must sit `gap` points above the base frame's top edge (maxY).
    func testAnchoredOrigin_sitsGapAboveBaseFrameTop() {
        let baseFrame = CGRect(x: 100, y: 24, width: 340, height: 136)
        let contentSize = CGSize(width: 400, height: 200)
        let origin = CodingCustomizationPanel.anchoredOrigin(
            baseFrame: baseFrame, contentSize: contentSize, gap: 12
        )
        XCTAssertEqual(origin.y, baseFrame.maxY + 12, accuracy: 0.001)
    }

    /// Growing content size (e.g. a section expands) must re-center horizontally around the
    /// same base-frame mid-x rather than growing off to one side.
    func testAnchoredOrigin_widerContentStaysCenteredOnSameBaseFrame() {
        let baseFrame = CGRect(x: 100, y: 24, width: 340, height: 136)
        let narrow = CodingCustomizationPanel.anchoredOrigin(
            baseFrame: baseFrame, contentSize: CGSize(width: 360, height: 120), gap: 12
        )
        let wide = CodingCustomizationPanel.anchoredOrigin(
            baseFrame: baseFrame, contentSize: CGSize(width: 480, height: 120), gap: 12
        )
        // Both remain centered on the same mid-x: narrow.x + 360/2 == wide.x + 480/2 == baseFrame.midX
        XCTAssertEqual(narrow.x + 180, baseFrame.midX, accuracy: 0.001)
        XCTAssertEqual(wide.x + 240, baseFrame.midX, accuracy: 0.001)
    }

    /// A degenerate zero base frame must not crash and produces a deterministic origin.
    func testAnchoredOrigin_zeroBaseFrame_doesNotCrash() {
        let origin = CodingCustomizationPanel.anchoredOrigin(
            baseFrame: .zero, contentSize: CGSize(width: 400, height: 200), gap: 12
        )
        XCTAssertEqual(origin.x, -200, accuracy: 0.001)
        XCTAssertEqual(origin.y, 12, accuracy: 0.001)
    }
}
