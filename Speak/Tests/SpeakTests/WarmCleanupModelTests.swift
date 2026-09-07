// SpeakTests/WarmCleanupModelTests.swift
//
// V01-W (specs/voicestudio-inspiration-plan.md W01) — warm cleanup model.
//
// Contract under test:
//   • Warm-up armed (non-nil handler, cleanup will run) → handler fires on start().
//   • Warm-up disarmed (nil handler — cleanup off / unavailable path) → provably
//     no-op: no task spawned, delivery byte-identical to pre-V01-W.
//   • A warm-up in flight when stop() runs is cancelled, never awaited: the real
//     clean() still runs on its own session and delivery is unaffected.
//   • A failed warm-up is a logged no-op, never an error: start/stop still reach
//     .done and paste runs.
//   • `LLMCleaning.warmUp()` defaults to no-op; `FoundationModelsCleaner.warmUp()`
//     always returns (both the unavailable early-return and the live path).
//
// Drives `CaptureSession` directly (no `beginDictation`) so no mic authorization
// is needed — same pattern as VoiceActionsPipelineTests / CaptureSessionTests.

@testable import SpeakCore
import XCTest

final class WarmCleanupModelTests: XCTestCase {

    // MARK: - Doubles

    /// Scripted STT: yields one final chunk then finishes on its own (no
    /// stop-gating), so `stop()` proceeds deterministically.
    private final class ScriptedTranscriber: Transcribing, @unchecked Sendable {
        let id = "scripted-stt"
        private let script: [TranscriptChunk]
        init(finalText: String) {
            self.script = [TranscriptChunk(text: finalText, isFinal: true, timestamp: Date())]
        }
        func startStream(locale: Locale) -> AsyncThrowingStream<TranscriptChunk, Error> {
            let script = self.script
            return AsyncThrowingStream { continuation in
                Task {
                    for chunk in script {
                        continuation.yield(chunk)
                        try? await Task.sleep(nanoseconds: 1_000_000)
                    }
                    continuation.finish()
                }
            }
        }
        func stop() async {}
    }

    /// Records every text handed to the paste step.
    private actor RecordingInserter: TextInserting {
        private(set) var calls: [String] = []
        func insert(_ text: String) async throws { calls.append(text) }
        func snapshot() -> [String] { calls }
    }

    /// Mock cleaner with controllable availability + a `warmUp()` override that
    /// records invocations. `clean()` appends a marker so tests can tell the
    /// real clean apart from any warm-up traffic.
    private final class MockCleaner: LLMCleaning, @unchecked Sendable {
        let id = "mock-cleaner"
        let available: Bool
        private let lock = NSLock()
        private var _warmUpCalls = 0
        private var _cleanCalls = 0
        init(available: Bool = true) { self.available = available }
        var isAvailable: Bool { get async { available } }
        func clean(_ text: String, mode: CleanupMode) async throws -> String {
            lock.withLock { _cleanCalls += 1 }
            return "\(text) [cleaned]"
        }
        func warmUp() async {
            lock.withLock { _warmUpCalls += 1 }
        }
        var warmUpCalls: Int { lock.withLock { _warmUpCalls } }
        var cleanCalls: Int { lock.withLock { _cleanCalls } }
    }

    /// A no-op history store so the engine can be constructed headlessly.
    private final class NullHistory: HistoryStoring, @unchecked Sendable {
        func save(_ entry: HistoryEntry) async throws {}
        func recent(limit: Int) async throws -> [HistoryEntry] { [] }
        func search(_ substring: String) async throws -> [HistoryEntry] { [] }
        func clear() async throws {}
        func export() async throws -> String { "[]" }
    }

    /// Isolated `SettingsStore` (never touches `.standard`).
    private func makeSettings(cleanupEnabled: Bool = true) throws -> SettingsStore {
        let suiteName = "WarmCleanupModelTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        addTeardownBlock { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
        let settings = SettingsStore(defaults: defaults)
        settings.cleanupEnabled = cleanupEnabled
        return settings
    }

    private func drive(_ session: CaptureSession) async throws -> TranscriptionResult {
        try await session.start()
        try await Task.sleep(nanoseconds: 30_000_000)  // let the scripted chunk emit
        return try await session.stop()
    }

    /// Poll until `condition()` is true or the deadline passes. Warm-up fires
    /// on a background task, so tests must wait rather than assert synchronously.
    private func pollUntil(
        timeoutNanoseconds: UInt64 = 2_000_000_000,
        _ condition: @escaping @Sendable () async -> Bool
    ) async -> Bool {
        let deadline = DispatchTime.now().uptimeNanoseconds + timeoutNanoseconds
        while DispatchTime.now().uptimeNanoseconds < deadline {
            if await condition() { return true }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        return await condition()
    }

    // MARK: - Warm-up fires on start when armed

    func testWarmUpHandler_firesOnStartWhenArmed() async throws {
        let cleaner = MockCleaner()
        let inserter = RecordingInserter()
        let session = CaptureSession(
            transcriber: ScriptedTranscriber(finalText: "hello warm world"),
            cleaner: cleaner,
            inserter: inserter,
            warmUpHandler: { await cleaner.warmUp() }
        )

        let armed = await session.isWarmUpArmed
        XCTAssertTrue(armed, "A non-nil handler must read as armed.")
        try await session.start()
        let fired = await pollUntil { cleaner.warmUpCalls > 0 }
        XCTAssertTrue(fired, "start() must fire the warm-up handler concurrently with listening.")
        _ = try await session.stop()
        XCTAssertEqual(cleaner.warmUpCalls, 1, "Warm-up must fire exactly once per dictation.")
    }

    // MARK: - Disarmed (nil handler) ⇒ provably no-op, byte-identical delivery

    func testWarmUpHandler_nilHandler_isDisarmedAndPastesUnchanged() async throws {
        let inserter = RecordingInserter()
        let session = CaptureSession(
            transcriber: ScriptedTranscriber(finalText: "plain dictation"),
            cleaner: nil,
            inserter: inserter,
            warmUpHandler: nil
        )

        let disarmed = await session.isWarmUpArmed
        XCTAssertFalse(disarmed, "A nil handler must read as disarmed.")
        let result = try await drive(session)

        XCTAssertEqual(result.rawText, "plain dictation")
        let pasted = await inserter.snapshot()
        XCTAssertEqual(pasted, ["plain dictation"],
                       "Disarmed warm-up must leave delivery byte-identical to pre-V01-W.")
    }

    func testWarmUpHandler_armedButInstant_noChangeToDelivery() async throws {
        // Armed with an immediately-returning handler (what a failed/unavailable
        // warm-up looks like from the session's side): delivery must be unchanged.
        let cleaner = MockCleaner()
        let inserter = RecordingInserter()
        let session = CaptureSession(
            transcriber: ScriptedTranscriber(finalText: "hello dictation"),
            cleaner: cleaner,
            inserter: inserter,
            warmUpHandler: { await cleaner.warmUp() }
        )

        let result = try await drive(session)

        XCTAssertEqual(result.rawText, "hello dictation")
        XCTAssertEqual(result.cleanedText, "hello dictation [cleaned]",
                       "The real clean() must still run exactly once, on its own path.")
        XCTAssertEqual(cleaner.cleanCalls, 1)
        let pasted = await inserter.snapshot()
        XCTAssertEqual(pasted, ["hello dictation [cleaned]"])
    }

    // MARK: - In-flight warm-up is cancelled by stop(); real clean unaffected

    func testWarmUpHandler_inFlightAtStop_isCancelledAndRealCleanRuns() async throws {
        let cleaner = MockCleaner()
        let inserter = RecordingInserter()
        let entered = ActorFlag()
        let sawCancellation = ActorFlag()
        // A warm-up that stays in flight until cancelled — the worst case stop()
        // must handle: cancel the handle, never await it.
        let session = CaptureSession(
            transcriber: ScriptedTranscriber(finalText: "cancel me warmly"),
            cleaner: cleaner,
            inserter: inserter,
            warmUpHandler: {
                await entered.set()
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 5_000_000)
                }
                await sawCancellation.set()
            }
        )

        try await session.start()
        let didEnter = await pollUntil { await entered.value }
        XCTAssertTrue(didEnter, "The warm-up must be in flight before stop() runs.")
        let result = try await session.stop()

        XCTAssertEqual(result.cleanedText, "cancel me warmly [cleaned]",
                       "Cancelling warm-up must not disturb the real clean().")
        XCTAssertEqual(cleaner.cleanCalls, 1)
        let pasted = await inserter.snapshot()
        XCTAssertEqual(pasted, ["cancel me warmly [cleaned]"])
        let observed = await pollUntil { await sawCancellation.value }
        XCTAssertTrue(observed, "stop() must cancel the in-flight warm-up task.")
    }

    // MARK: - Engine wiring

    func testEngine_cleanupEnabled_wiresWarmUpArmed() async throws {
        let settings = try makeSettings(cleanupEnabled: true)
        let engine = SpeakEngine(
            transcriber: ScriptedTranscriber(finalText: "engine wired"),
            cleaner: MockCleaner(),
            inserter: nil,
            history: NullHistory(),
            settings: settings
        )
        let session = await engine.newSession()
        let wiredArmed = await session.isWarmUpArmed
        XCTAssertTrue(wiredArmed,
                      "newSession() with cleanup enabled must arm warm-up.")
    }

    func testEngine_cleanupDisabled_leavesWarmUpDisarmed() async throws {
        let settings = try makeSettings(cleanupEnabled: false)
        let engine = SpeakEngine(
            transcriber: ScriptedTranscriber(finalText: "engine off"),
            cleaner: MockCleaner(),
            inserter: nil,
            history: NullHistory(),
            settings: settings
        )
        let session = await engine.newSession()
        let offArmed = await session.isWarmUpArmed
        XCTAssertFalse(offArmed,
                       "newSession() with cleanup disabled must pass nil (byte-identical path).")
    }

    func testEngine_cleanupLevelNone_leavesWarmUpDisarmed() async throws {
        let settings = try makeSettings(cleanupEnabled: true)
        settings.cleanupLevel = .none
        let engine = SpeakEngine(
            transcriber: ScriptedTranscriber(finalText: "engine none"),
            cleaner: MockCleaner(),
            inserter: nil,
            history: NullHistory(),
            settings: settings
        )
        let session = await engine.newSession()
        let noneArmed = await session.isWarmUpArmed
        XCTAssertFalse(noneArmed,
                       "cleanupLevel=.none means no model call — warm-up must stay disarmed.")
    }

    // MARK: - LLMCleaning default + real-cleaner warm-up

    /// The protocol default must be a safe no-op for engines with no cold-start
    /// cost (e.g. `OpenAICompatibleCleaner` inherits it unchanged).
    func testLLMCleaning_defaultWarmUp_isNoOp() async {
        let cleaner = MockCleanerNoWarmUpOverride()
        await cleaner.warmUp()
        let wasCalled = await cleaner.cleanWasCalled
        XCTAssertFalse(wasCalled, "Default warmUp() must not trigger any clean().")
    }

    /// `FoundationModelsCleaner.warmUp()` must always return — via the
    /// unavailable early-return on this (Apple-Intelligence-gated) Mac, or via
    /// the throwaway prewarm+respond on a live Mac. Either way it never throws
    /// (non-throwing by type) and never affects later calls. No timing
    /// assertions: duration is machine-dependent by design.
    @available(macOS 26.0, *)
    func testFoundationModelsCleaner_warmUp_alwaysReturns() async {
        let cleaner = FoundationModelsCleaner()
        await cleaner.warmUp()
        await cleaner.warmUp()
    }

    /// A mock cleaner that does NOT override `warmUp()` — pins the default.
    private actor MockCleanerNoWarmUpOverride: LLMCleaning {
        let id = "mock-cleaner-no-warmup"
        private(set) var cleanWasCalled = false
        var isAvailable: Bool { true }
        func clean(_ text: String, mode: CleanupMode) async throws -> String {
            cleanWasCalled = true
            return text
        }
    }
}

/// Minimal async boolean flag for cross-task test signalling.
private actor ActorFlag {
    private(set) var value = false
    func set() { value = true }
}
