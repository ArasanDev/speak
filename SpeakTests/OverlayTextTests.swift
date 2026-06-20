// SpeakTests/OverlayTextTests.swift
//
// Unit tests for `OverlayTextAccumulator` — the pure, headlessly-testable slice
// of the P4 partial-transcript overlay. All tests are synchronous and deterministic;
// no AppKit, no SwiftUI, no NSPanel, no async machinery.
//
// Coverage:
//   1. Initial state is empty.
//   2. Non-empty chunk updates displayText.
//   3. Empty chunk does NOT blank the display (newest-non-empty rule).
//   4. Sequence of empty then non-empty updates correctly.
//   5. Sequence of non-empty then empty retains the last non-empty value.
//   6. reset() clears displayText.
//   7. reset() after a sequence of chunks clears displayText.
//   8. Multiple non-empty chunks: latest wins.
//   9. Return value of next(_:) matches displayText after each call.

import XCTest
@testable import SpeakCore

final class OverlayTextTests: XCTestCase {

    // Helper: make a chunk with the given text and isFinal=false (isFinal is
    // irrelevant to the accumulator, but we test with both to confirm it's ignored).
    private func chunk(_ text: String, isFinal: Bool = false) -> TranscriptChunk {
        TranscriptChunk(text: text, isFinal: isFinal, timestamp: Date())
    }

    // MARK: - 1. Initial state

    func testInitialStateIsEmpty() {
        let acc = OverlayTextAccumulator()
        XCTAssertEqual(acc.displayText, "")
    }

    // MARK: - 2. Non-empty chunk updates displayText

    func testNonEmptyChunkUpdatesDisplayText() {
        var acc = OverlayTextAccumulator()
        acc.next(chunk("Hello"))
        XCTAssertEqual(acc.displayText, "Hello")
    }

    // MARK: - 3. Empty chunk does NOT blank the display (newest-non-empty rule)

    func testEmptyChunkDoesNotBlankDisplay() {
        var acc = OverlayTextAccumulator()
        acc.next(chunk("Hello"))
        acc.next(chunk(""))         // empty chunk — must not blank "Hello"
        XCTAssertEqual(acc.displayText, "Hello")
    }

    // MARK: - 4. Empty chunk before any non-empty chunk → display stays empty

    func testEmptyChunkBeforeAnyNonEmptyKeepsEmpty() {
        var acc = OverlayTextAccumulator()
        acc.next(chunk(""))
        XCTAssertEqual(acc.displayText, "")
    }

    // MARK: - 5. Non-empty then empty retains last non-empty

    func testNonEmptyThenEmptyRetainsLast() {
        var acc = OverlayTextAccumulator()
        acc.next(chunk("Hello world"))
        acc.next(chunk(""))
        acc.next(chunk(""))
        XCTAssertEqual(acc.displayText, "Hello world")
    }

    // MARK: - 6. reset() clears displayText

    func testResetClearsDisplayText() {
        var acc = OverlayTextAccumulator()
        acc.next(chunk("Hello"))
        acc.reset()
        XCTAssertEqual(acc.displayText, "")
    }

    // MARK: - 7. reset() after a sequence works correctly

    func testResetAfterSequenceClearsDisplay() {
        var acc = OverlayTextAccumulator()
        acc.next(chunk("first"))
        acc.next(chunk(""))
        acc.next(chunk("second"))
        acc.reset()
        XCTAssertEqual(acc.displayText, "")
    }

    // MARK: - 8. Multiple non-empty chunks: latest wins

    func testLatestNonEmptyChunkWins() {
        var acc = OverlayTextAccumulator()
        acc.next(chunk("one"))
        acc.next(chunk("one two"))
        acc.next(chunk("one two three"))
        XCTAssertEqual(acc.displayText, "one two three")
    }

    // MARK: - 9. Return value of next(_:) matches displayText

    func testNextReturnValueMatchesDisplayText() {
        var acc = OverlayTextAccumulator()
        let returned = acc.next(chunk("speak"))
        XCTAssertEqual(returned, acc.displayText)
    }

    // MARK: - 10. isFinal flag is ignored (accumulator cares only about text)

    func testFinalChunkBehavesIdenticallyToPartialChunk() {
        var acc1 = OverlayTextAccumulator()
        var acc2 = OverlayTextAccumulator()
        acc1.next(chunk("test", isFinal: false))
        acc2.next(chunk("test", isFinal: true))
        XCTAssertEqual(acc1.displayText, acc2.displayText)
    }

    // MARK: - 11. Accumulator is a value type — copies are independent

    func testAccumulatorValueSemantics() {
        var original = OverlayTextAccumulator()
        original.next(chunk("hello"))
        var copy = original
        copy.next(chunk("world"))
        // The copy advanced; the original must be unchanged.
        XCTAssertEqual(original.displayText, "hello")
        XCTAssertEqual(copy.displayText, "world")
    }
}
