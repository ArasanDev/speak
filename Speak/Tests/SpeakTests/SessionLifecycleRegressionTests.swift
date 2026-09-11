// SpeakTests/SessionLifecycleRegressionTests.swift
//
// Regression tests for the Wave-2 mic/session lifecycle audit fixes:
//
//   1. Wedge — a transcriber stream that ends THROWING while the session is
//      `.listening` (unrecoverable route/device teardown →
//      `SpeakError.captureInterrupted`) must settle the session `.error`,
//      make `stop()` re-throw, and let `SpeakEngine`'s A3 guard release the
//      terminal session so the next `beginDictation` isn't refused forever.
//   2. Mic-leak — `AppleSpeechTranscriber.stop()` racing a pending session
//      start must never leave the producer's mic open (every `start()`
//      matched by a `stop()`, or the session bails before ever starting).
//   3. Cancel-during-start — a `cancel()` landing while `start()` is
//      suspended on `cleaner.isAvailable` must throw before
//      `transcriber.startStream` runs — the mic never opens on a dead session.
//   4. Watchdog — `awaitStreamDrainWithWatchdog` must actually break a stalled
//      stream drain (~5 s) instead of deadlocking on `Task.value` inside a
//      task group whose children never finish.
//
// None of these touch real audio hardware.

import AVFoundation
@testable import SpeakCore
import XCTest

// MARK: - Test doubles

/// STT double with controllable stream-end behavior. `neverFinish` holds the
/// continuation forever — simulating a stream that stalls mid-dictation (the
/// case the drain watchdog exists to break).
private final class ControllableTranscriber: Transcribing, @unchecked Sendable {
    enum Behavior {
        /// Stream finishes by throwing after the given delay — the positive
        /// teardown signal a real route-change failure produces.
        case finishThrowing(Error, afterMilliseconds: UInt64)
        /// Stream never yields and never finishes — a stalled drain.
        case neverFinish
        /// Stream yields the script then finishes cleanly.
        case clean([TranscriptChunk])
    }

    let id = "controllable-stt"
    let behavior: Behavior

    private let lock = NSLock()
    private var _startStreamCalls = 0
    private var _stopCalls = 0
    private var heldContinuations: [AsyncThrowingStream<TranscriptChunk, Error>.Continuation] = []

    var startStreamCalls: Int { lock.withLock { _startStreamCalls } }
    var stopCalls: Int { lock.withLock { _stopCalls } }

    init(behavior: Behavior) { self.behavior = behavior }

    func startStream(locale: Locale) -> AsyncThrowingStream<TranscriptChunk, Error> {
        lock.withLock { _startStreamCalls += 1 }
        let behavior = self.behavior
        return AsyncThrowingStream { continuation in
            switch behavior {
            case .finishThrowing(let error, let ms):
                let task = Task {
                    try? await Task.sleep(nanoseconds: ms * 1_000_000)
                    continuation.finish(throwing: error)
                }
                continuation.onTermination = { _ in task.cancel() }

            case .neverFinish:
                lock.withLock { self.heldContinuations.append(continuation) }

            case .clean(let chunks):
                let task = Task {
                    for chunk in chunks {
                        continuation.yield(chunk)
                        try? await Task.sleep(nanoseconds: 1_000_000)
                    }
                    continuation.finish()
                }
                continuation.onTermination = { _ in task.cancel() }
            }
        }
    }

    func stop() async {
        lock.withLock { _stopCalls += 1 }
        // Deliberately does NOT finish .neverFinish streams — the stall is the
        // point: the watchdog must break it, not the producer.
    }
}

/// Cleaner whose `isAvailable` suspends on a test-controlled gate, letting a
/// `cancel()` land deterministically inside `start()`'s await window.
private final class GatedCleaner: LLMCleaning, @unchecked Sendable {
    let id = "gated-cleaner"

    private let lock = NSLock()
    private var entered = false
    private var enteredWaiter: CheckedContinuation<Void, Never>?
    private var gateOpen = false
    private var gateWaiter: CheckedContinuation<Void, Never>?

    var isAvailable: Bool {
        get async {
            lock.lock()
            entered = true
            enteredWaiter?.resume()
            enteredWaiter = nil
            lock.unlock()
            await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                lock.lock()
                if gateOpen {
                    lock.unlock()
                    cont.resume()
                } else {
                    gateWaiter = cont
                    lock.unlock()
                }
            }
            return true
        }
    }

    /// Suspends until `isAvailable` has actually been entered by the session.
    func waitUntilEntered() async {
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            lock.lock()
            if entered {
                lock.unlock()
                cont.resume()
            } else {
                enteredWaiter = cont
                lock.unlock()
            }
        }
    }

    /// Releases the `isAvailable` gate so `start()` resumes.
    func openGate() {
        lock.lock()
        gateOpen = true
        gateWaiter?.resume()
        gateWaiter = nil
        lock.unlock()
    }

    func clean(_ text: String, mode: CleanupMode) async throws -> String { text }
}

/// `AudioBufferProducing` double that counts start/stop calls — the mic-leak
/// assertion is `startCount == stopCount`: every opened mic is released.
private final class StartStopCountingProducer: AudioBufferProducing, @unchecked Sendable {
    private let lock = NSLock()
    private var _startCount = 0
    private var _stopCount = 0
    private var continuation: AsyncThrowingStream<AVAudioPCMBuffer, Error>.Continuation?

    var startCount: Int { lock.withLock { _startCount } }
    var stopCount: Int { lock.withLock { _stopCount } }

    func start() throws -> AsyncThrowingStream<AVAudioPCMBuffer, Error> {
        let (stream, cont) = AsyncThrowingStream<AVAudioPCMBuffer, Error>.makeStream()
        lock.withLock {
            _startCount += 1
            continuation = cont
        }
        return stream
    }

    func stop() {
        lock.withLock {
            _stopCount += 1
            continuation?.finish()
            continuation = nil
        }
    }
}

/// Poll helper — bounded wait for a condition, avoiding the `Task.value`-in-
/// task-group trap (a child parked in a non-cancellation-responsive await
/// wedges the whole group).
private func pollUntil(
    timeoutNanoseconds: UInt64,
    intervalNanoseconds: UInt64 = 10_000_000,
    _ condition: @Sendable () async -> Bool
) async -> Bool {
    let deadline = DispatchTime.now().uptimeNanoseconds + timeoutNanoseconds
    while DispatchTime.now().uptimeNanoseconds < deadline {
        if await condition() { return true }
        try? await Task.sleep(nanoseconds: intervalNanoseconds)
    }
    return await condition()
}

// MARK: - Tests

final class SessionLifecycleRegressionTests: XCTestCase {

    // MARK: 1. Wedge — throwing stream settles `.error`, engine self-heals

    /// A stream that ends THROWING while `.listening` must move the session to
    /// `.error` (via failStream) and make `stop()` re-throw — never wedge.
    func testThrowingStreamMidListenSettlesErrorAndStopRethrows() async throws {
        let interrupted = SpeakError.captureInterrupted("test teardown")
        let transcriber = ControllableTranscriber(
            behavior: .finishThrowing(interrupted, afterMilliseconds: 30)
        )
        let session = CaptureSession(transcriber: transcriber)

        try await session.start()

        let errored = await pollUntil(timeoutNanoseconds: 3_000_000_000) {
            if case .error = await session.currentState { return true }
            return false
        }
        XCTAssertTrue(errored, "session must reach .error after a thrown stream finish")

        do {
            _ = try await session.stop()
            XCTFail("stop() must re-throw the stored stream error")
        } catch let error as SpeakError {
            if case .captureInterrupted = error { /* expected */ } else {
                XCTFail("expected .captureInterrupted, got \(error)")
            }
        }

        let terminalAfterFailure = await session.isTerminal
        XCTAssertTrue(terminalAfterFailure, "session must be terminal after stream failure")
    }

    /// Engine-level wedge check: after a session dies on its own (terminal
    /// `.error` without an explicit endDictation), the next `beginDictation`
    /// must release it via the self-healing A3 guard — not refuse forever.
    func testTerminalSessionDoesNotWedgeBeginDictation() async throws {
        let suiteName = "SessionLifecycleRegressionTests.\(UUID().uuidString)"
        let testDefaults = try XCTUnwrap(
            UserDefaults(suiteName: suiteName),
            "UserDefaults(suiteName:) returned nil for '\(suiteName)'"
        )
        addTeardownBlock { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
        let store = try HistoryStore(databaseURL: TestStorage.tempDatabaseURL())

        let transcriber = ControllableTranscriber(
            behavior: .finishThrowing(
                SpeakError.captureInterrupted("test teardown"),
                afterMilliseconds: 30
            )
        )
        let engine = SpeakEngine(
            transcriber: transcriber,
            history: store,
            settings: SettingsStore(defaults: testDefaults)
        )

        let first = try await engine.beginDictation()
        XCTAssertTrue(first, "first beginDictation must start")

        let errored = await pollUntil(timeoutNanoseconds: 3_000_000_000) {
            if case .error = await engine.currentState { return true }
            return false
        }
        XCTAssertTrue(errored, "session must reach .error after teardown throw")

        // The A3 guard used to return false forever here — the dead session
        // stayed non-nil. Self-heal releases the terminal session instead.
        let second = try await engine.beginDictation()
        XCTAssertTrue(second, "beginDictation must self-heal a terminal session, not refuse")

        await engine.cancelDictation()
    }

    // MARK: 2. Mic-leak — stop() racing a pending session start

    /// `stop()` called immediately after `startStream` (before the session
    /// task has armed on the actor) must still guarantee the mic is never left
    /// open: either the session bails before `producer.start()` (0 == 0) or it
    /// starts and is immediately stopped (1 == 1). The old `stopRequested`
    /// reset let a delayed run() open an orphaned mic (startCount=1,
    /// stopCount=0, stream never finishing). [fix: audit — mic-leak]
    func testStopDuringPendingSessionStartNeverOrphansMic() async throws {
        let producer = StartStopCountingProducer()
        let transcriber = AppleSpeechTranscriber(audioProducer: producer)

        let stream = transcriber.startStream(locale: Locale(identifier: "en-US"))
        // Fire stop() without any intervening await — the session task may not
        // have run its arm hop yet; this is exactly the leak window.
        await transcriber.stop()

        // The session stream must finish — the session task ends on every
        // ordering (bail, start+stop, or early throw inside run()).
        final class FinishFlag: @unchecked Sendable {
            private let lock = NSLock()
            private var _done = false
            var done: Bool { lock.withLock { _done } }
            func mark() { lock.withLock { _done = true } }
        }
        let flag = FinishFlag()
        Task {
            do {
                for try await _ in stream { }
            } catch { }
            flag.mark()
        }

        let finished = await pollUntil(timeoutNanoseconds: 5_000_000_000) { flag.done }
        XCTAssertTrue(finished, "session stream must finish after stop() — an unfinished stream means an orphaned mic")
        XCTAssertEqual(producer.startCount, producer.stopCount,
            "every producer.start() must be matched by producer.stop() — mic released in all orderings")
        XCTAssertLessThanOrEqual(producer.startCount, 1)
    }

    // MARK: 3. Cancel during start — mic never opens on a dead session

    /// cancel() landing while start() is suspended on `cleaner.isAvailable`
    /// must throw `.sessionCancelled` BEFORE `transcriber.startStream` runs.
    /// The pre-fix code re-checked nothing and opened the mic on a session that
    /// was already `.error`. [fix: audit — cancel-during-start]
    func testCancelDuringStartNeverStartsStream() async throws {
        let transcriber = ControllableTranscriber(behavior: .neverFinish)
        let cleaner = GatedCleaner()
        let session = CaptureSession(transcriber: transcriber, cleaner: cleaner)

        let startTask = Task { try await session.start() }

        // Wait until start() is actually suspended inside isAvailable, then cancel.
        await cleaner.waitUntilEntered()
        await session.cancel()
        cleaner.openGate()

        do {
            try await startTask.value
            XCTFail("start() must throw after a cancel landed mid-start")
        } catch let error as SpeakError {
            if case .sessionCancelled = error { /* expected */ } else {
                XCTFail("expected .sessionCancelled, got \(error)")
            }
        }

        XCTAssertEqual(transcriber.startStreamCalls, 0,
            "startStream must never run on a cancelled session — the mic must not open")
        let terminalAfterCancel = await session.isTerminal
        XCTAssertTrue(terminalAfterCancel)
    }

    // MARK: 4. Watchdog — a stalled stream drain must not hang stop()

    /// With a stream that never finishes, `stop()` must return when the ~5 s
    /// watchdog fires (previously unreachable: `await task.value` inside the
    /// task group couldn't be unblocked, so a real stall deadlocked the
    /// watchdog itself). Elapsed asserts the watchdog actually waited — an
    /// instant return would mean the drain gave up early. [fix: audit]
    func testWatchdogBreaksStalledStreamDrain() async throws {
        let transcriber = ControllableTranscriber(behavior: .neverFinish)
        let session = CaptureSession(transcriber: transcriber)

        try await session.start()

        let t0 = DispatchTime.now().uptimeNanoseconds
        let result = try await session.stop()
        let elapsedSeconds = Double(DispatchTime.now().uptimeNanoseconds - t0) / 1e9

        XCTAssertTrue(result.rawText.isEmpty, "stalled stream produced no transcript")
        XCTAssertGreaterThanOrEqual(elapsedSeconds, 4.0,
            "stop() returned in \(elapsedSeconds)s — watchdog fired too early, drain wasn't given its window")
        XCTAssertLessThan(elapsedSeconds, 15.0,
            "stop() took \(elapsedSeconds)s — the watchdog did not break the stall")
    }
}
