// SpeakTests/SettingsStoreTests.swift
//
// Unit tests for SettingsStore, defaultTranscriber(for:), and defaultCleaner(for:).
//
// ISOLATION CONTRACT:
//   Every test creates its own named UserDefaults suite and removes it on teardown.
//   `.standard` is NEVER touched. Tests can run in any order without interference.
//
// COVERAGE:
//   - Every property persists and round-trips across a fresh SettingsStore on the
//     same injected defaults.
//   - Enum encodings round-trip, including CleanupEngine.ollama(model:) associated value.
//   - defaultCleaner(for:) returns nil when cleanupEnabled == false.
//   - defaultCleaner(for:) returns a FoundationModelsCleaner when cleanupEnabled == true.
//   - defaultTranscriber(for:) returns an AppleSpeechTranscriber for .appleSpeech.
//   - v0.1/v1 engine stubs fall back to v0 defaults without crashing.
//
// HONESTY BOUNDARY:
//   These tests cover the persistence layer and factory logic — [verified] by the
//   test suite. The Settings window UI rendering is [deferred — human verification].

import XCTest
@testable import SpeakCore

@available(macOS 26.0, *)
final class SettingsStoreTests: XCTestCase {

    // MARK: - Helpers

    /// Creates a named UserDefaults suite unique to each test run, and registers
    /// a teardown block to remove it so no state leaks between tests.
    ///
    /// `throws` so callers propagate via `try` — avoids force-unwrap in test code.
    private func makeIsolatedDefaults() throws -> UserDefaults {
        let name = "SettingsStoreTests.\(UUID().uuidString)"
        let ud = try XCTUnwrap(
            UserDefaults(suiteName: name),
            "UserDefaults(suiteName:) returned nil — this should be impossible for a UUID-based name."
        )
        addTeardownBlock {
            ud.removePersistentDomain(forName: name)
        }
        return ud
    }

    /// Convenience: create a fresh SettingsStore over the same UserDefaults,
    /// simulating a relaunch with the same persisted data.
    private func freshStore(on defaults: UserDefaults) -> SettingsStore {
        SettingsStore(defaults: defaults)
    }

    // MARK: - cleanupEnabled

    func testCleanupEnabledDefaultIsTrue() throws {
        let store = freshStore(on: try makeIsolatedDefaults())
        XCTAssertTrue(store.cleanupEnabled, "cleanupEnabled default must be true (v0 default: on).")
    }

    func testCleanupEnabledRoundTrips() throws {
        let defaults = try makeIsolatedDefaults()
        let store = freshStore(on: defaults)
        store.cleanupEnabled = false

        let reloaded = freshStore(on: defaults)
        XCTAssertFalse(reloaded.cleanupEnabled,
            "cleanupEnabled=false must survive a SettingsStore reload on the same defaults.")
    }

    func testCleanupEnabledTrueRoundTrips() throws {
        let defaults = try makeIsolatedDefaults()
        let store = freshStore(on: defaults)
        store.cleanupEnabled = false    // flip to false first
        store.cleanupEnabled = true     // then back to true

        let reloaded = freshStore(on: defaults)
        XCTAssertTrue(reloaded.cleanupEnabled,
            "cleanupEnabled=true must survive a SettingsStore reload on the same defaults.")
    }

    // MARK: - cleanupEngine

    func testCleanupEngineDefaultIsFoundationModels() throws {
        let store = freshStore(on: try makeIsolatedDefaults())
        XCTAssertEqual(store.cleanupEngine, .foundationModels,
            "cleanupEngine default must be .foundationModels.")
    }

    func testCleanupEngineFoundationModelsRoundTrips() throws {
        let defaults = try makeIsolatedDefaults()
        let store = freshStore(on: defaults)
        store.cleanupEngine = .ollama(model: "qwen2.5")
        store.cleanupEngine = .foundationModels   // overwrite back

        let reloaded = freshStore(on: defaults)
        XCTAssertEqual(reloaded.cleanupEngine, .foundationModels,
            ".foundationModels must round-trip through JSON encoding.")
    }

    func testCleanupEngineOllamaRoundTripsWithAssociatedValue() throws {
        let defaults = try makeIsolatedDefaults()
        let store = freshStore(on: defaults)
        store.cleanupEngine = .ollama(model: "qwen2.5-3b")

        let reloaded = freshStore(on: defaults)
        XCTAssertEqual(reloaded.cleanupEngine, .ollama(model: "qwen2.5-3b"),
            ".ollama(model:) including the associated model string must round-trip.")
    }

    func testCleanupEngineOllamaEmptyModelRoundTrips() throws {
        let defaults = try makeIsolatedDefaults()
        let store = freshStore(on: defaults)
        store.cleanupEngine = .ollama(model: "")

        let reloaded = freshStore(on: defaults)
        XCTAssertEqual(reloaded.cleanupEngine, .ollama(model: ""),
            ".ollama(model: \"\") must round-trip (empty string is a valid placeholder).")
    }

    // MARK: - sttEngine

    func testSTTEngineDefaultIsAppleSpeech() throws {
        let store = freshStore(on: try makeIsolatedDefaults())
        XCTAssertEqual(store.sttEngine, .appleSpeech,
            "sttEngine default must be .appleSpeech.")
    }

    func testSTTEngineAppleSpeechRoundTrips() throws {
        let defaults = try makeIsolatedDefaults()
        let store = freshStore(on: defaults)
        store.sttEngine = .whisperKit       // set to a v0.1 stub
        store.sttEngine = .appleSpeech      // overwrite back

        let reloaded = freshStore(on: defaults)
        XCTAssertEqual(reloaded.sttEngine, .appleSpeech,
            ".appleSpeech must round-trip through JSON encoding.")
    }

    func testSTTEngineWhisperKitRoundTrips() throws {
        let defaults = try makeIsolatedDefaults()
        let store = freshStore(on: defaults)
        store.sttEngine = .whisperKit

        let reloaded = freshStore(on: defaults)
        XCTAssertEqual(reloaded.sttEngine, .whisperKit,
            ".whisperKit must round-trip (even though it is a v0.1 placeholder).")
    }

    func testSTTEngineWhisperCppRoundTrips() throws {
        let defaults = try makeIsolatedDefaults()
        let store = freshStore(on: defaults)
        store.sttEngine = .whisperCpp

        let reloaded = freshStore(on: defaults)
        XCTAssertEqual(reloaded.sttEngine, .whisperCpp,
            ".whisperCpp must round-trip (even though it is a v1 placeholder).")
    }

    // MARK: - language

    func testLanguageDefaultIsEnUS() throws {
        let store = freshStore(on: try makeIsolatedDefaults())
        XCTAssertEqual(store.language.identifier, "en-US",
            "language default must be en-US.")
    }

    func testLanguageEnGBRoundTrips() throws {
        let defaults = try makeIsolatedDefaults()
        let store = freshStore(on: defaults)
        store.language = Locale(identifier: "en-GB")

        let reloaded = freshStore(on: defaults)
        XCTAssertEqual(reloaded.language.identifier, "en-GB",
            "en-GB must round-trip through the locale identifier string.")
    }

    func testLanguageEnUSRoundTrips() throws {
        let defaults = try makeIsolatedDefaults()
        let store = freshStore(on: defaults)
        store.language = Locale(identifier: "en-GB")
        store.language = Locale(identifier: "en-US")

        let reloaded = freshStore(on: defaults)
        XCTAssertEqual(reloaded.language.identifier, "en-US",
            "en-US must round-trip after overwriting en-GB.")
    }

    // MARK: - pasteMode

    func testPasteModeDefaultIsCmdV() throws {
        let store = freshStore(on: try makeIsolatedDefaults())
        XCTAssertEqual(store.pasteMode, .cmdV,
            "pasteMode default must be .cmdV.")
    }

    func testPasteModeCmdVRoundTrips() throws {
        let defaults = try makeIsolatedDefaults()
        let store = freshStore(on: defaults)
        store.pasteMode = .accessibility
        store.pasteMode = .cmdV

        let reloaded = freshStore(on: defaults)
        XCTAssertEqual(reloaded.pasteMode, .cmdV,
            ".cmdV must round-trip.")
    }

    func testPasteModeAccessibilityRoundTrips() throws {
        let defaults = try makeIsolatedDefaults()
        let store = freshStore(on: defaults)
        store.pasteMode = .accessibility

        let reloaded = freshStore(on: defaults)
        XCTAssertEqual(reloaded.pasteMode, .accessibility,
            ".accessibility must round-trip (v1 placeholder value).")
    }

    // MARK: - defaultCleaner(for:) factory

    func testDefaultCleanerReturnsNilWhenCleanupDisabled() throws {
        let store = freshStore(on: try makeIsolatedDefaults())
        store.cleanupEnabled = false
        XCTAssertNil(defaultCleaner(for: store),
            "defaultCleaner must return nil when cleanupEnabled == false.")
    }

    func testDefaultCleanerReturnsFoundationModelsCleanerWhenEnabled() throws {
        let store = freshStore(on: try makeIsolatedDefaults())
        store.cleanupEnabled = true
        store.cleanupEngine = .foundationModels
        let cleaner = defaultCleaner(for: store)
        XCTAssertNotNil(cleaner,
            "defaultCleaner must return a non-nil cleaner when cleanupEnabled == true.")
        XCTAssertTrue(cleaner is FoundationModelsCleaner,
            "defaultCleaner must return a FoundationModelsCleaner for .foundationModels.")
    }

    func testDefaultCleanerFallsBackWhenOllamaRequested() throws {
        // Wave 2.1: OllamaCleaner is now a real stub type (not a silent FM fallback).
        // defaultCleaner returns OllamaCleaner, whose isAvailable==false causes
        // CaptureSession.runCleanup to gracefully fall back to raw transcript.
        // The test verifies the type identity after the Wave 2.1 change. [decision Wave 2.1]
        let store = freshStore(on: try makeIsolatedDefaults())
        store.cleanupEnabled = true
        store.cleanupEngine = .ollama(model: "qwen2.5")
        let cleaner = defaultCleaner(for: store)
        XCTAssertNotNil(cleaner,
            "defaultCleaner must return a non-nil OllamaCleaner when .ollama is selected.")
        XCTAssertTrue(cleaner is OllamaCleaner,
            "defaultCleaner must return OllamaCleaner (not FM fallback) when .ollama is selected. " +
            "The OllamaCleaner stub returns isAvailable==false; CaptureSession falls back gracefully.")
    }

    // MARK: - defaultTranscriber(for:) factory

    func testDefaultTranscriberReturnsAppleSpeechForAppleSpeech() throws {
        let store = freshStore(on: try makeIsolatedDefaults())
        store.sttEngine = .appleSpeech
        let transcriber = defaultTranscriber(for: store)
        XCTAssertTrue(transcriber is AppleSpeechTranscriber,
            "defaultTranscriber must return AppleSpeechTranscriber for .appleSpeech.")
    }

    func testDefaultTranscriberFallsBackForWhisperKit() throws {
        // WhisperKit is v0.1 — defaultTranscriber logs + falls back to AppleSpeech.
        let store = freshStore(on: try makeIsolatedDefaults())
        store.sttEngine = .whisperKit
        let transcriber = defaultTranscriber(for: store)
        XCTAssertTrue(transcriber is AppleSpeechTranscriber,
            "defaultTranscriber v0.1 stub must fall back to AppleSpeechTranscriber for .whisperKit.")
    }

    func testDefaultTranscriberFallsBackForWhisperCpp() throws {
        // whisper.cpp is v1 — defaultTranscriber logs + falls back to AppleSpeech.
        let store = freshStore(on: try makeIsolatedDefaults())
        store.sttEngine = .whisperCpp
        let transcriber = defaultTranscriber(for: store)
        XCTAssertTrue(transcriber is AppleSpeechTranscriber,
            "defaultTranscriber v1 stub must fall back to AppleSpeechTranscriber for .whisperCpp.")
    }

    // MARK: - customVocabulary (H4 seam)

    func testCustomVocabularyDefaultIsEmpty() throws {
        let store = freshStore(on: try makeIsolatedDefaults())
        XCTAssertEqual(store.customVocabulary, [],
            "customVocabulary default must be [] — no injection in the baseline path.")
    }

    func testCustomVocabularyRoundTrips() throws {
        let defaults = try makeIsolatedDefaults()
        let store = freshStore(on: defaults)
        store.customVocabulary = ["Xcodegen", "SpeakCore", "SpeechAnalyzer"]

        let reloaded = freshStore(on: defaults)
        XCTAssertEqual(reloaded.customVocabulary, ["Xcodegen", "SpeakCore", "SpeechAnalyzer"],
            "customVocabulary must survive a SettingsStore reload on the same defaults.")
    }

    func testCustomVocabularyEmptyArrayRoundTrips() throws {
        let defaults = try makeIsolatedDefaults()
        let store = freshStore(on: defaults)
        store.customVocabulary = ["term1"]
        store.customVocabulary = []   // clear back to empty

        let reloaded = freshStore(on: defaults)
        XCTAssertEqual(reloaded.customVocabulary, [],
            "Clearing customVocabulary to [] must persist and reload as [].")
    }

    // MARK: - effectiveCleanupLevel (W3.1 collapse)

    /// Legacy back-compat: a user who toggled `cleanupEnabled=false` under the old UI
    /// has `enabled=false, level=medium`. The effective picker must show `.none` (not "Medium").
    func testEffectiveCleanupLevelReturnsNoneWhenCleanupDisabled() throws {
        let defaults = try makeIsolatedDefaults()
        let store = freshStore(on: defaults)
        store.cleanupEnabled = false
        store.cleanupLevel = .medium  // legacy state: off toggle but level still stored as medium
        XCTAssertEqual(store.effectiveCleanupLevel, .none,
            "effectiveCleanupLevel must return .none when cleanupEnabled==false, regardless of stored level.")
    }

    func testEffectiveCleanupLevelReturnsMediumWhenEnabled() throws {
        let defaults = try makeIsolatedDefaults()
        let store = freshStore(on: defaults)
        store.cleanupEnabled = true
        store.cleanupLevel = .medium
        XCTAssertEqual(store.effectiveCleanupLevel, .medium,
            "effectiveCleanupLevel must return the stored level when cleanupEnabled==true.")
    }

    func testEffectiveCleanupLevelSetterNoneDisablesCleanup() throws {
        let defaults = try makeIsolatedDefaults()
        let store = freshStore(on: defaults)
        store.cleanupEnabled = true
        store.cleanupLevel = .high
        store.effectiveCleanupLevel = .none  // user picks "None"
        XCTAssertFalse(store.cleanupEnabled,
            "Setting effectiveCleanupLevel to .none must set cleanupEnabled=false.")
        XCTAssertEqual(store.cleanupLevel, .none,
            "Setting effectiveCleanupLevel to .none must also set cleanupLevel=.none.")
    }

    func testEffectiveCleanupLevelSetterNonNoneEnablesCleanup() throws {
        let defaults = try makeIsolatedDefaults()
        let store = freshStore(on: defaults)
        store.cleanupEnabled = false
        store.effectiveCleanupLevel = .light  // user picks a level from the off state
        XCTAssertTrue(store.cleanupEnabled,
            "Setting effectiveCleanupLevel to a non-none level must set cleanupEnabled=true.")
        XCTAssertEqual(store.cleanupLevel, .light,
            "Setting effectiveCleanupLevel to .light must set cleanupLevel=.light.")
    }

    func testEffectiveCleanupLevelRoundTrips() throws {
        let defaults = try makeIsolatedDefaults()
        let store = freshStore(on: defaults)
        for level in CleanupLevel.allCases {
            store.effectiveCleanupLevel = level
            let reloaded = freshStore(on: defaults)
            XCTAssertEqual(reloaded.effectiveCleanupLevel, level,
                "effectiveCleanupLevel=.\(level) must survive a SettingsStore reload.")
        }
    }

    // MARK: - Multiple properties persist independently

    func testMultiplePropertiesPersistIndependently() throws {
        let defaults = try makeIsolatedDefaults()
        let store = freshStore(on: defaults)
        store.cleanupEnabled = false
        store.language = Locale(identifier: "en-GB")
        store.pasteMode = .accessibility
        store.sttEngine = .whisperKit
        store.cleanupEngine = .ollama(model: "phi-4")

        let reloaded = freshStore(on: defaults)
        XCTAssertFalse(reloaded.cleanupEnabled)
        XCTAssertEqual(reloaded.language.identifier, "en-GB")
        XCTAssertEqual(reloaded.pasteMode, .accessibility)
        XCTAssertEqual(reloaded.sttEngine, .whisperKit)
        XCTAssertEqual(reloaded.cleanupEngine, .ollama(model: "phi-4"))
    }

}
