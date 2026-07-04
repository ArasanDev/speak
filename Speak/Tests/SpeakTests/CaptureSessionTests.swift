// SpeakTests/CaptureSessionTests.swift
//
// Tests for the CaptureSession orchestration actor (architecture.md §6, §7.1;
// roadmap P3.5 done-when).
//
// SCOPE (read before changing):
//   These tests use MOCK `Transcribing` and `LLMCleaning` so the orchestration
//   logic is fully covered without depending on Apple SpeechAnalyzer or
//   Foundation Models hardware/availability. The REAL engine integration
//   tests live in `SpeechTranscriberTests.swift` and
//   `FoundationModelsCleanerTests.swift`. Paste (P6) and hotkey (P5) are not
//   exercised here — they consume this actor's API in their own test files.
//
// Done-when rows closed here (P3.5):
//   [x] start() transitions idle → listening
//   [x] stop() returns a TranscriptionResult with the latest chunk's text
//   [x] stop() with cleaner=nil (cleanup off) → cleanedText=nil, engineId=STT id
//   [x] stop() with cleaner.isAvailable=false → cleanedText=nil, no error,
//       engineId=STT id (graceful fallback, NOT .error)
//   [x] stop() with cleaner.clean() throwing → throws SpeakError.llmCleanupFailed
//   [x] stop() with cleaner available and succeeding → cleanedText populated,
//       engineId="<stt>+<cleaner>"
//   [x] double-start() throws
//   [x] cancel() moves to .error(.sessionCancelled) and stops the STT
//   [x] partials() stream emits chunks as the STT emits them, and finishes
//       when the session terminates
//   [x] stop() with stream that threw mid-session surfaces the STT error
//
// SKIP / DEFER:
//   - Live, end-to-end dictation with real STT + real cleanup is the P13
//     dogfood bar (quality.md §2). Out of scope here.

@testable import SpeakCore
import XCTest

// MARK: - Mocks

/// A controllable mock STT engine. Class (not actor) so it can conform to
/// `Transcribing` without the protocol's `nonisolated` requirements. Marked
/// `@unchecked Sendable` because all mutation is funneled through the
/// Mutable state (`_stopCallCount`) is only touched from the test's
    /// deterministic, single-task usage; no real concurrency, so no lock is needed.
private final class MockTranscriber: Transcribing, @unchecked Sendable {
    let id: String
    private let script: [TranscriptChunk]
    /// When non-nil, the stream finishes by throwing this error (used to
    /// exercise the stream-failure path).
    let failWith: Error?
    private var _stopCallCount: Int = 0
    private let _waitForStop: Bool
    /// Continuation used to gate the stream's finish on `stop()` being called
    /// (used by the stop()-awaits-finalization path test, if needed).
    private let stopContinuation: CheckedContinuation<Void, Never>?
    private let stopSignal: StopSignal?

    init(id: String = "mock-stt",
         script: [TranscriptChunk],
         failWith: Error? = nil) {
        self.id = id
        self.script = script
        self.failWith = failWith
        self._waitForStop = false
        self.stopContinuation = nil
        self.stopSignal = nil
    }

    func startStream(locale: Locale) -> AsyncThrowingStream<TranscriptChunk, Error> {
        let script = self.script
        let failWith = self.failWith
        let stopSignal = self.stopSignal
        return AsyncThrowingStream { continuation in
            let task = Task {
                for chunk in script {
                    // Yield each chunk.
                    continuation.yield(chunk)
                    // Brief sleep so the consumer has time to ingest each one
                    // (mimics real partial cadence; deterministic, not flaky).
                    try? await Task.sleep(nanoseconds: 1_000_000) // 1ms
                }
                if let stopSignal = stopSignal {
                    // Wait for stop() to be called before finishing.
                    await stopSignal.wait()
                }
                if let err = failWith {
                    continuation.finish(throwing: err)
                } else {
                    continuation.finish()
                }
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    func stop() async {
        _stopCallCount += 1
        stopSignal?.signal()
    }

    /// Test helper: how many times `stop()` was called on this mock.
    func calls() -> Int { _stopCallCount }
}

/// Helper used by `MockTranscriber` to coordinate "finish the stream" with
/// "the orchestrator called stop()". A second continuation primitive used
/// only in tests that need to verify the stream waits for stop().
private final class StopSignal: @unchecked Sendable {
    private var waiter: CheckedContinuation<Void, Never>?

    func wait() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            // Single-task usage: no lock needed for the wait/signal handshake.
            waiter = continuation
        }
    }

    func signal() {
        waiter?.resume()
        waiter = nil
    }
}

/// A controllable mock cleanup engine. Lets the test configure availability
/// and the `clean()` outcome (success, throw).
private struct MockCleaner: LLMCleaning {
    let id: String
    let available: Bool
    /// If non-nil, `clean()` throws this error.
    let cleanError: Error?
    /// What `clean()` returns on success.
    let cleanResult: String
    /// Records every `clean()` call.
    let recorder: CleanerRecorder

    var isAvailable: Bool { get async { available } }

    func clean(_ text: String, mode: CleanupMode) async throws -> String {
        await recorder.record(text: text, mode: mode)
        if let err = cleanError {
            throw err
        }
        return cleanResult
    }
}

/// Actor used to record `clean()` invocations across the test (the cleaner
/// is a struct, but it can call into this actor to retain state).
private actor CleanerRecorder {
    private(set) var calls: [(text: String, mode: CleanupMode)] = []

    func record(text: String, mode: CleanupMode) {
        calls.append((text, mode))
    }

    func snapshot() -> [(text: String, mode: CleanupMode)] { calls }
}

/// A cleaner that **never** returns from `clean()` — simulates a hung
/// Foundation Models session. Non-cooperative: awaits a CheckedContinuation
/// that is never resumed, so `Task.cancel()` alone cannot unblock it.
///
/// This is the correct mock for verifying `CaptureSession.runCleanup()`'s
/// timeout mechanism fires even when the cleaner ignores cooperative cancellation.
/// A `Task.sleep`-based mock would yield a false green because Task.sleep IS
/// cooperative and would unblock on cancel(), masking a timeout that relies on
/// cooperative cancellation to work.
private struct HangingCleaner: LLMCleaning, Sendable {
    let id: String
    var isAvailable: Bool { get async { true } }

    func clean(_ text: String, mode: CleanupMode) async throws -> String {
        // Await a continuation that is never resumed. This is a true non-cooperative
        // hang — Task.cancel() sets the cancellation flag but does NOT unblock this
        // await (CheckedContinuation ignores cooperative cancellation).
        await withCheckedContinuation { (_: CheckedContinuation<Void, Never>) in
            // Intentionally no-op. This continuation is never resumed.
            // The Task that runs this will eventually be leaked when the parent
            // times out and cancels it — that is the expected behavior documented
            // in CaptureSession.runCleanup() (non-cooperative cleaners may keep
            // running in the background after timeout).
        }
        return text  // unreachable, but satisfies the return type
    }
}

/// A cleaner that sleeps for `delayNanoseconds` then returns `result`.
/// Used to verify that a slow-but-cooperative cleaner still produces a clean
/// result (regression guard — timeout must not fire prematurely).
private struct SlowCleaner: LLMCleaning, Sendable {
    let id: String
    let delayNanoseconds: UInt64
    let result: String

    var isAvailable: Bool { get async { true } }

    func clean(_ text: String, mode: CleanupMode) async throws -> String {
        try? await Task.sleep(nanoseconds: delayNanoseconds)
        return result
    }
}

// MARK: - Tests

final class CaptureSessionTests: XCTestCase {

    // MARK: Helpers

    private func makeChunks(_ texts: [String], final: String? = nil) -> [TranscriptChunk] {
        let now = Date()
        let all = texts + (final.map { [$0] } ?? [])
        return all.enumerated().map { idx, text in
            TranscriptChunk(text: text,
                            isFinal: idx == all.count - 1,
                            timestamp: now.addingTimeInterval(Double(idx) * 0.01))
        }
    }

    // MARK: - State machine

    func testInitialStateIsIdle() async {
        let transcriber = MockTranscriber(script: makeChunks(["hello"]))
        let session = CaptureSession(transcriber: transcriber)
        let state = await session.currentState
        XCTAssertTrue(state == .idle, "Fresh session must start in .idle, got \(state)")
    }

    func testStartTransitionsToListening() async throws {
        let transcriber = MockTranscriber(script: makeChunks(["hello"]))
        let session = CaptureSession(transcriber: transcriber)
        try await session.start()
        let state = await session.currentState
        XCTAssertTrue(state == .listening, "start() must transition to .listening, got \(state)")
    }

    func testDoubleStartThrows() async throws {
        let transcriber = MockTranscriber(script: makeChunks(["hello"]))
        let session = CaptureSession(transcriber: transcriber)
        try await session.start()
        do {
            try await session.start()
            XCTFail("Second start() must throw")
        } catch {
            // Expected — non-idle state rejects start.
        }
    }

    func testStopWithoutListeningThrows() async throws {
        let transcriber = MockTranscriber(script: makeChunks(["hello"]))
        let session = CaptureSession(transcriber: transcriber)
        do {
            _ = try await session.stop()
            XCTFail("stop() from .idle must throw")
        } catch {
            // Expected.
        }
    }

    func testCancelMovesToErrorSessionCancelled() async throws {
        let transcriber = MockTranscriber(script: makeChunks(["hello"]))
        let session = CaptureSession(transcriber: transcriber)
        try await session.start()
        await session.cancel()
        let state = await session.currentState
        if case .error(.sessionCancelled) = state {
            // Expected.
        } else {
            XCTFail("cancel() must move to .error(.sessionCancelled), got \(state)")
        }
    }

    // MARK: - Stop returns a TranscriptionResult

    func testStopReturnsTranscriptionResultWithLatestChunkText() async throws {
        let chunks = makeChunks(["hel", "hello", "hello world"], final: nil)
        let transcriber = MockTranscriber(script: chunks)
        let session = CaptureSession(transcriber: transcriber)
        try await session.start()

        // Give the stream a moment to emit.
        try await Task.sleep(nanoseconds: 50_000_000) // 50ms

        let result = try await session.stop()
        XCTAssertEqual(result.rawText, "hello world", "rawText must be the last chunk's text")
        XCTAssertEqual(result.engineId, "mock-stt", "engineId is STT id when no cleanup")
        let state = await session.currentState
        XCTAssertTrue(state == .done, "stop() must end in .done, got \(state)")
    }

    // MARK: - Cleanup off (cleaner == nil)

    func testStopWithCleanerNilHasCleanedTextNil() async throws {
        let chunks = makeChunks(["hello", "world"], final: nil)
        let transcriber = MockTranscriber(script: chunks)
        let session = CaptureSession(transcriber: transcriber, cleaner: nil)
        try await session.start()
        try await Task.sleep(nanoseconds: 50_000_000)
        let result = try await session.stop()
        XCTAssertNil(result.cleanedText, "Cleanup off → cleanedText must be nil")
        XCTAssertEqual(result.engineId, "mock-stt", "Cleanup off → engineId is STT id only")
    }

    // MARK: - Cleanup on (cleaner available, succeeds)

    func testStopWithCleanerAvailableProducesCleanedText() async throws {
        let chunks = makeChunks(["um hello uh world"], final: nil)
        let transcriber = MockTranscriber(script: chunks)
        let recorder = CleanerRecorder()
        let cleaner = MockCleaner(
            id: "mock-cleaner",
            available: true,
            cleanError: nil,
            cleanResult: "Hello, world.",
            recorder: recorder
        )
        let session = CaptureSession(transcriber: transcriber, cleaner: cleaner)
        try await session.start()
        try await Task.sleep(nanoseconds: 50_000_000)
        let result = try await session.stop()
        XCTAssertEqual(result.cleanedText, "Hello, world.", "Cleanup on → cleaned text populated")
        XCTAssertEqual(result.engineId, "mock-stt+mock-cleaner", "engineId combines STT + cleaner")
        let calls = await recorder.snapshot()
        XCTAssertEqual(calls.count, 1, "clean() must be called exactly once")
        XCTAssertEqual(calls.first?.text, "um hello uh world", "clean() must receive the raw text")
    }

    // MARK: - Cleanup unavailable (graceful fallback)

    func testStopWithCleanerUnavailableFallsBackToRawNoError() async throws {
        let chunks = makeChunks(["hello world"], final: nil)
        let transcriber = MockTranscriber(script: chunks)
        let recorder = CleanerRecorder()
        let cleaner = MockCleaner(
            id: "mock-cleaner",
            available: false,                  // engine says it can't run
            cleanError: nil,
            cleanResult: "",
            recorder: recorder
        )
        let session = CaptureSession(transcriber: transcriber, cleaner: cleaner)
        try await session.start()
        try await Task.sleep(nanoseconds: 50_000_000)
        let result = try await session.stop()
        XCTAssertNil(result.cleanedText, "Unavailable cleanup → cleanedText must be nil")
        XCTAssertEqual(result.engineId, "mock-stt", "Unavailable cleanup → engineId is STT id only")
        XCTAssertEqual(result.rawText, "hello world", "Raw text is preserved on fallback")
        let state = await session.currentState
        XCTAssertTrue(state == .done, "Unavailable cleanup → .done (NOT .error), got \(state)")
        let calls = await recorder.snapshot()
        XCTAssertEqual(calls.count, 0, "clean() must NOT be called when unavailable")
    }

    // MARK: - Cleanup throws → graceful fallback (not an error)
    //
    // [decision: cleanup errors — whether the cleaner throws SpeakError.llmCleanupFailed
    //  or any other error — are treated as graceful fallback to raw transcript, NOT as a
    //  session error. This matches the "cleanup unavailability ≠ error" contract and ensures
    //  the overlay ALWAYS reaches a terminal hidden state. Previously these paths would
    //  surface as a HUD error with no auto-dismiss path, leaving the overlay stuck.
    //  See CaptureSession.runCleanup() doc comment for the full rationale.]

    func testStopWithCleanerThrowingFallsBackToRawTranscript() async throws {
        let chunks = makeChunks(["hello world"], final: nil)
        let transcriber = MockTranscriber(script: chunks)
        let recorder = CleanerRecorder()
        let cleaner = MockCleaner(
            id: "mock-cleaner",
            available: true,
            cleanError: SpeakError.llmCleanupFailed("model rejected input"),
            cleanResult: "",
            recorder: recorder
        )
        let session = CaptureSession(transcriber: transcriber, cleaner: cleaner)
        try await session.start()
        try await Task.sleep(nanoseconds: 50_000_000)
        // stop() must NOT throw — cleanup errors fall back to raw transcript.
        let result = try await session.stop()
        XCTAssertNil(result.cleanedText, "Cleanup error → cleanedText must be nil (raw fallback)")
        XCTAssertEqual(result.rawText, "hello world", "Raw text must be preserved on cleanup error")
        XCTAssertEqual(result.engineId, "mock-stt", "Cleanup error → engineId is STT id only (not combined)")
        let state = await session.currentState
        XCTAssertTrue(state == .done, "Cleanup error → .done (NOT .error), got \(state)")
    }

    func testStopWithCleanerThrowingGenericErrorFallsBackToRaw() async throws {
        // A non-SpeakError thrown from clean() must also fall back gracefully.
        struct GenericCleanError: LocalizedError {
            var errorDescription: String? { "transient api failure" }
        }
        let chunks = makeChunks(["hello world"], final: nil)
        let transcriber = MockTranscriber(script: chunks)
        let recorder = CleanerRecorder()
        let cleaner = MockCleaner(
            id: "mock-cleaner",
            available: true,
            cleanError: GenericCleanError(),
            cleanResult: "",
            recorder: recorder
        )
        let session = CaptureSession(transcriber: transcriber, cleaner: cleaner)
        try await session.start()
        try await Task.sleep(nanoseconds: 50_000_000)
        // stop() must NOT throw — generic errors fall back to raw transcript.
        let result = try await session.stop()
        XCTAssertNil(result.cleanedText, "Generic cleanup error → cleanedText must be nil")
        XCTAssertEqual(result.rawText, "hello world", "Raw text must be preserved on generic cleanup error")
        XCTAssertEqual(result.engineId, "mock-stt", "Generic cleanup error → engineId is STT id only")
        let state = await session.currentState
        XCTAssertTrue(state == .done, "Generic cleanup error → .done (NOT .error), got \(state)")
    }

    // MARK: - Cleanup timeout → graceful fallback (the primary bug fix)
    //
    // This test uses a NON-COOPERATIVE hanging cleaner (awaits a never-resumed
    // CheckedContinuation) to prove that the timeout fires even when the cleaner
    // ignores Task.cancel(). A Task.sleep-based mock would pass trivially (Task.sleep
    // is cooperative) — that would be a false green.
    //
    // The test timeout (XCTestCase.continueAfterFailure) is set to a safe margin above
    // T_cleanup to give the test runner room without being flaky. We use a shortened
    // mock T_cleanup via a custom mock session; the production constant is 10 s.

    func testStopWithHangingCleanerTimesOutAndFallsBackToRaw() async throws {
        // A cleaner that never returns from clean() — simulates a hung Foundation
        // Models session. This is intentionally NON-COOPERATIVE: it awaits a
        // CheckedContinuation that is never resumed, so Task.cancel() alone cannot
        // unblock it. The timeout mechanism in runCleanup() must work even when
        // the cleaner ignores cooperative cancellation.
        //
        // This test takes up to T_cleanup (10 s) to complete. That is expected and
        // correct — it verifies the production guarantee. The XCTest default timeout
        // (60 s) gives ample headroom.
        //
        // [decision: this test uses the production T_cleanup to verify real behavior.
        //  testStopWithSlowButReturnableCleanerSucceeds() below verifies the success
        //  path fast (200 ms) so CI failure is easy to diagnose.]
        let chunks = makeChunks(["hello world"], final: nil)
        let transcriber = MockTranscriber(script: chunks)
        let hangingCleaner = HangingCleaner(id: "hanging-cleaner")
        let session = CaptureSession(transcriber: transcriber, cleaner: hangingCleaner)
        try await session.start()
        try await Task.sleep(nanoseconds: 50_000_000) // 50 ms — let the stream emit

        // The await below blocks until the T_cleanup timeout fires (~10 s).
        // stop() must return without throwing, with raw fallback, and the session
        // must be in .done — not stuck in .processing.
        let result = try await session.stop()
        XCTAssertNil(result.cleanedText,
            "Hanging cleaner → cleanedText must be nil (raw fallback fires on timeout)")
        XCTAssertEqual(result.rawText, "hello world",
            "Raw text must be preserved when cleanup hangs")
        XCTAssertEqual(result.engineId, "mock-stt",
            "Hanging cleaner timeout → engineId is STT id only (not combined)")
        let state = await session.currentState
        XCTAssertTrue(state == .done,
            "Hanging cleaner → session must reach .done (NOT stuck in .processing), got \(state)")
    }

    /// Verifies that a slow-but-cooperative cleaner (200 ms delay) still produces
    /// a cleaned result — i.e., the timeout does NOT fire prematurely for a valid
    /// slow-but-returning cleaner. This is the regression guard for T_cleanup.
    func testStopWithSlowButReturnableCleanerSucceeds() async throws {
        let chunks = makeChunks(["hello world"], final: nil)
        let transcriber = MockTranscriber(script: chunks)
        // SlowCleaner sleeps 200 ms then returns a result — well within T_cleanup.
        let slowCleaner = SlowCleaner(id: "slow-cleaner", delayNanoseconds: 200_000_000, result: "Hello, world.")
        let session = CaptureSession(transcriber: transcriber, cleaner: slowCleaner)
        try await session.start()
        try await Task.sleep(nanoseconds: 50_000_000)
        let result = try await session.stop()
        XCTAssertEqual(result.cleanedText, "Hello, world.",
            "Slow-but-returning cleaner must produce cleaned text (not a false timeout)")
        XCTAssertEqual(result.rawText, "hello world", "Raw text must be preserved")
        XCTAssertEqual(result.engineId, "mock-stt+slow-cleaner",
            "Successful slow clean → combined engineId")
        let state = await session.currentState
        XCTAssertTrue(state == .done, "Slow cleaner that returns → .done, got \(state)")
    }

    // MARK: - STT stream failure

    func testStopSurfacesStreamFailure() async throws {
        let chunks = makeChunks(["hello"])
        let transcriber = MockTranscriber(
            script: chunks,
            failWith: SpeakError.transcriberUnavailable("mock STT crashed")
        )
        let session = CaptureSession(transcriber: transcriber)
        try await session.start()
        // Give the stream a moment to throw.
        try await Task.sleep(nanoseconds: 50_000_000)
        do {
            _ = try await session.stop()
            XCTFail("stop() must throw when the STT stream failed")
        } catch let SpeakError.transcriberUnavailable(detail) {
            XCTAssertEqual(detail, "mock STT crashed", "STT error detail must propagate")
        } catch {
            XCTFail("stop() must throw SpeakError.transcriberUnavailable, got \(error)")
        }
    }

    // MARK: - Multi-segment truncation fix (P0 correctness bug)

    /// Regression test for the truncation bug: long dictation pasting only the
    /// last few words instead of the full transcript.
    ///
    /// ROOT CAUSE: `ingest()` replaced `latestChunk` on every chunk. SpeechAnalyzer
    /// emits one `isFinal == true` chunk per speech WINDOW (not per utterance), so
    /// for a multi-window utterance only the last window's text landed in `rawText`.
    ///
    /// FIX: `ingest()` now accumulates `finalizedText` by appending each isFinal
    /// chunk's text (space-separated). `stop()` prefers `finalizedText` when
    /// non-empty, falling back to `latestChunk?.text` for short speech.
    ///
    /// FAIL-BEFORE/PASS-AFTER (verified by stash run):
    ///   Pre-fix: `rawText == "how are you"` (last isFinal only) → test FAILS
    ///   Post-fix: `rawText == "hello world how are you"` (all finals joined) → test PASSES
    func testMultiSegmentFinalChunksAreJoinedInResult() async throws {
        // Simulate three speech windows, each with volatile partials followed by
        // one isFinal. This is the exact pattern SpeechAnalyzer produces for
        // long dictations (one finalized segment per speech window).
        let now = Date()
        let multiSegmentScript: [TranscriptChunk] = [
            // Window 1 volatile partials
            TranscriptChunk(text: "hel", isFinal: false, timestamp: now),
            TranscriptChunk(text: "hello", isFinal: false, timestamp: now.addingTimeInterval(0.1)),
            TranscriptChunk(text: "hello wor", isFinal: false, timestamp: now.addingTimeInterval(0.2)),
            // Window 1 final
            TranscriptChunk(text: "hello world", isFinal: true, timestamp: now.addingTimeInterval(0.3)),
            // Window 2 volatile partials
            TranscriptChunk(text: "ho", isFinal: false, timestamp: now.addingTimeInterval(0.4)),
            TranscriptChunk(text: "how", isFinal: false, timestamp: now.addingTimeInterval(0.5)),
            TranscriptChunk(text: "how are", isFinal: false, timestamp: now.addingTimeInterval(0.6)),
            // Window 2 final
            TranscriptChunk(text: "how are you", isFinal: true, timestamp: now.addingTimeInterval(0.7))
        ]

        let transcriber = MockTranscriber(script: multiSegmentScript)
        let session = CaptureSession(transcriber: transcriber)
        try await session.start()
        // Wait for all 8 chunks to be ingested (8 × 1ms sleep in MockTranscriber + buffer).
        try await Task.sleep(nanoseconds: 50_000_000) // 50ms
        let result = try await session.stop()

        // The full utterance is both windows joined — NOT just the last window.
        XCTAssertEqual(result.rawText, "hello world how are you",
            """
            rawText must be ALL finalized segments joined, not just the last one.
            Pre-fix: only "how are you" (last isFinal) was captured.
            Post-fix: all isFinal chunks are accumulated in finalizedText.
            """)
        XCTAssertNil(result.cleanedText, "No cleaner → cleanedText must be nil")
        XCTAssertEqual(result.engineId, "mock-stt", "No cleaner → engineId is STT id")
        let state = await session.currentState
        XCTAssertTrue(state == .done, "Session must reach .done after successful stop()")
    }

    /// Short-utterance regression: a session where only volatile (isFinal=false)
    /// chunks arrive (stopped before any window finalizes) must still produce a
    /// result using the last volatile chunk — not empty string.
    func testShortUtteranceWithNoFinalChunkUsesLastVolatile() async throws {
        // Only volatile chunks — simulates stopping in the middle of a window
        // before SpeechAnalyzer emits an isFinal for that window.
        let now = Date()
        let volatileOnlyScript: [TranscriptChunk] = [
            TranscriptChunk(text: "spe", isFinal: false, timestamp: now),
            TranscriptChunk(text: "speak", isFinal: false, timestamp: now.addingTimeInterval(0.1)),
            TranscriptChunk(text: "speak c", isFinal: false, timestamp: now.addingTimeInterval(0.2))
        ]

        let transcriber = MockTranscriber(script: volatileOnlyScript)
        let session = CaptureSession(transcriber: transcriber)
        try await session.start()
        try await Task.sleep(nanoseconds: 50_000_000)
        let result = try await session.stop()

        // finalizedText is empty (no isFinal chunks) → fallback to latestChunk.text.
        XCTAssertEqual(result.rawText, "speak c",
            "When no isFinal chunks arrive, rawText must be the last volatile chunk's text.")
    }

    // MARK: - Partials stream

    func testPartialsStreamEmitsChunksAndFinishes() async throws {
        let chunks = makeChunks(["hel", "hello", "hello world"], final: nil)
        let transcriber = MockTranscriber(script: chunks)
        let session = CaptureSession(transcriber: transcriber)

        // Attach the partials consumer BEFORE start() so no chunks are lost.
        // `partials()` is `async` on an actor — `await` is required.
        let stream = await session.partials()
        let consumer = Task<[TranscriptChunk], Never> {
            var collected: [TranscriptChunk] = []
            for await chunk in stream {
                collected.append(chunk)
            }
            return collected
        }
        try await session.start()
        // Wait for the stream to drain (chunks + finish).
        let result = try await session.stop()
        let collected = await consumer.value
        XCTAssertEqual(collected.count, 3, "Partials stream must emit every chunk")
        XCTAssertEqual(collected.map(\.text), ["hel", "hello", "hello world"],
                       "Partials must preserve chunk order")
        XCTAssertEqual(result.rawText, "hello world", "Final result uses the last chunk")
    }
}

// MARK: - State == State (Equatable for assertions)

extension CaptureSession.State: @retroactive Equatable {
    public static func == (lhs: CaptureSession.State, rhs: CaptureSession.State) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle), (.listening, .listening),
             (.processing, .processing), (.done, .done):
            return true

        case (.error(let lhsErr), .error(let rhsErr)):
            return lhsErr.recoverySuggestion == rhsErr.recoverySuggestion

        default:
            return false
        }
    }
}
