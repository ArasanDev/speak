// SpeakTests/ProfileOverrideTests.swift
//
// PE-3c-V: Unit tests for the per-dictation profile/category override path.
// The live panel allows the user to reshape the current dictation's output by
// tapping destination (profile + category) or Raw chips AFTER the session starts
// but BEFORE stop() — the override is applied at stop, before cleanup runs.
//
// SCOPE:
//   - CaptureSession.setOverrideCleanupMode() and forceRawForThisSession() set
//     the internal state that runCleanup() consults.
//   - CaptureSession.effectiveCleanupMode returns the override if set, else base.
//   - CaptureSession.runCleanup() uses the effective mode and respects forcedRaw.
//   - SpeakEngine.applyProfileOverride() sets the session's effective cleanup mode
//     to the chosen profile + category (or no-ops for three documented cases).
//   - SpeakEngine.applyRawOverride() sets the session's forcedRaw flag.
//   - ZERO-REGRESSION: the default no-tap path (no override applied) leaves the
//     effective mode unchanged from the session's init-time mode.
//
// STRATEGY:
//   - Mock Transcribing and LLMCleaning to test orchestration without real APIs.
//   - For profile override: create a session with a base mode, apply an override,
//     assert effectiveCleanupMode reflects the override.
//   - For raw override: apply forceRawForThisSession() and drive to stop; assert
//     runCleanup returns nil (raw passthrough) even with a cleaner wired.
//   - For no-op cases: apply overrides that should be ignored and assert no effect.
//   - ZERO-REGRESSION test: create a session, do NOT apply any override, assert
//     effectiveCleanupMode stays at the base mode.

@testable import SpeakCore
import XCTest

final class ProfileOverrideTests: XCTestCase {

    // MARK: - Mocks (reused from CaptureSessionTests patterns)

    /// A simple mock STT that emits one final chunk then finishes.
    private struct SimpleTranscriber: Transcribing, @unchecked Sendable {
        let id: String = "mock-stt-override"
        let finalText: String

        func startStream(locale: Locale) -> AsyncThrowingStream<TranscriptChunk, Error> {
            AsyncThrowingStream { continuation in
                continuation.yield(TranscriptChunk(text: finalText, isFinal: true, timestamp: Date()))
                continuation.finish()
            }
        }

        func stop() async {}
    }

    /// Actor that records cleaner invocations (used by RecordingCleaner).
    private actor CleanerCallRecorder {
        private(set) var calls: [(text: String, mode: CleanupMode)] = []

        func record(text: String, mode: CleanupMode) {
            calls.append((text, mode))
        }

        func count() -> Int { calls.count }
        func lastMode() -> CleanupMode? { calls.last?.mode }
    }

    /// A mock cleaner that records every clean() call and returns a fixed result.
    private struct RecordingCleaner: LLMCleaning {
        let id: String = "mock-cleaner-override"
        var isAvailable: Bool { get async { true } }

        private let resultValue: String
        private let recorder: CleanerCallRecorder

        init(result: String = "cleaned text", recorder: CleanerCallRecorder) {
            resultValue = result
            self.recorder = recorder
        }

        func clean(_ text: String, mode: CleanupMode) async throws -> String {
            await recorder.record(text: text, mode: mode)
            return resultValue
        }
    }

    /// A no-op history store so the engine can run headless.
    private final class NullHistory: HistoryStoring, @unchecked Sendable {
        func save(_ entry: HistoryEntry) async throws {}
        func recent(limit: Int) async throws -> [HistoryEntry] { [] }
        func search(_ substring: String) async throws -> [HistoryEntry] { [] }
        func clear() async throws {}
        func export() async throws -> String { "[]" }
    }

    // MARK: - Helpers

    private func makeSettings(suiteSuffix: String = UUID().uuidString) throws -> SettingsStore {
        let suiteName = "ProfileOverrideTests.\(suiteSuffix)"
        let defaults = try XCTUnwrap(
            UserDefaults(suiteName: suiteName),
            "UserDefaults(suiteName:) returned nil"
        )
        addTeardownBlock { defaults.removePersistentDomain(forName: suiteName) }
        return SettingsStore(defaults: defaults)
    }

    /// Create a test profile with a specific model and name.
    private func testProfile(name: String, model: ModelChoice = .foundationModels) -> Profile {
        Profile(
            id: UUID(),
            name: name,
            icon: "text.quote",
            isBuiltIn: false,
            systemPrompt: "Test prompt",
            model: model
        )
    }

    // MARK: - Tests: CaptureSession override state

    /// Test: setOverrideCleanupMode() updates the override.
    func testCaptureSession_setOverrideCleanupMode_setsTheMode() async throws {
        let baseMode = CleanupMode.fillersOnly
        let overrideMode = CleanupMode.punctuation

        let session = CaptureSession(
            transcriber: SimpleTranscriber(finalText: "hello"),
            cleaner: nil,
            locale: .current,
            cleanupMode: baseMode
        )

        // Before override: effectiveCleanupMode should be the base mode.
        var effective = await session.effectiveCleanupMode
        XCTAssertTrue(self.isSameMode(effective, baseMode), "Before override, should be base mode")

        // Apply override.
        await session.setOverrideCleanupMode(overrideMode)

        // After override: effectiveCleanupMode should be the override.
        effective = await session.effectiveCleanupMode
        XCTAssertTrue(self.isSameMode(effective, overrideMode), "After override, should be override mode")
    }

    // MARK: - Helper for CleanupMode comparison (since CleanupMode is not Equatable)

    private func isSameMode(_ a: CleanupMode, _ b: CleanupMode) -> Bool {
        switch (a, b) {
        case (.fillersOnly, .fillersOnly): return true
        case (.punctuation, .punctuation): return true
        case (.codeAware, .codeAware): return true
        case (.toneAdjust, .toneAdjust): return true
        case (.translate(let l1), .translate(let l2)): return l1.identifier == l2.identifier
        case (.styled(let s1, let l1, _), .styled(let s2, let l2, _)): return s1 == s2 && l1 == l2
        case (.command(let i1), .command(let i2)): return i1 == i2
        case (.profile(let p1, let l1, let c1, _), .profile(let p2, let l2, let c2, _)):
            return p1.id == p2.id && l1 == l2 && c1 == c2
        default: return false
        }
    }

    /// Test: forcedRaw == true → runCleanup returns nil (raw passthrough).
    /// This is the core contract: Raw override means no AI, even with a cleaner wired.
    func testCaptureSession_forcedRaw_makesRunCleanupReturnNil() async throws {
        let recorder = CleanerCallRecorder()
        let cleaner = RecordingCleaner(result: "cleaned", recorder: recorder)
        let session = CaptureSession(
            transcriber: SimpleTranscriber(finalText: "raw text"),
            cleaner: cleaner,
            locale: .current,
            cleanupMode: .punctuation
        )

        // Force raw for this session.
        await session.forceRawForThisSession()

        // Run cleanup with forcedRaw == true.
        let (cleanedText, engineId, cleanupSeconds) = await session.runCleanup(rawText: "raw text")

        // Assert: cleanedText is nil (raw passthrough).
        XCTAssertNil(
            cleanedText,
            "forcedRaw == true must return nil, bypassing the cleaner entirely."
        )

        // Assert: cleaner was NOT called (0 calls).
        let callCount = await recorder.count()
        XCTAssertEqual(
            callCount, 0,
            "forcedRaw == true must skip the cleaner; clean() should not be called."
        )

        // Assert: engineId is the STT id only (no "+cleaner" suffix).
        XCTAssertEqual(
            engineId, "mock-stt-override",
            "engineId should be the STT id only when raw is forced."
        )

        // Assert: cleanupSeconds == 0.0 (sentinel: cleanup did not run).
        XCTAssertEqual(
            cleanupSeconds, 0.0,
            "cleanupSeconds must be 0.0 (sentinel) when cleanup is skipped via forcedRaw."
        )
    }

    /// Test: override mode is used by runCleanup.
    /// When an override is set, runCleanup reads effectiveCleanupMode (override ?? base).
    func testCaptureSession_overrideMode_isUsedByRunCleanup() async throws {
        let baseMode = CleanupMode.fillersOnly
        let overrideMode = CleanupMode.codeAware

        let recorder = CleanerCallRecorder()
        let cleaner = RecordingCleaner(result: "cleaned", recorder: recorder)
        let session = CaptureSession(
            transcriber: SimpleTranscriber(finalText: "raw text"),
            cleaner: cleaner,
            locale: .current,
            cleanupMode: baseMode
        )

        // Apply override.
        await session.setOverrideCleanupMode(overrideMode)

        // Run cleanup.
        let (cleanedText, _, _) = await session.runCleanup(rawText: "raw text")

        // Assert: cleanup ran (cleanedText is not nil).
        XCTAssertNotNil(cleanedText, "Cleanup should have run with the override mode.")

        // Assert: the cleaner was called with the override mode, not the base mode.
        let lastMode = await recorder.lastMode()
        XCTAssertTrue(
            self.isSameMode(lastMode ?? .fillersOnly, overrideMode),
            "runCleanup should use the override mode, not the base mode."
        )
    }

    // MARK: - Tests: SpeakEngine.applyProfileOverride

    /// Test: applyProfileOverride sets the session's override to the chosen profile + category.
    func testSpeakEngine_applyProfileOverride_setsTheOverride() async throws {
        let settings = try makeSettings()
        settings.cleanupEnabled = true
        settings.cleanupLevel = .high

        let profile = testProfile(name: "TestProfile")
        let category = AgentCategory.ask

        let recorder = CleanerCallRecorder()
        let engine = SpeakEngine(
            transcriber: SimpleTranscriber(finalText: "hello"),
            cleaner: RecordingCleaner(recorder: recorder),
            history: NullHistory(),
            settings: settings
        )

        // Start a session so there is a currentSession to override.
        let session = await engine.newSession()
        try await session.start()

        // Apply the profile override.
        await engine.applyProfileOverride(profile, category: category)

        // Assert: the session's effectiveCleanupMode is now the override.
        let effective = await session.effectiveCleanupMode
        if case .profile(let p, let level, let c, _) = effective {
            XCTAssertEqual(p.name, "TestProfile", "Profile name should match the override.")
            XCTAssertEqual(level, .high, "Cleanup level should be from settings.")
            XCTAssertEqual(c, .ask, "Category should match the override.")
        } else {
            XCTFail("effectiveCleanupMode should be .profile(...) after override.")
        }
    }

    /// Test: applyProfileOverride is a no-op when cleanup is disabled.
    func testSpeakEngine_applyProfileOverride_noop_cleanupDisabled() async throws {
        let settings = try makeSettings()
        settings.cleanupEnabled = false
        settings.cleanupLevel = .high

        let overrideProfile = testProfile(name: "Override")

        let recorder = CleanerCallRecorder()
        let engine = SpeakEngine(
            transcriber: SimpleTranscriber(finalText: "hello"),
            cleaner: RecordingCleaner(recorder: recorder),
            history: NullHistory(),
            settings: settings
        )

        let session = await engine.newSession()
        let baseMode = await session.effectiveCleanupMode
        try await session.start()

        // Attempt to apply override with cleanup disabled.
        await engine.applyProfileOverride(overrideProfile, category: .fix)

        // Assert: the override was ignored; effectiveCleanupMode remains unchanged.
        let effective = await session.effectiveCleanupMode
        XCTAssertTrue(
            self.isSameMode(effective, baseMode),
            "applyProfileOverride should be a no-op when cleanupEnabled == false."
        )
    }

    /// Test: applyProfileOverride is a no-op when cleanupLevel == .none.
    func testSpeakEngine_applyProfileOverride_noop_levelNone() async throws {
        let settings = try makeSettings()
        settings.cleanupEnabled = true
        settings.cleanupLevel = .none

        let overrideProfile = testProfile(name: "Override")

        let recorder = CleanerCallRecorder()
        let engine = SpeakEngine(
            transcriber: SimpleTranscriber(finalText: "hello"),
            cleaner: RecordingCleaner(recorder: recorder),
            history: NullHistory(),
            settings: settings
        )

        let session = await engine.newSession()
        let baseMode = await session.effectiveCleanupMode
        try await session.start()

        // Attempt to apply override with level == .none.
        await engine.applyProfileOverride(overrideProfile, category: .fix)

        // Assert: the override was ignored.
        let effective = await session.effectiveCleanupMode
        XCTAssertTrue(
            self.isSameMode(effective, baseMode),
            "applyProfileOverride should be a no-op when cleanupLevel == .none."
        )
    }

    /// Test: applyProfileOverride is a no-op when the profile model is .raw.
    func testSpeakEngine_applyProfileOverride_noop_profileModelRaw() async throws {
        let settings = try makeSettings()
        settings.cleanupEnabled = true
        settings.cleanupLevel = .high

        let rawProfile = testProfile(name: "Raw", model: .raw)

        let recorder = CleanerCallRecorder()
        let engine = SpeakEngine(
            transcriber: SimpleTranscriber(finalText: "hello"),
            cleaner: RecordingCleaner(recorder: recorder),
            history: NullHistory(),
            settings: settings
        )

        let session = await engine.newSession()
        let baseMode = await session.effectiveCleanupMode
        try await session.start()

        // Attempt to apply override with model == .raw.
        await engine.applyProfileOverride(rawProfile, category: .fix)

        // Assert: the override was ignored.
        let effective = await session.effectiveCleanupMode
        XCTAssertTrue(
            self.isSameMode(effective, baseMode),
            "applyProfileOverride should be a no-op when profile.model == .raw."
        )
    }

    /// Test: applyProfileOverride is a no-op when no session is active.
    func testSpeakEngine_applyProfileOverride_noop_noSession() async throws {
        let settings = try makeSettings()
        settings.cleanupEnabled = true
        settings.cleanupLevel = .high

        let recorder = CleanerCallRecorder()
        let engine = SpeakEngine(
            transcriber: SimpleTranscriber(finalText: "hello"),
            cleaner: RecordingCleaner(recorder: recorder),
            history: NullHistory(),
            settings: settings
        )

        // Do NOT start a session; currentSession is nil.
        let profile = testProfile(name: "Override")
        await engine.applyProfileOverride(profile, category: .fix)

        // Assert: no crash; the engine handles the missing session gracefully.
    }

    // MARK: - Tests: SpeakEngine.applyRawOverride

    /// Test: applyRawOverride sets the session's forcedRaw flag.
    func testSpeakEngine_applyRawOverride_setsForcedRaw() async throws {
        let settings = try makeSettings()

        let recorder = CleanerCallRecorder()
        let engine = SpeakEngine(
            transcriber: SimpleTranscriber(finalText: "hello"),
            cleaner: RecordingCleaner(recorder: recorder),
            history: NullHistory(),
            settings: settings
        )

        let session = await engine.newSession()
        try await session.start()

        // Apply raw override.
        await engine.applyRawOverride()

        // Assert: the session's forcedRaw is now true (observable via runCleanup returning nil).
        let (cleanedText, _, _) = await session.runCleanup(rawText: "raw text")
        XCTAssertNil(
            cleanedText,
            "applyRawOverride should cause runCleanup to return nil (raw passthrough)."
        )
    }

    /// Test: applyRawOverride is a no-op when no session is active.
    func testSpeakEngine_applyRawOverride_noop_noSession() async throws {
        let settings = try makeSettings()

        let recorder = CleanerCallRecorder()
        let engine = SpeakEngine(
            transcriber: SimpleTranscriber(finalText: "hello"),
            cleaner: RecordingCleaner(recorder: recorder),
            history: NullHistory(),
            settings: settings
        )

        // Do NOT start a session.
        await engine.applyRawOverride()

        // Assert: no crash.
    }

    // MARK: - Tests: ZERO-REGRESSION default path

    /// CRITICAL: The default no-tap path (no override applied) leaves the effective
    /// mode at the session's base mode. This is the fence against regression.
    func testZeroRegression_defaultNoTapPath_keepsBaseMode() async throws {
        let settings = try makeSettings()
        settings.cleanupEnabled = true
        settings.cleanupLevel = .medium

        let recorder = CleanerCallRecorder()
        let engine = SpeakEngine(
            transcriber: SimpleTranscriber(finalText: "hello"),
            cleaner: RecordingCleaner(result: "cleaned", recorder: recorder),
            history: NullHistory(),
            settings: settings
        )

        let session = await engine.newSession()
        let baseMode = await session.effectiveCleanupMode
        try await session.start()

        // DO NOT apply any override. The user did not tap any chip.

        // Assert: effectiveCleanupMode is still the base mode.
        let effective = await session.effectiveCleanupMode
        XCTAssertTrue(
            self.isSameMode(effective, baseMode),
            "Without any override, effectiveCleanupMode must remain at the base mode. " +
            "This is the critical regression fence: a broken override mechanism must not " +
            "alter the default behavior."
        )

        // Also verify: cleanup runs with the base mode.
        let (cleanedText, engineId, _) = await session.runCleanup(rawText: "raw text")
        XCTAssertNotNil(
            cleanedText,
            "Cleanup should have run with the base mode."
        )
        XCTAssertEqual(
            engineId, "mock-stt-override+mock-cleaner-override",
            "engineId should contain both STT and cleaner ids (cleanup ran)."
        )
    }

    /// ZERO-REGRESSION: fillersOnly (a simple base mode) is unaffected when no override.
    func testZeroRegression_fillersOnlyDefault_unaffected() async throws {
        let session = CaptureSession(
            transcriber: SimpleTranscriber(finalText: "hello"),
            cleaner: nil,
            locale: .current,
            cleanupMode: .fillersOnly
        )

        // DO NOT apply any override.
        let effective = await session.effectiveCleanupMode
        XCTAssertTrue(
            self.isSameMode(effective, .fillersOnly),
            "Base mode (.fillersOnly) must not be altered by the override mechanism " +
            "when no override is set."
        )
    }
}
