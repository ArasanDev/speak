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

    /// Terminal-emulator frontmost apps must never get the caret mini-panel:
    /// the shell cursor is not a text-field caret — the panel lands on the
    /// prompt and reads as a stray square while the main capsule HUD is the
    /// intended surface. Gate happens before `model.partialText` is written,
    /// so an empty model proves suppression.
    @Test("show() suppresses the overlay for terminal bundle IDs")
    func showSuppressesForTerminals() {
        let controller = CaretOverlayController()
        controller.show(partialText: "hello", frontmostPID: 0,
                        bundleID: "com.apple.Terminal")
        #expect(controller.model.partialText == "",
                "Terminal frontmost must suppress the caret overlay entirely.")

        controller.show(partialText: "hello", frontmostPID: 0,
                        bundleID: "dev.warp.Warp-Stable")
        #expect(controller.model.partialText == "",
                "Warp must also be suppressed.")
        controller.hide()
    }

    /// A non-terminal bundle ID must not be suppressed — the feature still
    /// reaches CaretLocator (nil-safe path here since pid=0 has no AX context).
    @Test("show() does not suppress for non-terminal bundle IDs")
    func showAllowsNonTerminalApps() {
        let controller = CaretOverlayController()
        controller.show(partialText: "hello", frontmostPID: 0,
                        bundleID: "com.microsoft.VSCode")
        #expect(controller.model.partialText == "hello",
                "VS Code is a text editor — the caret overlay must not be gated.")

        controller.show(partialText: "hi", frontmostPID: 0, bundleID: nil)
        #expect(controller.model.partialText == "hi",
                "nil bundleID (unresolvable app) must fall through to CaretLocator.")
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
