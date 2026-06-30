// SpeakTests/CaretOverlayControllerTests.swift
//
// Nil-safety smoke tests for CaretOverlayController.
// CaretLocator is inaccessible in a test host (no real AX context, no target PID),
// so these tests verify the controller behaves correctly in the nil-caret path:
// no crash, no hang, no force-unwrap. Positioning and panel visibility are
// [unverified — live dogfood only] per the CaretOverlayController header.

@testable import Speak
import Testing

@Suite("CaretOverlayController — nil-safety smoke tests")
@MainActor
struct CaretOverlayControllerTests {

    /// hide() before any show() must be a silent no-op (panel was never created).
    @Test("hide() when never shown is a no-op")
    func hideWhenNeverShown() {
        let controller = CaretOverlayController()
        // Must not crash or throw.
        controller.hide()
    }

    /// show() with pid=0 (no real process) — CaretLocator returns nil.
    /// The controller must not crash and must not surface a warning log.
    @Test("show() with pid=0 is a graceful no-op when CaretLocator returns nil")
    func showWithZeroPID() {
        let controller = CaretOverlayController()
        // pid_t(0) has no AX context — CaretLocator will return nil.
        // The only observable outcome is: no crash.
        controller.show(partialText: "hello", frontmostPID: 0)
        // Clean up to release any resources allocated for the happy path.
        controller.hide()
    }

    /// update() when the panel was never shown must be a silent no-op
    /// (model update is safe even when no panel exists).
    @Test("update() when no panel is showing is a no-op")
    func updateWhenNotShowing() {
        let controller = CaretOverlayController()
        // Must not crash — model mutation is always safe regardless of panel state.
        controller.update(partialText: "partial text update")
    }

    // MARK: - P2.3 showProcessing tests

    /// showProcessing("") must not crash and must set isProcessing.
    @Test("showProcessing() with empty string does not crash and sets isProcessing")
    func showProcessingEmptyStringDoesNotCrash() {
        let controller = CaretOverlayController()
        controller.showProcessing(rawText: "")
        #expect(controller.model.isProcessing == true)
        controller.hide()
    }

    /// showProcessing(rawText:) sets model.partialText + isProcessing; hide() clears both.
    @Test("showProcessing() sets model state; hide() resets it")
    func showProcessingSetsModelStateAndHideClears() {
        let controller = CaretOverlayController()
        controller.showProcessing(rawText: "hello world")
        #expect(controller.model.isProcessing == true)
        #expect(controller.model.partialText == "hello world")
        controller.hide()
        #expect(controller.model.isProcessing == false)
        #expect(controller.model.partialText == "")
    }
}
