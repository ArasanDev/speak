// SpeakTests/SpeakEngineLanguageTests.swift
//
// Proves the H1 multi-language seam: `SpeakEngine.newSession()` reads
// `settings.language` at call time, NOT from a locale baked into the engine
// at init. Changing `settings.language` between sessions is the only step
// needed to switch languages — no engine restart required. [decision H1]
//
// SCOPE:
//   These run WITHOUT the live speech model or any hardware — all components
//   are headless mocks. `CaptureSession.locale` is `public nonisolated let`
//   and is directly readable after `newSession()` returns, giving a clean
//   synchronous observation without touching the transcriber stream.
//
// BEHAVIOR-NEUTRALITY CHECK:
//   `SettingsStore` defaults `language` to `en-US` (registered in
//   `SettingsStore.init`). A fresh test-isolated store therefore behaves
//   identically to the pre-H1 hardcoded `en-US` default. The test below
//   confirms that an explicitly set non-en locale flows through, which
//   proves the seam is live without breaking the default.

import XCTest
@testable import SpeakCore

final class SpeakEngineLanguageTests: XCTestCase {

    // MARK: - Minimal mocks

    /// A no-op transcriber — the test does not exercise the transcription path,
    /// only the locale that `newSession()` passes to `CaptureSession`.
    private struct NullTranscriber: Transcribing, @unchecked Sendable {
        let id = "null-stt"

        func startStream(locale: Locale) -> AsyncThrowingStream<TranscriptChunk, Error> {
            AsyncThrowingStream { continuation in
                continuation.finish()
            }
        }

        func stop() async {}
    }

    /// A no-op history store so the engine can be assembled headlessly.
    private final class NullHistory: HistoryStoring, @unchecked Sendable {
        func save(_ entry: HistoryEntry) async throws {}
        func recent(limit: Int) async throws -> [HistoryEntry] { [] }
        func search(_ substring: String) async throws -> [HistoryEntry] { [] }
        func clear() async throws {}
        func export() async throws -> String { "[]" }
    }

    // MARK: - Helper

    /// Build a headless engine wired to a test-isolated `SettingsStore`.
    /// Never touches `.standard` — always tears down its named suite.
    private func makeEngine(settings: SettingsStore) -> SpeakEngine {
        SpeakEngine(
            transcriber: NullTranscriber(),
            cleaner: nil,
            inserter: nil,
            history: NullHistory(),
            settings: settings
        )
    }

    private func makeSettings() throws -> SettingsStore {
        let suiteName = "SpeakEngineLanguageTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(
            UserDefaults(suiteName: suiteName),
            "UserDefaults(suiteName:) returned nil for '\(suiteName)'"
        )
        addTeardownBlock { defaults.removePersistentDomain(forName: suiteName) }
        return SettingsStore(defaults: defaults)
    }

    // MARK: - Tests

    /// `SettingsStore.language` defaults to `en-US`. A fresh engine with an
    /// unmodified settings store must produce sessions with the `en-US` locale.
    /// This is the behavior-neutrality proof: H1 preserves the prior default.
    func testDefaultLocaleIsEnUS() async throws {
        let settings = try makeSettings()
        let engine = makeEngine(settings: settings)

        let session = await engine.newSession()
        XCTAssertEqual(
            session.locale.identifier, "en-US",
            "Default settings.language must yield an en-US session locale."
        )
    }

    /// Changing `settings.language` before `newSession()` is called must
    /// produce a session with the new locale — no engine restart required.
    /// This is the load-bearing assertion for H1: the seam is live.
    func testNewSessionHonorsChangedLanguage() async throws {
        let settings = try makeSettings()
        let engine = makeEngine(settings: settings)

        // Mutate the language setting AFTER the engine is constructed.
        settings.language = Locale(identifier: "de-DE")

        let session = await engine.newSession()
        XCTAssertEqual(
            session.locale.identifier, "de-DE",
            "newSession() must read settings.language at call time; " +
            "a changed locale must flow through without restarting the engine."
        )
    }

    /// Changing `settings.language` between two consecutive sessions must yield
    /// different locales for each session, confirming per-call read semantics.
    func testLocaleFlowsPerCall() async throws {
        let settings = try makeSettings()
        let engine = makeEngine(settings: settings)

        settings.language = Locale(identifier: "fr-FR")
        let sessionFR = await engine.newSession()

        settings.language = Locale(identifier: "ja-JP")
        let sessionJA = await engine.newSession()

        XCTAssertEqual(sessionFR.locale.identifier, "fr-FR",
            "First session must carry the fr-FR locale.")
        XCTAssertEqual(sessionJA.locale.identifier, "ja-JP",
            "Second session must carry the ja-JP locale — same engine, new call.")
    }
}
