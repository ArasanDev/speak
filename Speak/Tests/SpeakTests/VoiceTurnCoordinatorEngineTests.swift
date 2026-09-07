// SpeakTests/VoiceTurnCoordinatorEngineTests.swift
//
// Tests for `SpeakEngine`'s conformance to `VoiceTurnCapturing`, against the
// real engine rather than a double.
//
// WHY THIS FILE EXISTS SEPARATELY FROM `VoiceTurnCoordinatorTests`:
//   That suite proves the coordinator's *logic* against a recording double, and
//   a double cannot prove the one property that matters most here — the double
//   shares no state with `SpeakEngine`, so it cannot observe what happens when an
//   agent turn collides with a dictation the human started.
//
// THE COLLISION:
//   `SpeakEngine.beginDictation()` RETURNS FALSE rather than throwing when a
//   session is already in flight (the [A3] re-entrancy guard). If
//   `beginTurnCapture()` discarded that value, an agent turn arriving mid-
//   dictation would attach its detector to the human's live session, and the
//   turn's flush (`finalizeTurnCapture()` -> `endDictation()`) would end that
//   dictation and swallow its transcript with paste suppressed. The human's
//   sentence would simply vanish. This is the regression the daily-use
//   constraint forbids outright, so it is pinned here rather than reasoned about.
//
// Headless: a mock `Transcribing` that never finishes its stream keeps a session
// live without a microphone, a speech model, or a TCC grant.

import Foundation
@testable import SpeakCore
import XCTest

final class VoiceTurnCoordinatorEngineTests: XCTestCase {

    // MARK: - Doubles

    /// Holds a session open: the stream yields one final chunk and then stays
    /// alive, so `currentSession` remains non-nil for a collision to hit.
    private final class HoldingTranscriber: Transcribing, @unchecked Sendable {
        let id = "holding-stt"
        private let lock = NSLock()
        private var _count = 0

        var startStreamCount: Int {
            lock.lock(); defer { lock.unlock() }
            return _count
        }

        func startStream(locale: Locale) -> AsyncThrowingStream<TranscriptChunk, Error> {
            lock.lock(); _count += 1; lock.unlock()
            return AsyncThrowingStream { continuation in
                continuation.yield(TranscriptChunk(text: "the human was mid sentence",
                                                   isFinal: true,
                                                   timestamp: Date()))
                let task = Task {
                    try? await Task.sleep(nanoseconds: 60_000_000_000)
                    continuation.finish()
                }
                continuation.onTermination = { _ in task.cancel() }
            }
        }

        func stop() async {}
    }

    private final class NullHistory: HistoryStoring, @unchecked Sendable {
        func save(_ entry: HistoryEntry) async throws {}
        func recent(limit: Int) async throws -> [HistoryEntry] { [] }
        func search(_ substring: String) async throws -> [HistoryEntry] { [] }
        func clear() async throws {}
        func export() async throws -> String { "[]" }
    }

    private func makeEngine(transcriber: any Transcribing) throws -> SpeakEngine {
        let suiteName = "VoiceTurnCoordinatorEngineTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        addTeardownBlock { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
        let settings = SettingsStore(defaults: defaults)
        return SpeakEngine(
            transcriber: transcriber,
            cleaner: nil,
            inserter: nil,
            history: NullHistory(),
            settings: settings
        )
    }

    // MARK: - The collision

    /// An agent turn must refuse to adopt a session it did not open. Asserted
    /// three ways, because "it threw" alone would not prove the human's dictation
    /// survived: no second stream is started, the session stays in flight, and
    /// the human's transcript is still theirs to collect afterwards.
    func testAgentTurnRefusesToAdoptAnInFlightDictation() async throws {
        let transcriber = HoldingTranscriber()
        let engine = try makeEngine(transcriber: transcriber)

        // The human presses the hotkey and starts talking.
        let started = try await engine.beginDictation()
        XCTAssertTrue(started)

        // An agent asks for a turn at the worst possible moment.
        do {
            try await engine.beginTurnCapture()
            XCTFail("an agent turn must not adopt the human's in-flight dictation")
        } catch {
            // Expected. The specific case matters less than the refusal.
        }

        XCTAssertEqual(transcriber.startStreamCount, 1,
                       "the refused turn must not have opened a second capture")

        let state = await engine.currentState
        guard case .listening = state else {
            return XCTFail("the human's dictation must still be live after the refusal, got \(state)")
        }

        // And it is still the human's to finish: the transcript comes back to
        // whoever ends it, not to the agent that collided with it.
        let result = try await engine.endDictation()
        XCTAssertEqual(result.rawText, "the human was mid sentence")
    }

    /// The mute gate is a refusal at the engine (SPEC §7.4) and must stay one
    /// through this seam — an agent must never be the reason a muted microphone
    /// opens.
    func testMutedEngineRefusesAnAgentTurn() async throws {
        let transcriber = HoldingTranscriber()
        let engine = try makeEngine(transcriber: transcriber)
        await engine.setMuted(true)

        do {
            try await engine.beginTurnCapture()
            XCTFail("a muted engine must refuse an agent turn")
        } catch let error as SpeakError {
            XCTAssertEqual(error.code, SpeakError.microphoneMuted.code)
        }

        XCTAssertEqual(transcriber.startStreamCount, 0,
                       "a muted engine must never start a capture for an agent")
    }

    /// Detaching from an engine with no session must report failure rather than
    /// pretending it worked — the coordinator turns that false into a failed
    /// turn, which is the only reason a blind turn cannot silently happen.
    func testAttachingWithoutASessionIsRefused() async throws {
        let engine = try makeEngine(transcriber: HoldingTranscriber())
        let attached = await engine.attachTurnDetector(VoiceActivityDetector())
        XCTAssertFalse(attached, "there is no session to host a detector")
    }
}
