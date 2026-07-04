// SpeakTests/SpeakEngineCleanupLevelTests.swift
//
// Proves the W4.1 guarantee: CleanupLevel.none causes SpeakEngine.newSession()
// to pass nil for the cleaner, so CaptureSession.runCleanup() short-circuits and
// cleanedText == nil — the LLM is never invoked, even with cleanupEnabled == true.
//
// This is the behavioral lock for the headline W4.1 feature: "None = no model call,
// raw passthrough." The guarantee is procedural (enforced in newSession(), not the
// type system), so without this test a future refactor of newSession() could
// silently break it with all other gates still green. [decision W4.1]
//
// TEST STRATEGY:
//   A SpyCleaner is wired into a SpeakEngine. Its clean() fails the test if called.
//   A MockTranscriber emits one final chunk ("hello world") so the session can
//   be driven start-to-stop without real audio. cleanupEnabled is explicitly true
//   so the only reason cleanup is skipped is cleanupLevel == .none.
//
//   The complementary positive test confirms that changing the level to a non-none
//   value (while keeping the spy available) causes clean() to be called — proving
//   the spy mechanism is sound.

@testable import SpeakCore
import XCTest

final class SpeakEngineCleanupLevelTests: XCTestCase {

    // MARK: - Mocks

    /// Emits one final chunk then finishes. Enough for a start-to-stop session.
    private struct ScriptedTranscriber: Transcribing, @unchecked Sendable {
        let id = "scripted-stt"
        let finalText: String

        func startStream(locale: Locale) -> AsyncThrowingStream<TranscriptChunk, Error> {
            AsyncThrowingStream { continuation in
                continuation.yield(TranscriptChunk(text: finalText, isFinal: true, timestamp: Date()))
                continuation.finish()
            }
        }

        func stop() async {}
    }

    /// A cleaner that fails the test if clean() is invoked. Used to prove that
    /// cleanupLevel == .none skips the LLM entirely — not just a different prompt.
    private final class SpyCleaner: LLMCleaning, @unchecked Sendable {
        let id = "spy-cleaner"
        var isAvailable: Bool { get async { true } }

        var cleanWasCalled = false

        func clean(_ text: String, mode: CleanupMode) async throws -> String {
            cleanWasCalled = true
            // Return something so the session does not error even if invoked.
            return text
        }
    }

    /// No-op history store so the engine can be assembled headlessly.
    private final class NullHistory: HistoryStoring, @unchecked Sendable {
        func save(_ entry: HistoryEntry) async throws {}
        func recent(limit: Int) async throws -> [HistoryEntry] { [] }
        func search(_ substring: String) async throws -> [HistoryEntry] { [] }
        func clear() async throws {}
        func export() async throws -> String { "[]" }
    }

    // MARK: - Helpers

    private func makeSettings(suiteSuffix: String = UUID().uuidString) throws -> SettingsStore {
        let suiteName = "SpeakEngineCleanupLevelTests.\(suiteSuffix)"
        let defaults = try XCTUnwrap(
            UserDefaults(suiteName: suiteName),
            "UserDefaults(suiteName:) returned nil for '\(suiteName)'"
        )
        addTeardownBlock { defaults.removePersistentDomain(forName: suiteName) }
        return SettingsStore(defaults: defaults)
    }

    private func makeEngine(spy: SpyCleaner, settings: SettingsStore) -> SpeakEngine {
        SpeakEngine(
            transcriber: ScriptedTranscriber(finalText: "hello world"),
            cleaner: spy,
            inserter: nil,
            history: NullHistory(),
            settings: settings
        )
    }

    // MARK: - Tests

    /// CORE W4.1 CONTRACT: cleanupLevel == .none must skip the cleaner entirely.
    ///
    /// Even though:
    ///   - a SpyCleaner is injected and reports isAvailable == true
    ///   - cleanupEnabled == true (default)
    ///
    /// ... the LLM must NOT be called when cleanupLevel is .none.
    /// The result's cleanedText must be nil (raw passthrough).
    func testCleanupLevel_none_skipsCleanerEntirely() async throws {
        let settings = try makeSettings()
        settings.cleanupEnabled = true          // LLM is enabled — level==.none is the only gate
        settings.cleanupLevel = CleanupLevel.none  // W4.1: explicit fully-qualified to avoid Optional.none ambiguity

        let spy = SpyCleaner()
        let engine = makeEngine(spy: spy, settings: settings)

        let session = await engine.newSession()
        try await session.start()
        let result = try await session.stop()

        XCTAssertFalse(
            spy.cleanWasCalled,
            "SpyCleaner.clean() must NOT be called when cleanupLevel == .none. " +
            "The LLM skip is enforced in SpeakEngine.newSession() by passing activeCleaner=nil " +
            "when level is .none. [decision W4.1]"
        )
        XCTAssertNil(
            result.cleanedText,
            "cleanedText must be nil for cleanupLevel == .none (raw passthrough). " +
            "The result should deliver the raw transcript unchanged."
        )
        XCTAssertEqual(
            result.rawText, "hello world",
            "rawText must carry the transcribed text unchanged."
        )
    }

    /// Complementary positive test: cleanupLevel != .none causes the cleaner to be
    /// called. This confirms the SpyCleaner mechanism is sound — the test above
    /// is not passing vacuously because of a bug in the spy.
    func testCleanupLevel_medium_invokesCleanerWhenEnabled() async throws {
        let settings = try makeSettings()
        settings.cleanupEnabled = true
        settings.cleanupLevel = .medium  // non-none level

        let spy = SpyCleaner()
        let engine = makeEngine(spy: spy, settings: settings)

        let session = await engine.newSession()
        try await session.start()
        _ = try await session.stop()

        XCTAssertTrue(
            spy.cleanWasCalled,
            "SpyCleaner.clean() MUST be called when cleanupLevel == .medium and cleanupEnabled == true. " +
            "If this fails, the spy itself is broken — re-examine the test harness."
        )
    }

    /// cleanupEnabled == false must also skip the cleaner, regardless of level.
    /// This is the legacy boolean-toggle path (pre-W4.1 behavior preserved).
    func testCleanupEnabled_false_skipsCleanerRegardlessOfLevel() async throws {
        let settings = try makeSettings()
        settings.cleanupEnabled = false
        settings.cleanupLevel = .high   // level is non-none, but toggle is off

        let spy = SpyCleaner()
        let engine = makeEngine(spy: spy, settings: settings)

        let session = await engine.newSession()
        try await session.start()
        let result = try await session.stop()

        XCTAssertFalse(
            spy.cleanWasCalled,
            "cleanupEnabled == false must skip the cleaner regardless of cleanupLevel."
        )
        XCTAssertNil(
            result.cleanedText,
            "cleanedText must be nil when cleanupEnabled == false."
        )
    }
}
