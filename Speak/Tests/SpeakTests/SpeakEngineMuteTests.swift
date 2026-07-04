// SpeakTests/SpeakEngineMuteTests.swift
//
// Headless tests for the hardware-mute gate in `SpeakEngine` (SPEC §7.4 /
// product.md §8 #4 — "when muted, no audio is read; impossible to bypass").
//
// SCOPE:
//   These run WITHOUT the live speech model or any hardware — they use a mock
//   `Transcribing` that RECORDS whether `startStream` was ever called. That
//   recording is the load-bearing assertion: a muted engine must never start
//   the transcriber, so no microphone capture is ever initiated. Unlike the
//   real-component integration test (which XCTSkips without an installed model),
//   these always execute, so the privacy guarantee is actually proven, not skipped.
//
// ENFORCEMENT POINT:
//   The gate lives in `SpeakEngine.beginDictation()` — the single place that
//   constructs a `CaptureSession` and starts the transcriber. Gating there (not
//   in the UI) is what makes the guarantee bypass-proof: there is no other path
//   to start capture.

@testable import SpeakCore
import XCTest

final class SpeakEngineMuteTests: XCTestCase {

    // MARK: - Mock transcriber (records whether capture was ever started)

    /// A `Transcribing` mock whose only job is to record if `startStream` was
    /// called. `@unchecked Sendable` with an NSLock — `startStream` may be called
    /// from the engine actor while the test reads `didStartStream` from the test
    /// task; the lock makes that access data-race-free.
    private final class RecordingTranscriber: Transcribing, @unchecked Sendable {
        let id = "mock-recording-stt"
        private let lock = NSLock()
        private var _didStart = false

        var didStartStream: Bool {
            lock.lock(); defer { lock.unlock() }
            return _didStart
        }

        func startStream(locale: Locale) -> AsyncThrowingStream<TranscriptChunk, Error> {
            lock.lock(); _didStart = true; lock.unlock()
            return AsyncThrowingStream { continuation in
                continuation.yield(TranscriptChunk(text: "hello", isFinal: true, timestamp: Date()))
                continuation.finish()
            }
        }

        func stop() async {}
    }

    /// A no-op history store so the engine can be constructed headlessly.
    private final class NullHistory: HistoryStoring, @unchecked Sendable {
        func save(_ entry: HistoryEntry) async throws {}
        func recent(limit: Int) async throws -> [HistoryEntry] { [] }
        func search(_ substring: String) async throws -> [HistoryEntry] { [] }
        func clear() async throws {}
        func export() async throws -> String { "[]" }
    }

    // MARK: - Helpers

    /// Build an engine wired to a recording transcriber and an isolated
    /// SettingsStore (never touches `.standard`).
    private func makeEngine(transcriber: RecordingTranscriber) throws -> SpeakEngine {
        let suiteName = "SpeakEngineMuteTests.\(UUID().uuidString)"
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

    // MARK: - Tests

    /// Default state is unmuted.
    func testDefaultIsUnmuted() async throws {
        let engine = try makeEngine(transcriber: RecordingTranscriber())
        let muted = await engine.isMuted
        XCTAssertFalse(muted, "A fresh engine must default to unmuted.")
    }

    /// `setMuted(true)` is reflected by `isMuted`.
    func testSetMutedReflected() async throws {
        let engine = try makeEngine(transcriber: RecordingTranscriber())
        await engine.setMuted(true)
        let muted = await engine.isMuted
        XCTAssertTrue(muted, "isMuted must reflect setMuted(true).")
    }

    /// `toggleMute()` flips the value and returns the new state each call.
    func testToggleMuteFlipsAndReturnsNewValue() async throws {
        let engine = try makeEngine(transcriber: RecordingTranscriber())
        let first = await engine.toggleMute()
        XCTAssertTrue(first, "First toggle from unmuted must return true.")
        let second = await engine.toggleMute()
        XCTAssertFalse(second, "Second toggle must return false.")
        let finalState = await engine.isMuted
        XCTAssertFalse(finalState, "isMuted must equal the last toggle result.")
    }

    /// THE GUARANTEE: when muted, beginDictation throws `.microphoneMuted` AND
    /// the transcriber is never started — so no audio is ever captured.
    func testMutedRefusesBeginAndNeverStartsTranscriber() async throws {
        let transcriber = RecordingTranscriber()
        let engine = try makeEngine(transcriber: transcriber)
        await engine.setMuted(true)

        do {
            try await engine.beginDictation()
            XCTFail("beginDictation must throw when muted.")
        } catch SpeakError.microphoneMuted {
            // expected
        } catch {
            XCTFail("Expected SpeakError.microphoneMuted, got \(error).")
        }

        // The load-bearing assertion: capture was never started.
        XCTAssertFalse(transcriber.didStartStream,
            "Muted engine MUST NOT start the transcriber — no audio may be read (SPEC §7.4).")

        // And no session is in flight.
        let state = await engine.currentState
        XCTAssertEqual(String(describing: state), String(describing: CaptureSession.State.idle),
            "Muted engine must stay idle (no session created).")
    }

    /// When unmuted, beginDictation starts the transcriber (the gate is not
    /// over-blocking). Cancel afterward to avoid a dangling session.
    func testUnmutedAllowsBeginAndStartsTranscriber() async throws {
        let transcriber = RecordingTranscriber()
        let engine = try makeEngine(transcriber: transcriber)

        try await engine.beginDictation()
        XCTAssertTrue(transcriber.didStartStream,
            "Unmuted engine must start the transcriber.")
        await engine.cancelDictation()
    }

    /// THE GUARANTEE (in-flight half): muting while a session is `.listening`
    /// stops capture — the session is no longer listening (SPEC §7.4 "toggles
    /// capture"). A mute that only blocked *starting* would keep reading audio.
    func testMutingStopsInFlightCapture() async throws {
        let transcriber = RecordingTranscriber()
        let engine = try makeEngine(transcriber: transcriber)

        try await engine.beginDictation()
        let listening = await engine.currentState
        XCTAssertEqual(String(describing: listening), String(describing: CaptureSession.State.listening),
            "Precondition: engine must be listening before we mute.")

        await engine.setMuted(true)

        let afterMute = await engine.currentState
        XCTAssertNotEqual(String(describing: afterMute), String(describing: CaptureSession.State.listening),
            "Muting mid-capture MUST stop the in-flight session — no audio may keep being read (SPEC §7.4).")
    }

    /// Unmuting after a muted refusal restores the ability to dictate.
    func testUnmuteRestoresDictation() async throws {
        let transcriber = RecordingTranscriber()
        let engine = try makeEngine(transcriber: transcriber)

        await engine.setMuted(true)
        do {
            try await engine.beginDictation()
            XCTFail("should refuse")
        } catch SpeakError.microphoneMuted {
            // expected
        }

        await engine.setMuted(false)
        try await engine.beginDictation()
        XCTAssertTrue(transcriber.didStartStream,
            "After unmuting, beginDictation must start capture again.")
        await engine.cancelDictation()
    }
}
