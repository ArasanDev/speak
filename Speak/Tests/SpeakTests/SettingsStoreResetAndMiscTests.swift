// SpeakTests/SettingsStoreResetAndMiscTests.swift
//
// Split out of SettingsStoreTests.swift to keep that class under SwiftLint's
// type_body_length cap (350 lines). Covers: resetToDefaults() coverage,
// defaultTranscriber(for:) factory, streaming/per-app-context/voice-actions
// settings, and the multi-property independence check.
//
// ISOLATION CONTRACT: same as SettingsStoreTests.swift — each test creates its
// own named UserDefaults suite and removes it on teardown. `.standard` is
// never touched.

import CoreGraphics
@testable import SpeakCore
import XCTest

@available(macOS 26.0, *)
final class SettingsStoreResetAndMiscTests: XCTestCase {

    private func makeIsolatedDefaults() throws -> UserDefaults {
        let name = "SettingsStoreResetAndMiscTests.\(UUID().uuidString)"
        let ud = try XCTUnwrap(
            UserDefaults(suiteName: name),
            "UserDefaults(suiteName:) returned nil — this should be impossible for a UUID-based name."
        )
        addTeardownBlock {
            UserDefaults.standard.removePersistentDomain(forName: name)
        }
        return ud
    }

    private func freshStore(on defaults: UserDefaults) -> SettingsStore {
        SettingsStore(defaults: defaults)
    }

    // MARK: - resetToDefaults()

    func testResetToDefaultsRestoresHUDStyleToClassic() throws {
        let store = freshStore(on: try makeIsolatedDefaults())
        store.hudStyle = .aurora
        store.resetToDefaults()
        XCTAssertEqual(store.hudStyle, .classic,
            "resetToDefaults() must restore hudStyle to .classic.")
    }

    func testResetToDefaultsRestoresVoiceAnimationStyleToSonar() throws {
        let store = freshStore(on: try makeIsolatedDefaults())
        store.voiceAnimationStyle = .ringGauge
        store.resetToDefaults()
        XCTAssertEqual(store.voiceAnimationStyle, .sonar,
            "resetToDefaults() must restore voiceAnimationStyle to .sonar.")
    }

    func testResetToDefaultsRestoresCleanupEngineToFoundationModels() throws {
        // cleanupEngine must revert to default on reset.
        let store = freshStore(on: try makeIsolatedDefaults())
        store.cleanupEngine = .openAICompatible(preset: .openAI, model: "gpt-4o-mini")
        store.resetToDefaults()
        XCTAssertEqual(store.cleanupEngine, .foundationModels,
            "resetToDefaults() must restore cleanupEngine to .foundationModels (v0 default).")
    }

    func testResetToDefaultsRestoresExtraBindingsToEmpty() throws {
        // extraBindings must revert to empty on reset.
        let store = freshStore(on: try makeIsolatedDefaults())
        store.extraBindings = ExtraBindingSet(bindings: [
            ExtraBinding(source: .modifierKey(58), action: .activate)
        ])
        store.resetToDefaults()
        XCTAssertEqual(store.extraBindings, .empty,
            "resetToDefaults() must restore extraBindings to .empty.")
    }

    func testResetToDefaultsRestoresRevealTextWhileProcessingToTrue() throws {
        // revealTextWhileProcessing must revert to true on reset.
        let store = freshStore(on: try makeIsolatedDefaults())
        store.revealTextWhileProcessing = false
        store.resetToDefaults()
        XCTAssertTrue(store.revealTextWhileProcessing,
            "resetToDefaults() must restore revealTextWhileProcessing to true.")
    }

    func testResetToDefaultsRestoresAgentPrefixStyle() throws {
        let store = freshStore(on: try makeIsolatedDefaults())
        store.agentPrefixStyle = .voiceSTT
        store.agentPrefixIncludeState = true
        store.resetToDefaults()
        XCTAssertEqual(store.agentPrefixStyle, .speakSTT,
            "resetToDefaults() must restore agentPrefixStyle to .speakSTT.")
        XCTAssertFalse(store.agentPrefixIncludeState,
            "resetToDefaults() must restore agentPrefixIncludeState to false.")
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

    // MARK: - Streaming settings

    func testStreamingRawTextEnabledDefaultTrue() throws {
        let store = freshStore(on: try makeIsolatedDefaults())
        XCTAssertTrue(store.streamingRawTextEnabled,
            "streamingRawTextEnabled default must be true.")
    }

    func testStreamingModePersistedAcrossRestart() throws {
        let defaults = try makeIsolatedDefaults()
        let store = freshStore(on: defaults)
        store.streamingMode = .off

        let reloaded = freshStore(on: defaults)
        XCTAssertEqual(reloaded.streamingMode, .off,
            "streamingMode=.off must survive a SettingsStore reload on the same defaults.")
    }

    // MARK: - perAppContextEnabled (V01-3, profile-native)

    func testPerAppContextEnabledDefaultIsTrue() throws {
        let store = freshStore(on: try makeIsolatedDefaults())
        XCTAssertTrue(store.perAppContextEnabled,
            "perAppContextEnabled default must be true — per-app profile matching has shipped since PE-1.")
    }

    func testPerAppContextEnabledRoundTrips() throws {
        let defaults = try makeIsolatedDefaults()
        let store = freshStore(on: defaults)
        store.perAppContextEnabled = false

        let reloaded = freshStore(on: defaults)
        XCTAssertFalse(reloaded.perAppContextEnabled,
            "perAppContextEnabled=false must survive a SettingsStore reload on the same defaults.")
    }

    // MARK: - Voice Actions (H-1, specs/horizon-voice-os.md Pillar 1)

    func testVoiceActionsEnabledDefaultIsFalse() throws {
        let store = freshStore(on: try makeIsolatedDefaults())
        XCTAssertFalse(store.voiceActionsEnabled,
            "voiceActionsEnabled default must be false — H-1 is an opt-in extension, existing users see no change.")
    }

    func testVoiceActionsEnabledRoundTrips() throws {
        let defaults = try makeIsolatedDefaults()
        let store = freshStore(on: defaults)
        store.voiceActionsEnabled = true

        let reloaded = freshStore(on: defaults)
        XCTAssertTrue(reloaded.voiceActionsEnabled,
            "voiceActionsEnabled=true must survive a SettingsStore reload on the same defaults.")
    }

    func testVoiceActionsPrefixDefaultIsHeySpeak() throws {
        let store = freshStore(on: try makeIsolatedDefaults())
        XCTAssertEqual(store.voiceActionsPrefix, "hey speak")
    }

    func testVoiceActionsPrefixRoundTrips() throws {
        let defaults = try makeIsolatedDefaults()
        let store = freshStore(on: defaults)
        store.voiceActionsPrefix = "computer"

        let reloaded = freshStore(on: defaults)
        XCTAssertEqual(reloaded.voiceActionsPrefix, "computer",
            "voiceActionsPrefix must survive a SettingsStore reload on the same defaults.")
    }
}
