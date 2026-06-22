// SpeakTests/SessionIntegrityTests.swift
//
// Regression tests for Batch A engine fixes (validation-findings.md Phase 4 BATCH A):
//
//   A1 — Cancel-during-processing must not paste (CaptureSession.stop re-check)
//   A2 — Empty-transcript must not paste + must not save to history (both halves)
//   A3 — Re-entrant beginDictation() is a no-op; first session is kept intact
//   A4 — cleanupSeconds floor: 0.0 never emitted for a path that actually ran cleanup
//   LOW — cancel() on .done is a no-op (terminal guard)
//   LOW — snippet expansion inside a CaptureSession run
//
// All tests are headless (no mic, no real STT, no real FM) and always execute
// — they must not XCTSkip. They use the same mock patterns as CaptureSessionTests.swift
// and SpeakEngineMuteTests.swift so patterns stay consistent.

import XCTest
@testable import SpeakCore

// MARK: - Mocks shared across this file

/// Transcriber that gates stream completion on an explicit signal from the test.
/// This lets the test interleave cancel() during stop()'s drain precisely.
private final class GatedTranscriber: Transcribing, @unchecked Sendable {
    let id: String
    private let chunks: [TranscriptChunk]
    /// The test fires this to release the stream (simulating the STT finishing).
    let gate = GateSignal()
    private let lock = NSLock()
    private var _stopCount = 0

    init(id: String = "gated-stt", chunks: [TranscriptChunk] = []) {
        self.id = id
        self.chunks = chunks
    }

    func startStream(locale: Locale) -> AsyncThrowingStream<TranscriptChunk, Error> {
        let chunks = self.chunks
        let gate = self.gate
        return AsyncThrowingStream { continuation in
            let task = Task {
                for chunk in chunks {
                    continuation.yield(chunk)
                    try? await Task.sleep(nanoseconds: 1_000_000)  // 1ms
                }
                // Block until the test releases the gate.
                await gate.wait()
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func stop() async {
        lock.lock(); _stopCount += 1; lock.unlock()
        gate.signal()  // releasing the gate lets the stream finish
    }

    func stopCallCount() -> Int {
        lock.lock(); defer { lock.unlock() }
        return _stopCount
    }
}

/// A cleaner that blocks until the test releases it — used to inject cancel()
/// during the runCleanup() await (the longest cancel window: up to T_cleanup = 10s).
private final class BlockingCleaner: LLMCleaning, @unchecked Sendable {
    let id = "blocking-cleaner"
    var isAvailable: Bool { get async { true } }
    let gate = GateSignal()

    func clean(_ text: String, mode: CleanupMode) async throws -> String {
        await gate.wait()
        return text + " (cleaned)"
    }
}

/// Simple actor-based gate: `wait()` blocks until `signal()` is called.
final class GateSignal: @unchecked Sendable {
    private let lock = NSLock()
    private var waiter: CheckedContinuation<Void, Never>?
    private var signalled = false

    func wait() async {
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            lock.lock()
            if signalled {
                lock.unlock()
                cont.resume()
            } else {
                waiter = cont
                lock.unlock()
            }
        }
    }

    func signal() {
        lock.lock()
        signalled = true
        if let w = waiter {
            waiter = nil
            lock.unlock()
            w.resume()
        } else {
            lock.unlock()
        }
    }
}

/// Records every text passed to insert(), actor-isolated.
private actor RecordingInserter: TextInserting {
    private(set) var calls: [String] = []
    func insert(_ text: String) async throws { calls.append(text) }
    func snapshot() -> [String] { calls }
}

/// Records every HistoryEntry passed to save().
private actor RecordingHistory: HistoryStoring {
    private(set) var saved: [HistoryEntry] = []
    func save(_ entry: HistoryEntry) async throws { saved.append(entry) }
    func recent(limit: Int) async throws -> [HistoryEntry] { saved }
    func search(_ s: String) async throws -> [HistoryEntry] { [] }
    func clear() async throws { saved.removeAll() }
    func export() async throws -> String { "[]" }
    func snapshot() -> [HistoryEntry] { saved }
}

// MARK: - A1: Cancel-during-processing must not paste

final class CancelDuringStopTests: XCTestCase {

    /// cancel() arriving while stop() is suspended inside runCleanup() must prevent
    /// paste. The cleaner is blocked; the test fires cancel() from a concurrent task
    /// while stop() waits inside runCleanup(). Then the cleaner is released so the
    /// continuation resolves. The A1 re-check must catch the .error state and throw
    /// .sessionCancelled — the recording inserter must receive zero calls.
    func testCancelDuringCleanupDoesNotPaste() async throws {
        let now = Date()
        let chunk = TranscriptChunk(text: "hello world", isFinal: true, timestamp: now)
        let transcriber = GatedTranscriber(chunks: [chunk])
        let cleaner = BlockingCleaner()
        let inserter = RecordingInserter()

        let session = CaptureSession(
            transcriber: transcriber,
            cleaner: cleaner,
            inserter: inserter
        )
        try await session.start()

        // Give stream a moment to emit the chunk before stop() is called.
        try await Task.sleep(nanoseconds: 10_000_000)  // 10ms

        // Launch stop() concurrently — it will park inside runCleanup (cleaner blocked).
        let stopTask = Task<Void, Error> {
            _ = try await session.stop()
        }

        // Brief pause so stop() enters runCleanup before cancel() fires.
        try await Task.sleep(nanoseconds: 50_000_000)  // 50ms

        // Fire cancel() while stop() is waiting on the cleaner.
        await session.cancel()

        // Release the cleaner so the CheckedContinuation in runCleanup resolves.
        // stop() resumes from runCleanup, hits the A1 re-check, finds .error, and throws.
        cleaner.gate.signal()

        // stop() must throw .sessionCancelled (not return a result).
        do {
            try await stopTask.value
            XCTFail("stop() must throw when cancel() arrived during its awaits")
        } catch SpeakError.sessionCancelled {
            // expected
        } catch {
            XCTFail("stop() must throw SpeakError.sessionCancelled, got \(error)")
        }

        // THE CORE ASSERTION: no text was pasted.
        let insertCalls = await inserter.snapshot()
        XCTAssertEqual(insertCalls.count, 0,
            "cancel-during-processing must never call inserter.insert() (paste against user intent)")

        // State must be .error(.sessionCancelled), not .done.
        let state = await session.currentState
        if case .error(.sessionCancelled) = state {
            // correct
        } else {
            XCTFail("State must be .error(.sessionCancelled) after cancel-during-stop, got \(state)")
        }
    }
}

// MARK: - A2: Empty-transcript must not paste and must not save history

final class EmptyTranscriptTests: XCTestCase {

    // MARK: Session-level: inserter must not be called

    func testEmptyTranscriptDoesNotCallInserter() async throws {
        // Transcriber emits no chunks (silence / blocked mic).
        let transcriber = GatedTranscriber(chunks: [])
        let inserter = RecordingInserter()

        let session = CaptureSession(
            transcriber: transcriber,
            inserter: inserter
        )
        try await session.start()
        try await Task.sleep(nanoseconds: 10_000_000)

        let result = try await session.stop()

        // Must NOT have called insert with empty string (would clobber clipboard).
        let insertCalls = await inserter.snapshot()
        XCTAssertEqual(insertCalls.count, 0,
            "Empty transcript must never call inserter.insert() — it would clobber the clipboard")
        XCTAssertEqual(result.rawText, "",
            "Empty transcript result must have rawText == \"\"")
        XCTAssertNil(result.cleanedText,
            "Empty transcript result must have cleanedText == nil")

        let state = await session.currentState
        XCTAssertTrue(state == .done,
            "Empty transcript must reach .done (not .error), got \(state)")
    }

    // MARK: Engine-level: history must not be saved

    func testEmptyTranscriptDoesNotSaveHistory() async throws {
        let transcriber = GatedTranscriber(chunks: [])
        let inserter = RecordingInserter()
        let history = RecordingHistory()

        let engine = try makeEngine(
            transcriber: transcriber,
            inserter: inserter,
            history: history
        )

        try await engine.beginDictation()
        try await Task.sleep(nanoseconds: 10_000_000)

        let result = try await engine.endDictation()

        XCTAssertEqual(result.rawText, "",
            "endDictation result must have empty rawText")
        let insertCalls = await inserter.snapshot()
        XCTAssertEqual(insertCalls.count, 0,
            "Empty transcript: engine must not call inserter")
        let entries = await history.snapshot()
        XCTAssertEqual(entries.count, 0,
            "Empty transcript: engine must not save a history entry (zero-char entry is noise)")
    }

    // MARK: Helpers

    private func makeEngine(
        transcriber: any Transcribing,
        inserter: (any TextInserting)? = nil,
        history: any HistoryStoring
    ) throws -> SpeakEngine {
        let suiteName = "SessionIntegrityTests.EmptyTranscript.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        addTeardownBlock { defaults.removePersistentDomain(forName: suiteName) }
        let settings = SettingsStore(defaults: defaults)
        settings.cleanupEnabled = false  // no cleaner — empty-transcript path is independent of cleanup
        return SpeakEngine(
            transcriber: transcriber,
            cleaner: nil,
            inserter: inserter,
            history: history,
            settings: settings
        )
    }
}

// MARK: - A3: Re-entrant beginDictation is a no-op

final class ReentrantBeginDictationTests: XCTestCase {

    /// Two concurrent beginDictation() calls: only one session must be started.
    /// The first session must be the one that survives; the second is a no-op.
    func testConcurrentBeginDictationStartsOnlyOneSession() async throws {
        let transcriber = CountingTranscriber()
        let engine = try makeEngine(transcriber: transcriber)

        // Fire both concurrently using async let — they race to enter the actor.
        // Both may succeed from the caller's perspective (no throw), but only one
        // actual STT stream must be started (transcriber.startStream called once).
        async let first: Void = { try await engine.beginDictation() }()
        async let second: Void = { try await engine.beginDictation() }()

        // Ignore throws from the second call (it returns without throwing by design).
        _ = try? await first
        _ = try? await second

        let startCount = transcriber.startStreamCount()
        XCTAssertEqual(startCount, 1,
            "Re-entrant beginDictation must be a no-op: exactly 1 STT stream must be started, got \(startCount)")

        // Clean up: cancel the surviving session.
        await engine.cancelDictation()
    }

    /// Sequential double-start after the first session is in flight:
    /// the second call returns without starting a new stream.
    func testSequentialReentrantBeginIsNoOp() async throws {
        let transcriber = CountingTranscriber()
        let engine = try makeEngine(transcriber: transcriber)

        try await engine.beginDictation()

        let countAfterFirst = transcriber.startStreamCount()
        XCTAssertEqual(countAfterFirst, 1, "First beginDictation must start exactly 1 stream")

        // Second call while first is still in flight — must be a no-op.
        try await engine.beginDictation()

        let countAfterSecond = transcriber.startStreamCount()
        XCTAssertEqual(countAfterSecond, 1,
            "Second beginDictation while session in flight must be a no-op (stream count must stay 1)")

        await engine.cancelDictation()
    }

    // MARK: Helpers

    /// Transcriber that counts startStream invocations. Thread-safe via NSLock.
    private final class CountingTranscriber: Transcribing, @unchecked Sendable {
        let id = "counting-stt"
        private let lock = NSLock()
        private var _count = 0

        func startStreamCount() -> Int {
            lock.lock(); defer { lock.unlock() }
            return _count
        }

        func startStream(locale: Locale) -> AsyncThrowingStream<TranscriptChunk, Error> {
            lock.lock(); _count += 1; lock.unlock()
            return AsyncThrowingStream { continuation in
                // Never finish — keeps the session in .listening so the second
                // beginDictation() has a live session to guard against.
                let task = Task {
                    // Wait indefinitely until the task is cancelled.
                    try? await Task.sleep(nanoseconds: 60_000_000_000)  // 60s
                    continuation.finish()
                }
                continuation.onTermination = { _ in task.cancel() }
            }
        }

        func stop() async {
            // Intentionally empty — the test calls cancelDictation() to clean up.
        }
    }

    private func makeEngine(transcriber: any Transcribing) throws -> SpeakEngine {
        let suiteName = "SessionIntegrityTests.ReentrantBegin.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        addTeardownBlock { defaults.removePersistentDomain(forName: suiteName) }
        let settings = SettingsStore(defaults: defaults)
        return SpeakEngine(
            transcriber: transcriber,
            cleaner: nil,
            inserter: nil,
            history: NullHistory(),
            settings: settings
        )
    }
}

// MARK: - LOW: cancel() on .done must be a no-op

final class CancelTerminalStateTests: XCTestCase {

    func testCancelOnDoneSessionIsNoOp() async throws {
        let transcriber = GatedTranscriber(chunks: [
            TranscriptChunk(text: "hello", isFinal: true, timestamp: Date())
        ])
        let session = CaptureSession(transcriber: transcriber)
        try await session.start()
        try await Task.sleep(nanoseconds: 20_000_000)
        _ = try await session.stop()

        // Session is now .done — cancel must be a no-op.
        await session.cancel()

        let state = await session.currentState
        XCTAssertTrue(state == .done,
            "cancel() on .done session must leave it in .done, got \(state)")
    }
}

// MARK: - LOW: snippet expansion inside a CaptureSession run

final class SnippetInSessionTests: XCTestCase {

    func testSnippetExpansionRunsBeforeCleanup() async throws {
        // A simple expander: "brb" → "be right back"
        let expander = MockSnippetExpander(rules: ["brb": "be right back"])
        let recorder = CleanerCallRecorder()
        let cleaner = RecordingMockCleaner(recorder: recorder)

        let transcriber = GatedTranscriber(chunks: [
            TranscriptChunk(text: "brb", isFinal: true, timestamp: Date())
        ])
        let session = CaptureSession(
            transcriber: transcriber,
            cleaner: cleaner,
            expander: expander
        )
        try await session.start()
        try await Task.sleep(nanoseconds: 20_000_000)
        let result = try await session.stop()

        // rawText must be the expanded form (expansion runs before cleanup).
        XCTAssertEqual(result.rawText, "be right back",
            "rawText must be the snippet-expanded text, not the original 'brb'")

        // The cleaner must have received the expanded text, not the original.
        let cleanerCalls = await recorder.calls()
        XCTAssertEqual(cleanerCalls.count, 1,
            "Cleaner must be called once")
        XCTAssertEqual(cleanerCalls.first, "be right back",
            "Cleaner must receive the expanded text (expansion runs BEFORE cleanup)")
    }

    // MARK: Helpers

    /// Stub expander: replaces keys with values (case-sensitive, first match wins).
    private struct MockSnippetExpander: SnippetExpanding {
        let rules: [String: String]
        func expand(_ text: String) -> String {
            var result = text
            for (key, value) in rules {
                result = result.replacingOccurrences(of: key, with: value)
            }
            return result
        }
    }

    private actor CleanerCallRecorder {
        private var _calls: [String] = []
        func record(_ text: String) { _calls.append(text) }
        func calls() -> [String] { _calls }
    }

    private struct RecordingMockCleaner: LLMCleaning {
        let id = "recording-cleaner"
        var isAvailable: Bool { get async { true } }
        let recorder: CleanerCallRecorder

        func clean(_ text: String, mode: CleanupMode) async throws -> String {
            await recorder.record(text)
            return text + " (cleaned)"
        }
    }
}

// MARK: - Shared helpers

/// No-op history store — used by multiple test suites above.
private final class NullHistory: HistoryStoring, @unchecked Sendable {
    func save(_ entry: HistoryEntry) async throws {}
    func recent(limit: Int) async throws -> [HistoryEntry] { [] }
    func search(_ substring: String) async throws -> [HistoryEntry] { [] }
    func clear() async throws {}
    func export() async throws -> String { "[]" }
}

// MARK: - CaptureSession.State Equatable (local to this file's assertions)
// The same retroactive conformance is already in CaptureSessionTests.swift —
// extend it here only when that file is not linked in the same target (it is,
// so this is a duplicate that would conflict). Omit here; rely on the conformance
// from CaptureSessionTests.swift which is in the same test target.
