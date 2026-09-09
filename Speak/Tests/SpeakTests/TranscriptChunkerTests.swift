// SpeakTests/TranscriptChunkerTests.swift
//
// Unit tests for `TranscriptChunker`: sentence segmentation, word threshold fast path,
// clause boundary fallback, and chunk stitching.

@testable import SpeakCore
import XCTest

final class TranscriptChunkerTests: XCTestCase {

    func testShortUtteranceReturnsSingleChunk() {
        let text = "Can you check the server logs?"
        let chunks = TranscriptChunker.chunk(text, wordThreshold: 25)
        XCTAssertEqual(chunks.count, 1)
        XCTAssertEqual(chunks.first, text)
    }

    func testMultiSentenceStreamSegmentsAtSentenceBoundaries() {
        let text = "Do you have any other ideas? Can you study the competitors? Now you understand what the prompting style is."
        let chunks = TranscriptChunker.chunk(text, wordThreshold: 10)
        XCTAssertEqual(chunks.count, 3)
        XCTAssertEqual(chunks[0], "Do you have any other ideas?")
        XCTAssertEqual(chunks[1], "Can you study the competitors?")
        XCTAssertEqual(chunks[2], "Now you understand what the prompting style is.")
    }

    func testFallbackChunkingSplitsOnClauseConnectorsWhenNoPunctuation() {
        let text = "we should not do the bulk things all the things bulk at a time and we have to stream when the inputs start coming in so we have to do proper engineering"
        let chunks = TranscriptChunker.chunk(text, wordThreshold: 10)
        XCTAssertGreaterThan(chunks.count, 1, "Unpunctuated long text must split into chunks")
    }

    func testStitchReassemblesChunksWithProperSpacing() {
        let chunks = [
            "Do you have any other ideas?",
            "Can you study the competitors?",
            "Now you understand what the prompting style is."
        ]
        let stitched = TranscriptChunker.stitch(chunks)
        XCTAssertEqual(
            stitched,
            "Do you have any other ideas? Can you study the competitors? Now you understand what the prompting style is."
        )
    }

    func testEmptyOrWhitespaceTextProducesEmptyChunks() {
        XCTAssertEqual(TranscriptChunker.chunk(""), [])
        XCTAssertEqual(TranscriptChunker.chunk("   \n\t  "), [])
        XCTAssertEqual(TranscriptChunker.stitch([]), "")
    }
}
