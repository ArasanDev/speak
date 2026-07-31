// SpeakTests/ScriptedTranscriberTests.swift
//
// Coverage for the DEBUG-only ScriptedTranscriber that backs
// `--debug-open simulate-dictation-scripted:<text>` — verifies the
// progressive-reveal chunk sequence and the failure path conform to the
// `Transcribing` contract real callers (CaptureSession) depend on.

@testable import SpeakCore
import XCTest

final class ScriptedTranscriberTests: XCTestCase {

    func testProgressiveRevealYieldsGrowingPartialsThenOneFinal() async throws {
        let transcriber = ScriptedTranscriber(
            revealingWordsIn: "hello there friend",
            wordDelayNanoseconds: 1_000_000 // 1ms — keep the test fast
        )

        var chunks: [TranscriptChunk] = []
        for try await chunk in transcriber.startStream(locale: Locale(identifier: "en-US")) {
            chunks.append(chunk)
        }

        XCTAssertEqual(chunks.map(\.text), ["hello", "hello there", "hello there friend"])
        XCTAssertEqual(chunks.map(\.isFinal), [false, false, true],
            "Only the last chunk (full text) should be marked final.")
    }

    func testSingleWordScriptYieldsOneFinalChunk() async throws {
        let transcriber = ScriptedTranscriber(revealingWordsIn: "hello", wordDelayNanoseconds: 1_000_000)

        var chunks: [TranscriptChunk] = []
        for try await chunk in transcriber.startStream(locale: Locale(identifier: "en-US")) {
            chunks.append(chunk)
        }

        XCTAssertEqual(chunks.count, 1)
        XCTAssertEqual(chunks.first?.text, "hello")
        XCTAssertEqual(chunks.first?.isFinal, true)
    }

    func testFailureScriptThrowsAndYieldsNoChunks() async throws {
        let transcriber = ScriptedTranscriber(script: .failure(ScriptedTranscriberError(reason: "forced test failure")))

        var chunks: [TranscriptChunk] = []
        var thrown: Error?
        do {
            for try await chunk in transcriber.startStream(locale: Locale(identifier: "en-US")) {
                chunks.append(chunk)
            }
        } catch {
            thrown = error
        }

        XCTAssertTrue(chunks.isEmpty, "A failure script must yield zero chunks before throwing.")
        XCTAssertNotNil(thrown, "A failure script must propagate its error through the stream.")
    }

    func testStopCancelsInFlightStream() async throws {
        let transcriber = ScriptedTranscriber(
            revealingWordsIn: "one two three four five six seven eight nine ten",
            wordDelayNanoseconds: 50_000_000 // 50ms/word — long enough to interrupt mid-stream
        )

        let stream = transcriber.startStream(locale: Locale(identifier: "en-US"))
        let counter = ChunkCounter()

        // Consume in a detached task so `stop()` below is a genuine external
        // interruption, not a self-inflicted `break` — the previous version of
        // this test broke out of the loop itself, which finishes the stream via
        // `onTermination` before `stop()` is ever invoked, so it exercised
        // nothing about `stop()`'s behavior. This version lets the loop run
        // freely and calls `stop()` from outside after ~2 words have arrived.
        let consumer = Task {
            for try await chunk in stream {
                await counter.record(chunk)
            }
        }

        // Wait for a couple of chunks to land, then interrupt from outside.
        while await counter.count < 2 {
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        await transcriber.stop()
        _ = try? await consumer.value

        let finalCount = await counter.count
        XCTAssertGreaterThanOrEqual(finalCount, 1, "Should have received at least one partial before stopping.")
        XCTAssertLessThan(finalCount, 10, "stop() should cut the stream short of the full 10-word script.")
    }

    /// Actor-isolated accumulator so the consumer task and the polling loop
    /// above can share state without a data race.
    private actor ChunkCounter {
        private(set) var count = 0
        func record(_ chunk: TranscriptChunk) { count += 1 }
    }

    func testIdIsStableAndDescriptive() {
        let transcriber = ScriptedTranscriber(revealingWordsIn: "test")
        XCTAssertEqual(transcriber.id, "scripted-fixture")
    }
}
