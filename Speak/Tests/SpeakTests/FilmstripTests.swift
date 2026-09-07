// SpeakTests/FilmstripTests.swift
//
// Felt-speed (input-felt-speed.md §3.3) — horizontal filmstrip transcript.
//
// Tests the PURE block-cut logic (`FilmstripCutter`) and the filmstrip choreography
// (`OverlayController.ingestFilmstripPartial`): when streaming text exceeds the block
// budget it is captured as a miniaturized block, the active area resets to the
// remainder, and each block is sent to the live per-block AI cleaner.
//
// HONESTY BOUNDARY: the SwiftUI rendering (slide-left animation, miniaturization scale)
// is a live-visual surface, not unit-tested here. The cut/remainder/polish state
// machine IS tested — it's pure and deterministic.

@testable import Speak
import SpeakCore
import XCTest

// MARK: - FilmstripCutter (pure)

final class FilmstripCutterTests: XCTestCase {

    private var cutter: FilmstripCutter!

    override func setUp() {
        super.setUp()
        cutter = FilmstripCutter(maxActiveChars: 40)
    }

    func testShortText_noCut() {
        XCTAssertNil(cutter.blockCut(for: "hello world"), "Short text under the budget must not cut.")
    }

    func testTextAtBudget_noCut() {
        // Exactly 40 chars — still fits, no cut.
        let text = String(repeating: "a", count: 40)
        XCTAssertNil(cutter.blockCut(for: text), "Text exactly at the budget must not cut.")
    }

    func testTextOverBudget_cutsAtSentenceBoundary() {
        // Over budget, with a sentence boundary inside the prefix → cut at the boundary.
        let text = "This is the first sentence. And then a much longer tail that overflows."
        let cut = cutter.blockCut(for: text)
        XCTAssertEqual(cut, "This is the first sentence. ", "Must cut at the last sentence boundary within budget.")
    }

    func testTextOverBudget_cutsAtWhitespaceWhenNoSentenceBoundary() {
        // Over budget, no sentence boundary → cut at last whitespace.
        let text = String(repeating: "word ", count: 15)  // 75 chars, spaces at every 5
        let cut = cutter.blockCut(for: text)
        guard let cut else {
            XCTFail("Over-budget text must produce a cut.")
            return
        }
        XCTAssertFalse(cut.hasSuffix(" "), "Cut at whitespace excludes the trailing space.")
        XCTAssertTrue(cut.count <= 40, "Cut must be within the budget.")
    }

    func testTextOverBudget_hardCutWhenNoWhitespace() {
        // Over budget, no whitespace at all → hard character cut.
        let text = String(repeating: "a", count: 60)
        let cut = cutter.blockCut(for: text)
        XCTAssertEqual(cut, String(repeating: "a", count: 40), "No whitespace → hard cut at the budget.")
    }

    func testBlockCut_remainderKeepsStreaming() {
        // Verify the cutter's contract: block + remainder reconstruct the input.
        let text = "First block sentence. Second block still streaming."
        guard let cut = cutter.blockCut(for: text) else {
            XCTFail("Over-budget text must produce a cut.")
            return
        }
        let remainder = String(text.dropFirst(cut.count))
        XCTAssertEqual(cut + remainder, text, "Block + remainder must reconstruct the original text.")
    }
}

// MARK: - OverlayController filmstrip choreography

@MainActor
final class OverlayControllerFilmstripTests: XCTestCase {

    private var controller: OverlayController!

    override func setUp() async throws {
        try await super.setUp()
        controller = OverlayController()
        controller.overlayModel.isFilmstripEnabled = true
    }

    override func tearDown() async throws {
        controller = nil
        try await super.tearDown()
    }

    /// A long partial that exceeds the block budget must produce a block and reset the
    /// active streaming area to the remainder.
    func testIngest_longPartial_producesBlockAndResetsActive() {
        let long = String(repeating: "word ", count: 60)  // 300 chars, well over the default budget

        controller.ingestFilmstripPartial(long)

        XCTAssertFalse(controller.overlayModel.filmstripBlocks.isEmpty, "Over-budget text must produce a block.")
        let blockText = controller.overlayModel.filmstripBlocks.map(\.rawText).joined(separator: " ")
        XCTAssertFalse(blockText.isEmpty)
        // The active stream holds only the remainder (shorter than the block).
        XCTAssertLessThan(
            controller.overlayModel.activeStreamText.count, long.count,
            "Active stream must hold the remainder, not the whole input."
        )
    }

    /// A short partial must NOT produce a block — the active area just streams.
    func testIngest_shortPartial_noBlock() {
        controller.ingestFilmstripPartial("just a short line")

        XCTAssertTrue(controller.overlayModel.filmstripBlocks.isEmpty, "Short text must not cut a block.")
        XCTAssertEqual(controller.overlayModel.activeStreamText, "just a short line")
    }

    /// With the filmstrip disabled, ingestion must be a no-op (no blocks, no active reset).
    func testIngest_disabled_isNoOp() {
        controller.overlayModel.isFilmstripEnabled = false
        let long = String(repeating: "word ", count: 60)

        controller.ingestFilmstripPartial(long)

        XCTAssertTrue(controller.overlayModel.filmstripBlocks.isEmpty, "Disabled filmstrip must not cut blocks.")
        XCTAssertEqual(controller.overlayModel.activeStreamText, "", "Disabled filmstrip must not set active text.")
    }

    /// When cleanup is off (no cleaner), a captured block is marked polished immediately
    /// with raw text as the display — no hang, no ghost "Polishing…" state.
    func testPolish_noCleaner_marksPolishedImmediately() {
        controller.filmstripCleaner = nil
        let long = String(repeating: "word ", count: 60)

        controller.ingestFilmstripPartial(long)

        let blocks = controller.overlayModel.filmstripBlocks
        XCTAssertFalse(blocks.isEmpty)
        XCTAssertTrue(blocks.allSatisfy { $0.isPolished }, "No cleaner → every block is immediately polished.")
        XCTAssertTrue(blocks.allSatisfy { !$0.isPolishing }, "No cleaner → no block stays polishing.")
        XCTAssertTrue(blocks.allSatisfy { $0.cleanedText == nil }, "No cleaner → blocks stay raw.")
    }

    /// Cumulative full-snapshot ingests (real STT shape) must not duplicate blocks.
    func testIngest_cumulativeSnapshots_noDuplicateBlocks() {
        let first = String(repeating: "word ", count: 60)
        controller.ingestFilmstripPartial(first)
        let blockCountAfterFirst = controller.overlayModel.filmstripBlocks.count
        XCTAssertGreaterThan(blockCountAfterFirst, 0)

        // Same growing transcript again (accumulator snapshot), then a longer one.
        controller.ingestFilmstripPartial(first)
        XCTAssertEqual(
            controller.overlayModel.filmstripBlocks.count, blockCountAfterFirst,
            "Re-feeding the same snapshot must not append duplicate blocks."
        )

        let longer = first + "and then more words that continue the stream past another cut. "
        controller.ingestFilmstripPartial(longer)
        let joined = controller.overlayModel.filmstripBlocks.map(\.rawText).joined()
            + controller.overlayModel.activeStreamText
        XCTAssertEqual(joined, longer, "Blocks + active must reconstruct the latest snapshot once.")
    }

    /// stop() must reset the filmstrip state so the next dictation starts clean.
    func testStop_resetsFilmstrip() {
        controller.ingestFilmstripPartial(String(repeating: "word ", count: 60))
        XCTAssertFalse(controller.overlayModel.filmstripBlocks.isEmpty)

        controller.stop()

        XCTAssertTrue(controller.overlayModel.filmstripBlocks.isEmpty)
        XCTAssertEqual(controller.overlayModel.activeStreamText, "")
    }

    /// cancelImmediate() must reset the filmstrip identically to stop().
    func testCancelImmediate_resetsFilmstrip() {
        controller.ingestFilmstripPartial(String(repeating: "word ", count: 60))
        XCTAssertFalse(controller.overlayModel.filmstripBlocks.isEmpty)

        controller.cancelImmediate()

        XCTAssertTrue(controller.overlayModel.filmstripBlocks.isEmpty)
        XCTAssertEqual(controller.overlayModel.activeStreamText, "")
    }
}
