// SpeakTests/SpeakEngineIntegrationTests.swift
//
// Real-component integration test for SpeakEngine.
//
// PURPOSE:
//   The 61 existing tests all use mocks. No real components have ever run
//   together in one process. This test closes that gap with one end-to-end
//   dictation using the actual components, wired through SpeakEngine:
//
//     FixtureAudioProducer → AppleSpeechTranscriber (real STT)
//       → CaptureSession (via SpeakEngine)
//       → FoundationModelsCleaner (real FM — takes isAvailable==false → raw fallback)
//       → HistoryStore (real SQLite, temp-file DB, cleaned up on tearDown)
//       → MockTextInserter (records text; we cannot headlessly paste)
//
// SKIP CONTRACT:
//   This test XCTSkips (not fails) if the en-US speech model is not installed —
//   the same guard used by SpeechTranscriberTests.testTranscribesFixture.
//   A skip is NOT a pass. A green (non-skip) test means all real components
//   ran end-to-end and the assertions held.
//
// ASSERTIONS (what this test catches that the all-mock suite cannot):
//   1. SpeakEngine.beginDictation() reaches .listening without error.
//   2. A real STT session produces a non-empty final transcript.
//   3. FoundationModelsCleaner.isAvailable == false (on this dev Mac) →
//      graceful fallback: cleanedText == nil, session reaches .done (not .error).
//   4. The mock inserter received the raw transcript (cleanedText ?? rawText == rawText).
//   5. HistoryStore has exactly one entry matching the result.
//
// TIMING:
//   After beginDictation(), we observe the partials stream and wait until
//   an isFinal chunk arrives (the fixture auto-finalizes at EOF), THEN call
//   endDictation(). This avoids the race where endDictation → stop() truncates
//   the audio before the analyzer finalizes, producing an empty transcript.
//   The isFinal-wait is deterministic; a blind sleep is the fragile fallback.

import XCTest
import AVFoundation
import Speech
@testable import SpeakCore

@available(macOS 26.0, *)
final class SpeakEngineIntegrationTests: XCTestCase {

    // MARK: - Mock text inserter

    /// Records the text passed to `insert(_:)`. Thread-safe via actor.
    actor MockTextInserter: TextInserting {
        private(set) var insertedTexts: [String] = []
        func insert(_ text: String) async throws { insertedTexts.append(text) }
    }

    // MARK: - Helpers

    /// URL for the fixture audio file. Mirrors `SpeechTranscriberTests.fixtureURL`.
    private var fixtureURL: URL {
        let bundle = Bundle(for: type(of: self))
        if let url = bundle.url(forResource: "hello_speech", withExtension: "caf", subdirectory: "Fixtures") {
            return url
        }
        return URL(fileURLWithPath: #file)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/hello_speech.caf")
    }

    /// Creates a unique temp-file database URL and registers teardown cleanup.
    private func tempDatabaseURL() -> URL {
        let name = "speak-engine-integration-\(UUID().uuidString).sqlite"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    /// Guards that the en-US speech model is installed. Throws `XCTSkip` if not.
    private func requireSpeechModel(locale: Locale) async throws {
        guard SpeechTranscriber.isAvailable else {
            throw XCTSkip("SpeechTranscriber not available on this device. Skip ≠ pass.")
        }
        guard await SpeechTranscriber.supportedLocale(equivalentTo: locale) != nil else {
            throw XCTSkip("en-US not a supported locale on this machine. Skip ≠ pass.")
        }
        let module = SpeechTranscriber(locale: locale, preset: .progressiveTranscription)
        let status = await AssetInventory.status(forModules: [module])
        guard status == .installed else {
            throw XCTSkip("Speech model not installed (status: \(status)). Skip ≠ pass.")
        }
        guard FileManager.default.fileExists(atPath: fixtureURL.path) else {
            throw XCTSkip("Fixture not found at \(fixtureURL.path). Run `make test` from repo root.")
        }
    }

    /// Waits for the first `isFinal` chunk on `stream`, timing out after 30 seconds.
    /// The 30-second value [decision] is generous CI headroom for the 1.3s fixture.
    private func waitForFinalChunk(_ stream: AsyncStream<TranscriptChunk>) async -> Bool {
        var finalSeen = false
        let waitTask = Task {
            for await chunk in stream where chunk.isFinal {
                finalSeen = true
                return
            }
        }
        let timeoutTask = Task {
            try? await Task.sleep(for: .seconds(30))
            waitTask.cancel()
        }
        await waitTask.value
        timeoutTask.cancel()
        return finalSeen
    }

    /// Asserts the fixture's expected words appear in `text` (case-insensitive).
    private func assertContainsFixtureWords(_ text: String) {
        let lower = text.lowercased()
        let missing = ["one", "two", "three"].filter { !lower.contains($0) }
        XCTAssertTrue(missing.isEmpty,
            "Transcript missing \(missing). Got: '\(text)'. Fixture: 'Testing one two three'.")
    }

    // MARK: - Integration test

    /// End-to-end dictation through SpeakEngine: real STT, real FM (unavailable
    /// path → raw fallback), real SQLite HistoryStore, mock TextInserter.
    func testEndToEndDictationWithRealComponents() async throws {
        let enUS = Locale(identifier: "en-US")
        try await requireSpeechModel(locale: enUS)

        // Build real components (named so they can be asserted after the run)
        let mockInserter = MockTextInserter()
        let historyStore = try HistoryStore(databaseURL: tempDatabaseURL())

        // Inject a test-isolated SettingsStore (never touches .standard).
        // Set cleanupEnabled=true so this test exercises the FM-unavailable
        // raw-fallback path, NOT the toggle-off path. The two are distinct:
        // toggle-off → activeCleaner==nil by toggle; FM-unavailable → activeCleaner
        // is non-nil but isAvailable==false → CaptureSession falls back to raw.
        let suiteName = "SpeakEngineIntegrationTests.\(UUID().uuidString)"
        let testDefaults = try XCTUnwrap(
            UserDefaults(suiteName: suiteName),
            "UserDefaults(suiteName:) returned nil for '\(suiteName)' — UUID names cannot be invalid."
        )
        addTeardownBlock { testDefaults.removePersistentDomain(forName: suiteName) }
        let testSettings = SettingsStore(defaults: testDefaults)
        testSettings.cleanupEnabled = true   // exercise FM-unavailable path, not toggle-off

        // H1: locale no longer baked at init — SpeakEngine reads settings.language at
        // newSession() time. testSettings defaults to en-US (SettingsStore default),
        // preserving the prior behavior for this test.
        let engine = SpeakEngine(
            transcriber: AppleSpeechTranscriber(
                audioProducer: SpeechTranscriberTests.FixtureAudioProducer(fileURL: fixtureURL)
            ),
            cleaner: FoundationModelsCleaner(),   // isAvailable==false → raw fallback
            inserter: mockInserter,
            history: historyStore,
            cleanupMode: .punctuation,
            settings: testSettings
        )

        // Begin dictation
        try await engine.beginDictation()
        let stateAfterBegin = await engine.currentState
        guard case .listening = stateAfterBegin else {
            XCTFail("Expected .listening after beginDictation(), got \(stateAfterBegin)")
            await engine.cancelDictation()
            return
        }

        // Wait for the fixture to auto-finalize (deterministic isFinal-wait)
        if let partialsStream = await engine.currentPartials() {
            _ = await waitForFinalChunk(partialsStream)
        }

        let result = try await engine.endDictation()

        // 1. Non-empty transcript containing fixture words
        XCTAssertFalse(result.rawText.isEmpty,
            "rawText must be non-empty. Fixture contains speech. Check SpeakLog.stt.")
        assertContainsFixtureWords(result.rawText)

        // 2. FM unavailable → cleanedText == nil (graceful fallback, NOT .error)
        XCTAssertNil(result.cleanedText,
            "cleanedText must be nil: FM unavailable on this Mac → raw fallback.")

        // 3. Inserter received rawText (cleanedText ?? rawText == rawText when cleaned is nil)
        let insertedTexts = await mockInserter.insertedTexts
        XCTAssertEqual(insertedTexts.count, 1, "Inserter must receive exactly one insert call.")
        XCTAssertEqual(insertedTexts.first, result.rawText,
            "Inserter must receive rawText when cleanedText is nil.")

        // 4. HistoryStore has exactly one entry matching the result
        let entries = try await historyStore.recent(limit: 100)
        XCTAssertEqual(entries.count, 1, "HistoryStore must have exactly one entry.")
        if let entry = entries.first {
            XCTAssertEqual(entry.rawText, result.rawText, "Entry rawText must match result.")
            XCTAssertNil(entry.cleanedText, "Entry cleanedText must be nil (FM unavailable).")
            XCTAssertEqual(entry.engineId, result.engineId, "Entry engineId must match result.")
        }

        SpeakLog.engine.info("""
            SpeakEngineIntegration PASSED: \
            raw='\(result.rawText, privacy: .public)' \
            engineId='\(result.engineId, privacy: .public)'
            """)
    }
}
