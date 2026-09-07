// SpeakTests/OverlayTextFlowTests.swift
//
// FIFO-out text flow — pure state machine (`OverlayTextFlow`).
//
// Feed contract: `ingest` takes a FULL transcript snapshot (matching
// `OverlayTextAccumulator`), not a delta. Already-flowed text is the committed
// prefix; only the uncaptured suffix is the active window.

@testable import Speak
import SpeakCore
import XCTest

final class OverlayTextFlowTests: XCTestCase {

    private var flow: OverlayTextFlow!

    override func setUp() {
        super.setUp()
        flow = OverlayTextFlow(maxWindowChars: 40)
    }

    // MARK: - Window budget

    func testShortPartial_staysInWindow() {
        flow.ingest("hello world")
        XCTAssertEqual(flow.windowText, "hello world")
        XCTAssertTrue(flow.flowedChunks.isEmpty, "Text under the budget must stay in the window.")
    }

    func testTextAtBudget_staysInWindow() {
        let text = String(repeating: "a", count: 40)
        flow.ingest(text)
        XCTAssertEqual(flow.windowText, text)
        XCTAssertTrue(flow.flowedChunks.isEmpty)
    }

    // MARK: - FIFO-out from cumulative snapshots

    func testOverBudget_flushesOldestFirst() {
        let first = "First sentence here. "
        flow.ingest(first)
        XCTAssertTrue(flow.flowedChunks.isEmpty)

        // Full snapshot (accumulator shape), not a delta append.
        let full = first + "Second sentence that pushes past the budget now."
        let flushed = flow.ingest(full)
        XCTAssertFalse(flushed.isEmpty, "Overflow must produce a flush.")
        XCTAssertEqual(flushed.first?.text, "First sentence here. ", "Oldest text leaves first (FIFO).")
        XCTAssertFalse(
            flow.windowText.hasPrefix("First"),
            "Oldest prefix must no longer sit in the window."
        )
        XCTAssertLessThanOrEqual(flow.windowText.count, 40)
        XCTAssertEqual(flow.flowedText + flow.windowText, full)
    }

    func testCumulativeSnapshots_doNotDuplicate() {
        let growing = [
            "Hello ",
            "Hello world. ",
            "Hello world. More text that will eventually overflow the forty char budget here."
        ]
        for snap in growing {
            flow.ingest(snap)
        }
        let joined = flow.flowedText + flow.windowText
        XCTAssertEqual(joined, growing.last, "Flowed + window must reconstruct the latest snapshot once.")
        let helloCount = joined.components(separatedBy: "Hello").count - 1
        XCTAssertEqual(helloCount, 1, "Must not duplicate earlier snapshot prefixes.")
    }

    func testFlushedChunks_reconstructOriginalInOrder() {
        let full = "Alpha beta gamma. Delta epsilon zeta. Eta theta iota. "
        flow.ingest(full)
        XCTAssertTrue(flow.flowedChunks.first?.text.contains("Alpha") == true,
                      "Alpha (oldest) must have flowed out first.")
        XCTAssertEqual(flow.flowedText + flow.windowText, full)
    }

    // MARK: - Chunk boundaries

    func testFlush_cutsAtSentenceBoundary() {
        let text = "This is the first sentence. And then a much longer tail that overflows."
        flow.ingest(text)
        let first = flow.flowedChunks.first
        XCTAssertEqual(first?.text, "This is the first sentence. ", "Must cut at the first sentence boundary.")
    }

    func testFlush_hardCutWhenNoBoundary() {
        flow.ingest(String(repeating: "a", count: 60))
        let first = flow.flowedChunks.first
        XCTAssertEqual(first?.text, String(repeating: "a", count: 40), "No boundary → hard cut at the budget.")
    }

    // MARK: - Reset

    func testReset_clearsWindowAndFlowed() {
        flow.ingest(String(repeating: "word ", count: 15))
        XCTAssertFalse(flow.flowedChunks.isEmpty)

        flow.reset()

        XCTAssertEqual(flow.windowText, "")
        XCTAssertTrue(flow.flowedChunks.isEmpty)
    }
}
