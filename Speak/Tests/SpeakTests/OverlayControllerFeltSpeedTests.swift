// SpeakTests/OverlayControllerFeltSpeedTests.swift
//
// Felt-speed (input-felt-speed.md §3.3) unit tests for `OverlayController`'s
// settling + transformation state machine. Split out of `OverlayControllerTests.swift`
// to satisfy SwiftLint's `type_body_length` cap — pure test-code motion.
//
// PURPOSE:
//   Verify the felt-speed contract: transition(to: .processing) preserves the raw
//   transcript as provisional `settlingText` instead of wiping to a blank spinner;
//   showTransformation(cleaned:raw:) animates raw→clean when there's a real change
//   and settles straight to "Done" otherwise; stop()/cancelImmediate() reset all of it.
//   `onAir` is never lit — refinement is `.processing`/`.done`, never capture.

@testable import Speak
import SpeakCore
import XCTest

@MainActor
final class OverlayControllerFeltSpeedTests: XCTestCase {

    private var controller: OverlayController!

    override func setUp() async throws {
        try await super.setUp()
        controller = OverlayController()
    }

    override func tearDown() async throws {
        controller = nil
        try await super.tearDown()
    }

    // MARK: - Settling (transition to .processing)

    /// transition(to: .processing) preserves the raw transcript into `settlingText` and
    /// marks it provisional — the user sees their words during cleanup, not a blank spinner.
    func testTransition_toProcessing_preservesRawTranscriptAsSettling() {
        controller.overlayModel.overlayState = .listening
        controller.overlayModel.partialText = "um I wanted to ask about the build"

        controller.transition(to: .processing)

        XCTAssertEqual(
            controller.overlayModel.settlingText, "um I wanted to ask about the build",
            "transition(to: .processing) must preserve the accumulated partialText into settlingText."
        )
        XCTAssertTrue(
            controller.overlayModel.isSettling,
            "transition(to: .processing) must mark the settling state as provisional."
        )
        XCTAssertFalse(
            controller.overlayModel.isDiffTransforming,
            "transition(to: .processing) must reset the diff-transformation flag."
        )
        XCTAssertNil(
            controller.overlayModel.revealedText,
            "transition(to: .processing) must clear any prior revealed text."
        )
    }

    /// transition(to: .processing) must NOT wipe the raw transcript (the felt-speed defect
    /// this slice fixes — the previous behavior cleared partialText to a blank spinner).
    func testTransition_toProcessing_doesNotWipePartialText() {
        controller.overlayModel.overlayState = .listening
        controller.overlayModel.partialText = "keep my words visible"

        controller.transition(to: .processing)

        XCTAssertEqual(
            controller.overlayModel.partialText, "keep my words visible",
            "transition(to: .processing) must keep partialText intact for the settling state."
        )
    }

    // MARK: - Transformation (showTransformation)

    /// showTransformation with a real cleaned diff animates raw→clean: isDiffTransforming=true,
    /// revealedText=cleaned, isSettling cleared, state→.done. `onAir` is never lit.
    func testShowTransformation_withRealChange_animatesDiff() {
        controller.overlayModel.overlayState = .processing
        controller.overlayModel.settlingText = "um I wanted to ask"
        controller.overlayModel.isSettling = true

        controller.showTransformation(cleaned: "I wanted to ask", raw: "um I wanted to ask")

        XCTAssertTrue(
            controller.overlayModel.isDiffTransforming,
            "A real raw→clean change must set isDiffTransforming so the view renders the diff."
        )
        XCTAssertEqual(
            controller.overlayModel.revealedText, "I wanted to ask",
            "revealedText must hold the cleaned result for the diff view."
        )
        XCTAssertEqual(
            controller.overlayModel.settlingText, "um I wanted to ask",
            "settlingText (diff raw) must survive showTransformation so PolishedDiffContent can seed the strikethrough."
        )
        XCTAssertFalse(
            controller.overlayModel.isSettling,
            "Reveal must end the settling/provisional state."
        )
        XCTAssertEqual(
            controller.overlayModel.overlayState, .done,
            "showTransformation must settle the overlay to .done."
        )
    }

    /// showTransformation with cleanup off / failed / identical (cleaned nil or == raw)
    /// must NOT animate a no-op diff — it settles straight to "Done".
    func testShowTransformation_noRealChange_settlesDirectlyToDone() {
        controller.overlayModel.overlayState = .processing
        controller.overlayModel.settlingText = "same words"
        controller.overlayModel.isSettling = true

        // Case 1: cleanup off → cleaned == nil.
        controller.showTransformation(cleaned: nil, raw: "same words")
        XCTAssertFalse(
            controller.overlayModel.isDiffTransforming,
            "No cleaned text must not animate a diff."
        )
        XCTAssertNil(
            controller.overlayModel.revealedText,
            "No cleaned text must leave revealedText nil."
        )
        XCTAssertEqual(
            controller.overlayModel.overlayState, .done,
            "No cleaned text must still settle to .done."
        )

        // Case 2: cleanup returned text identical to raw — no diff worth animating.
        controller.transition(to: .processing)
        controller.overlayModel.isSettling = true
        controller.overlayModel.settlingText = "same words"
        controller.showTransformation(cleaned: "same words", raw: "same words")
        XCTAssertFalse(
            controller.overlayModel.isDiffTransforming,
            "Cleaned identical to raw must not animate a no-op diff."
        )
        XCTAssertEqual(
            controller.overlayModel.revealedText, "same words",
            "Identical clean text still reveals for the 'Done' surface."
        )
    }

    /// showTransformation with an empty raw (non-standard caller) must fall back to the
    /// settling text preserved at the processing transition.
    func testShowTransformation_emptyRaw_usesSettlingText() {
        controller.overlayModel.overlayState = .processing
        controller.overlayModel.settlingText = "preserved raw"
        controller.overlayModel.isSettling = true

        controller.showTransformation(cleaned: "preserved raw cleaned", raw: "")

        XCTAssertTrue(
            controller.overlayModel.isDiffTransforming,
            "Empty raw must fall back to settlingText and still animate a real diff."
        )
        XCTAssertEqual(
            controller.overlayModel.revealedText, "preserved raw cleaned"
        )
    }

    // MARK: - Reset (stop / cancelImmediate)

    /// stop() must reset all felt-speed state so the next dictation starts clean.
    func testStop_resetsFeltSpeedState() {
        controller.overlayModel.overlayState = .done
        controller.overlayModel.settlingText = "stale"
        controller.overlayModel.isSettling = true
        controller.overlayModel.isDiffTransforming = true
        controller.overlayModel.revealedText = "stale cleaned"

        controller.stop()

        XCTAssertEqual(controller.overlayModel.settlingText, "")
        XCTAssertFalse(controller.overlayModel.isSettling)
        XCTAssertFalse(controller.overlayModel.isDiffTransforming)
        XCTAssertNil(controller.overlayModel.revealedText)
        XCTAssertEqual(controller.overlayModel.overlayState, .listening)
    }

    /// cancelImmediate() must reset felt-speed state identically to stop().
    func testCancelImmediate_resetsFeltSpeedState() {
        controller.overlayModel.overlayState = .done
        controller.overlayModel.settlingText = "stale"
        controller.overlayModel.isSettling = true
        controller.overlayModel.isDiffTransforming = true
        controller.overlayModel.revealedText = "stale cleaned"

        controller.cancelImmediate()

        XCTAssertEqual(controller.overlayModel.settlingText, "")
        XCTAssertFalse(controller.overlayModel.isSettling)
        XCTAssertFalse(controller.overlayModel.isDiffTransforming)
        XCTAssertNil(controller.overlayModel.revealedText)
        XCTAssertEqual(controller.overlayModel.overlayState, .listening)
    }

    // MARK: - 3-line FIFO window

    /// Short speech stays fully visible in the window.
    func testIngestWindow_short_staysVisible() {
        controller.ingestWindowPartial("hello world")
        XCTAssertEqual(controller.overlayModel.windowText, "hello world")
    }

    /// Over-budget cumulative snapshots keep only the newest window; oldest leaves.
    func testIngestWindow_overflow_keepsNewestOnly() {
        let first = "First sentence here. "
        let full = first + String(repeating: "word ", count: 40)
        controller.ingestWindowPartial(first)
        controller.ingestWindowPartial(full)

        XCTAssertFalse(
            controller.overlayModel.windowText.hasPrefix("First sentence"),
            "Oldest text must leave the 3-line window (FIFO)."
        )
        XCTAssertTrue(
            controller.overlayModel.windowText.contains("word"),
            "Newest speech must remain in the window."
        )
        let budget = OverlayTextFlow().maxWindowChars
        XCTAssertLessThanOrEqual(
            controller.overlayModel.windowText.count, budget,
            "Window must stay within the 3-line char budget."
        )
        // Full transcript is still held for settling/paste via partialText path;
        // window is only the visible FIFO slice.
        XCTAssertEqual(
            controller.overlayModel.textFlow.flowedText + controller.overlayModel.windowText,
            full
        )
    }
}
