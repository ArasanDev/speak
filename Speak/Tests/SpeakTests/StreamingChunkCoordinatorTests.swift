// SpeakTests/StreamingChunkCoordinatorTests.swift
//
// Unit tests for `StreamingChunkCoordinator`:
// Verifies live progressive chunk cleanup, concurrent background tasks,
// trailing text handling, stitching, and reset semantics.

@testable import SpeakCore
import XCTest

private final class MockChunkCleaner: LLMCleaning, @unchecked Sendable {
    let id = "mock-chunk-cleaner"
    var isAvailable: Bool = true
    var cleanedResults: [String: String] = [:]
    var callCount = 0

    func clean(_ text: String, mode: CleanupMode) async throws -> String {
        callCount += 1
        return cleanedResults[text] ?? (text + " [cleaned]")
    }
}

final class StreamingChunkCoordinatorTests: XCTestCase {

    func testIngestAndFinalizeStitching() async {
        let mock = MockChunkCleaner()
        mock.cleanedResults["hello world"] = "Hello world."
        mock.cleanedResults["how are you"] = "How are you?"

        let coordinator = StreamingChunkCoordinator(cleaner: mock, mode: .punctuation)

        await coordinator.ingestChunk("hello world")
        await coordinator.ingestChunk("how are you")

        let count = await coordinator.chunkCount
        XCTAssertEqual(count, 2)

        let result = await coordinator.finalizeAndStitch()
        XCTAssertEqual(result, "Hello world. How are you?")
    }

    func testFinalizeWithTrailingRawText() async {
        let mock = MockChunkCleaner()
        mock.cleanedResults["first sentence"] = "First sentence."
        mock.cleanedResults["trailing segment"] = "Trailing segment."

        let coordinator = StreamingChunkCoordinator(cleaner: mock, mode: .punctuation)

        await coordinator.ingestChunk("first sentence")
        let result = await coordinator.finalizeAndStitch(trailingRawText: "trailing segment")

        XCTAssertEqual(result, "First sentence. Trailing segment.")
    }

    func testResetClearsChunks() async {
        let mock = MockChunkCleaner()
        let coordinator = StreamingChunkCoordinator(cleaner: mock, mode: .punctuation)

        await coordinator.ingestChunk("chunk one")
        await coordinator.ingestChunk("chunk two")

        var count = await coordinator.chunkCount
        XCTAssertEqual(count, 2)

        await coordinator.reset()

        count = await coordinator.chunkCount
        XCTAssertEqual(count, 0)
    }

    func testHierarchicalMacroConsolidationPass() async {
        let mock = MockChunkCleaner()
        mock.cleanedResults["we will do option one"] = "We will do option one."
        mock.cleanedResults["actually not option two do option one and three immediately"] =
            "Actually not option two do option one and three immediately."
        mock.cleanedResults["We will do option one. Actually not option two do option one and three immediately."] =
            "Implement option 1 and option 3 immediately."

        let coordinator = StreamingChunkCoordinator(cleaner: mock, mode: .styled(.code, .medium))

        await coordinator.ingestChunk("we will do option one")
        await coordinator.ingestChunk("actually not option two do option one and three immediately")

        let result = await coordinator.finalizeAndStitch()
        XCTAssertEqual(result, "Implement option 1 and option 3 immediately.")
    }
}
