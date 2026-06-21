// SpeakTests/OverlayControllerTests.swift
//
// H3 unit tests for `OverlayController`.
//
// PURPOSE:
//   Construct-and-assert tests for the overlay state-machine wiring extracted
//   from `DictationController` by H3. These are LOGIC / WIRING assertions —
//   they verify the model transitions correctly across
//   listening → processing → done → stop. They do NOT assert on physical
//   panel visibility (`orderFrontRegardless` / `orderOut`) — those are live
//   window-server effects that require a running display server and manual
//   dogfooding to verify.
//
// APPROACH:
//   - Construct `OverlayController` on `@MainActor`.
//   - Assert model state after `start(...)`, `transition(to:)`, and `stop()`.
//   - Supply a nil-returning partials provider where the stream path is not
//     under test (avoids spawning real async tasks in wiring tests).
//   - Use a short `Task { }.value` hop where needed to let the async `start`
//     Task schedule (even if it exits early) without blocking the test runner.
//
// TAGS: H3 (acceleration-plan.md), OverlayController, OverlayViewModel
//
// [decision: @MainActor-isolated because OverlayController is @MainActor and
//  NSPanel construction requires the main thread per macOS/AppKit convention.]

import XCTest
@testable import Speak

@MainActor
final class OverlayControllerTests: XCTestCase {

    // MARK: - Fixture

    private var controller: OverlayController!

    override func setUp() async throws {
        try await super.setUp()
        controller = OverlayController()
    }

    override func tearDown() async throws {
        controller = nil
        try await super.tearDown()
    }

    // MARK: - Initial state

    /// OverlayViewModel starts in .listening state (the reset default).
    func testInitialState_isListening() {
        XCTAssertEqual(
            controller.overlayModel.overlayState, .listening,
            "OverlayController must initialise the model in .listening state."
        )
    }

    func testInitialPartialText_isEmpty() {
        XCTAssertEqual(
            controller.partialText, "",
            "OverlayController.partialText must be empty at init."
        )
    }

    // MARK: - start() transitions to .listening

    /// `start(partialsProvider:)` resets the model to .listening and clears partialText.
    func testStart_setsListeningState() async {
        // Put the model in a dirty state first.
        controller.overlayModel.overlayState = .done
        controller.overlayModel.partialText = "stale text"

        // Start with a nil-returning provider (no stream to drain).
        controller.start { nil }

        // The transition is synchronous before the async drain task starts.
        XCTAssertEqual(
            controller.overlayModel.overlayState, .listening,
            "start() must set overlayState to .listening before the partials drain starts."
        )
        XCTAssertEqual(
            controller.overlayModel.partialText, "",
            "start() must clear overlayModel.partialText."
        )
        XCTAssertEqual(
            controller.partialText, "",
            "start() must clear controller.partialText."
        )
    }

    // MARK: - transition(to:) state machine

    /// transition to .processing sets the model state.
    func testTransition_toProcessing_setsState() {
        controller.overlayModel.overlayState = .listening

        controller.transition(to: .processing)

        XCTAssertEqual(
            controller.overlayModel.overlayState, .processing,
            "transition(to: .processing) must set overlayModel.overlayState to .processing."
        )
    }

    /// transition to .done sets the model state.
    func testTransition_toDone_setsState() {
        controller.overlayModel.overlayState = .processing

        controller.transition(to: .done)

        XCTAssertEqual(
            controller.overlayModel.overlayState, .done,
            "transition(to: .done) must set overlayModel.overlayState to .done."
        )
    }

    /// Full state-machine walk: listening → processing → done, then stop.
    /// This mirrors the happy-path flow in `DictationController.endDictation()`.
    func testStateMachine_listeningToProcessingToDone() {
        // Simulate start().
        controller.start { nil }
        XCTAssertEqual(controller.overlayModel.overlayState, .listening)

        // Simulate endDictation() phase 1: transition to processing.
        controller.transition(to: .processing)
        XCTAssertEqual(controller.overlayModel.overlayState, .processing)

        // Simulate endDictation() phase 2: transition to done.
        controller.transition(to: .done)
        XCTAssertEqual(controller.overlayModel.overlayState, .done)

        // Simulate stop() after done flash.
        controller.stop()
        // stop() resets to .listening (ready for next dictation).
        XCTAssertEqual(
            controller.overlayModel.overlayState, .listening,
            "stop() must reset overlayState to .listening for the next dictation cycle."
        )
    }

    // MARK: - stop() resets all state

    func testStop_clearsPartialText() {
        controller.overlayModel.partialText = "in progress text"
        controller.stop()
        XCTAssertEqual(
            controller.overlayModel.partialText, "",
            "stop() must clear overlayModel.partialText."
        )
        XCTAssertEqual(
            controller.partialText, "",
            "stop() must clear controller.partialText."
        )
    }

    func testStop_resetsOverlayStateToListening() {
        controller.overlayModel.overlayState = .done
        controller.stop()
        XCTAssertEqual(
            controller.overlayModel.overlayState, .listening,
            "stop() must reset overlayState to .listening."
        )
    }

    // MARK: - createPanel() is idempotent

    /// Calling createPanel() twice must not crash or create a second panel.
    /// (The panel is private; we verify there's no crash or assertion failure.)
    func testCreatePanel_isIdempotent() {
        // The panel constructor touches AppKit; calling it in a test is safe
        // because H2 TEST_HOST provides a running NSApplication.
        // [honesty boundary: we only verify no crash; we don't assert on the
        //  panel's internal state because it's private.]
        XCTAssertNoThrow(controller.createPanel(), "First createPanel() must not throw or crash.")
        XCTAssertNoThrow(controller.createPanel(), "Second createPanel() must be a no-op (idempotent).")
    }
}
