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
import SpeakCore
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

    /// `start(partialsProvider:levelsProvider:isCleaningUp:)` resets to .listening.
    func testStart_setsListeningState() async {
        // Put the model in a dirty state first.
        controller.overlayModel.overlayState = .done
        controller.overlayModel.partialText = "stale text"

        // Start with nil-returning providers (no stream to drain).
        controller.start(partialsProvider: { nil }, levelsProvider: { nil }, isCleaningUp: false)

        // The transition is synchronous before the async drain tasks start.
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
        controller.start(partialsProvider: { nil }, levelsProvider: { nil }, isCleaningUp: false)
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
    func testCreatePanel_isIdempotent() {
        XCTAssertNoThrow(controller.createPanel(), "First createPanel() must not throw or crash.")
        XCTAssertNoThrow(controller.createPanel(), "Second createPanel() must be a no-op (idempotent).")
    }

    // MARK: - W2.2: .error state

    /// showError(_:) transitions overlay to .error state.
    func testShowError_setsErrorState() {
        controller.showError("Speech engine unavailable")
        XCTAssertEqual(
            controller.overlayModel.overlayState, .error,
            "showError must set overlayState to .error."
        )
    }

    /// showError(_:) stores the reason in errorReason.
    func testShowError_storesReason() {
        let reason = "Test failure reason"
        controller.showError(reason)
        XCTAssertEqual(
            controller.overlayModel.errorReason, reason,
            "showError must store reason in overlayModel.errorReason."
        )
    }

    /// showError(_:) with empty reason stores an empty string.
    func testShowError_emptyReasonStored() {
        controller.showError("")
        XCTAssertEqual(
            controller.overlayModel.errorReason, "",
            "showError with empty reason must store empty string."
        )
    }

    /// stop() after showError clears errorReason and resets state.
    func testStop_afterError_clearsErrorReason() {
        controller.showError("Some error")
        controller.stop()
        XCTAssertNil(
            controller.overlayModel.errorReason,
            "stop() must clear errorReason."
        )
        XCTAssertEqual(
            controller.overlayModel.overlayState, .listening,
            "stop() must reset overlayState to .listening after error."
        )
    }

    // MARK: - W2.2 (updated): onEscapeStop wiring

    /// `onEscapeStop` is nil by default — wiring is not set during OverlayController init.
    func testOnEscapeStop_isNilByDefault() {
        XCTAssertNil(
            controller.onEscapeStop,
            "onEscapeStop must be nil until the caller sets it."
        )
    }

    /// Setting `onEscapeStop` stores the closure and invokes it when called.
    /// This is a wiring-only test — it does NOT exercise the NSEvent global monitor
    /// or the physical Escape key. The actual Escape-key → stop-and-paste behavior
    /// is [unverified — human dogfood required].
    func testOnEscapeStop_storedClosureIsInvokedWhenCalled() {
        var wasCalled = false
        controller.onEscapeStop = { wasCalled = true }

        // Simulate the call path the installEscapeMonitor handler fires.
        controller.onEscapeStop?()

        XCTAssertTrue(
            wasCalled,
            "onEscapeStop closure must be invoked when called — wiring test."
        )
    }

    /// cancelImmediate() hides overlay and resets all state (including error).
    func testCancelImmediate_resetsAllState() {
        controller.showError("Some error")
        controller.cancelImmediate()
        XCTAssertNil(controller.overlayModel.errorReason)
        XCTAssertEqual(controller.overlayModel.overlayState, .listening)
        XCTAssertEqual(controller.overlayModel.level, 0.0)
        XCTAssertEqual(controller.overlayModel.partialText, "")
        XCTAssertEqual(controller.overlayModel.elapsedSeconds, 0)
    }

    /// transition(to: .error) sets the error state via the transition path.
    func testTransition_toError_setsState() {
        controller.transition(to: .error)
        XCTAssertEqual(
            controller.overlayModel.overlayState, .error,
            "transition(to: .error) must set overlayState to .error."
        )
    }

    // MARK: - W2.2: isCleaningUp propagation

    /// start() with isCleaningUp=true sets the model flag.
    func testStart_withCleanupOn_setsIsCleaningUp() {
        controller.start(
            partialsProvider: { nil },
            levelsProvider: { nil },
            isCleaningUp: true
        )
        XCTAssertTrue(
            controller.overlayModel.isCleaningUp,
            "start(isCleaningUp:true) must set overlayModel.isCleaningUp."
        )
    }

    /// start() with isCleaningUp=false clears the model flag.
    func testStart_withCleanupOff_clearsIsCleaningUp() {
        controller.start(
            partialsProvider: { nil },
            levelsProvider: { nil },
            isCleaningUp: false
        )
        XCTAssertFalse(
            controller.overlayModel.isCleaningUp,
            "start(isCleaningUp:false) must clear overlayModel.isCleaningUp."
        )
    }

    // MARK: - W2.2: level reset on transition

    /// transition(to: .processing) resets level to 0.
    func testTransition_toProcessing_resetsLevel() {
        controller.overlayModel.level = 0.8
        controller.transition(to: .processing)
        XCTAssertEqual(
            controller.overlayModel.level, 0.0, accuracy: 1e-9,
            "transition(to: .processing) must reset level to 0."
        )
    }

    // MARK: - Partials drain (1C coverage — real AsyncStream path)
    //
    // Previous tests pass `partialsProvider: { nil }` which exercises only the early-
    // exit path. These tests supply a real `AsyncStream<TranscriptChunk>` so the
    // drain loop, `OverlayTextAccumulator`, and `controller.partialText` are exercised.

    /// A partials stream with a single final chunk must update `partialText`.
    func testPartialsDrain_singleFinalChunk_updatesPartialText() async {
        // Build a stream that yields one final chunk and then finishes.
        let chunk = TranscriptChunk(text: "Hello world", isFinal: true, timestamp: Date())
        let stream: AsyncStream<TranscriptChunk> = AsyncStream { continuation in
            continuation.yield(chunk)
            continuation.finish()
        }

        // Start with the real stream provider.
        controller.start(
            partialsProvider: { stream },
            levelsProvider: { nil },
            isCleaningUp: false
        )

        // Give the drain task a chance to consume the stream (background task → MainActor.run).
        // One Task.yield is enough because the drain task is already scheduled; it
        // consumes the single-element stream and posts back to the main actor.
        // We yield several times to cover the back-and-forth scheduling.
        for _ in 0..<10 {
            await Task.yield()
        }

        XCTAssertEqual(
            controller.partialText, chunk.text,
            "After a single final chunk, controller.partialText must equal the chunk text."
        )
        XCTAssertEqual(
            controller.overlayModel.partialText, chunk.text,
            "After a single final chunk, overlayModel.partialText must equal the chunk text."
        )
    }

    /// Cancelling via stop() before the stream finishes must clear partialText.
    func testPartialsDrain_stopCancelsTask_clearsPartialText() async {
        // Build a stream that never finishes (simulates an ongoing dictation).
        var continuation: AsyncStream<TranscriptChunk>.Continuation!
        let stream: AsyncStream<TranscriptChunk> = AsyncStream { cont in
            continuation = cont
        }

        controller.start(
            partialsProvider: { stream },
            levelsProvider: { nil },
            isCleaningUp: false
        )

        // Yield a partial chunk so there is text in flight.
        continuation.yield(TranscriptChunk(text: "typing…", isFinal: false, timestamp: Date()))
        await Task.yield()

        // Stop before the stream finishes — must cancel the task and clear text.
        controller.stop()
        await Task.yield()

        XCTAssertEqual(
            controller.partialText, "",
            "stop() must clear controller.partialText even when the drain stream is open."
        )
        XCTAssertEqual(
            controller.overlayModel.partialText, "",
            "stop() must clear overlayModel.partialText even when the drain stream is open."
        )

        // Clean up: finish the stream so no continuation is leaked.
        continuation.finish()
    }
}
