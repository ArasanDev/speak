// SpeakTests/VoiceSandboxTests.swift
//
// Tests for the "Test My Voice" sandbox path — `SpeakEngine.beginAuxiliarySession`
// (includeCleanup: true). Mock engines only; the assertion surface is wiring:
//
//   - the aux session is paste-free by construction (engine wires inserter: nil)
//   - acoustic corrections apply to the delivered rawText (expander chain)
//   - cleaner gated on cleanupEnabled && cleanupLevel != .none
//   - cleaner receives the corrected text + merged vocabulary mode
//   - state machine reaches .done (not .error) on a clean run
//   - cleanupStatus honestly reports .cleaned / .skipped
//
// [fix: audit — C1] `VoiceSandbox` (a parallel, ungated factory minting a second
// transcriber) is deleted; the sandbox is an engine-minted auxiliary session
// sharing the engine's transcriber so mute/TCC/single-capture gates apply.

@testable import SpeakCore
import XCTest

// MARK: - Mocks

private final class SandboxTranscriber: Transcribing, @unchecked Sendable {
    let id = "sandbox-stt"
    private let script: [TranscriptChunk]

    init(text: String) {
        script = [TranscriptChunk(text: text, isFinal: true, timestamp: Date())]
    }

    func startStream(locale: Locale) -> AsyncThrowingStream<TranscriptChunk, Error> {
        let script = self.script
        return AsyncThrowingStream { continuation in
            let task = Task {
                for chunk in script {
                    continuation.yield(chunk)
                    try? await Task.sleep(nanoseconds: 1_000_000)
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func stop() async {}
}

private final class SandboxCleaner: LLMCleaning, @unchecked Sendable {
    let id = "sandbox-cleaner"
    var isAvailable: Bool { true }
    private(set) var lastText: String?
    private(set) var lastMode: CleanupMode?

    /// Marker suffix (not a "Cleaned:"-style prefix — `extractTargetTranscript`
    /// strips LLM label prefixes, so a prefix marker would be eaten and the
    /// assertion would read raw text).
    func clean(_ text: String, mode: CleanupMode) async throws -> String {
        lastText = text
        lastMode = mode
        return "\(text) [cleaned]"
    }
}

/// A no-op history store so the engine can be constructed headlessly.
private final class NullHistory: HistoryStoring, @unchecked Sendable {
    func save(_ entry: HistoryEntry) async throws {}
    func recent(limit: Int) async throws -> [HistoryEntry] { [] }
    func search(_ substring: String) async throws -> [HistoryEntry] { [] }
    func clear() async throws {}
    func export() async throws -> String { "[]" }
}

// MARK: - Tests

final class VoiceSandboxTests: XCTestCase {

    private func freshDefaults() -> UserDefaults {
        let name = "speak.tests.sandbox.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: name) else {
            XCTFail("UserDefaults(suiteName:) returned nil")
            return .standard
        }
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    /// Drive a sandbox run through the REAL engine path: `beginAuxiliarySession`
    /// mints+starts (mute/TCC/single-capture gates inside), `endAuxiliarySession`
    /// stops under the watchdog and releases the slot.
    private func runSandbox(
        settings: SettingsStore,
        said: String,
        cleaner: SandboxCleaner? = SandboxCleaner(),
        snippetStore: SnippetStore? = nil
    ) async throws -> TranscriptionResult {
        let engine = SpeakEngine(
            transcriber: SandboxTranscriber(text: said),
            cleaner: cleaner,
            inserter: nil,
            history: NullHistory(),
            settings: settings,
            snippetStore: snippetStore,
            isMicrophoneAuthorized: { true }
        )
        let session = try await engine.beginAuxiliarySession(includeCleanup: true)
        return try await engine.endAuxiliarySession(session)
    }

    func testSandboxReturnsResultWithoutPaste() async throws {
        let settings = SettingsStore(defaults: freshDefaults())
        let result = try await runSandbox(settings: settings, said: "um hello world")
        XCTAssertEqual(result.rawText, "um hello world")
        XCTAssertEqual(result.cleanedText, "um hello world [cleaned]")
        XCTAssertEqual(result.engineId, "sandbox-stt+sandbox-cleaner")
        XCTAssertEqual(result.cleanupStatus, .cleaned)
    }

    func testSandboxAppliesAcousticCorrectionsToRawAndCleanerInput() async throws {
        let settings = SettingsStore(defaults: freshDefaults())
        settings.acousticCorrections = [
            AcousticCorrection(heard: "rippo", typed: "repo"),
            AcousticCorrection(heard: "cubectl", typed: "kubectl")
        ]
        let cleaner = SandboxCleaner()
        let result = try await runSandbox(
            settings: settings, said: "open the rippo and run cubectl", cleaner: cleaner
        )
        XCTAssertEqual(result.rawText, "open the repo and run kubectl",
                       "Corrections land in the delivered rawText.")
        XCTAssertEqual(cleaner.lastText, "open the repo and run kubectl",
                       "The cleaner sees corrected text, not the mishearing.")
    }

    func testSandboxRespectsCorrectionsBeforeSnippetsOrder() async throws {
        let settings = SettingsStore(defaults: freshDefaults())
        settings.acousticCorrections = [AcousticCorrection(heard: "rippo", typed: "repo")]
        let snippets = SnippetStore(defaults: freshDefaults())
        XCTAssertTrue(snippets.add(trigger: "repo", expansion: "the repo"))

        let result = try await runSandbox(
            settings: settings, said: "push to rippo", cleaner: nil,
            snippetStore: snippets
        )
        XCTAssertEqual(result.rawText, "push to the repo",
                       "Correction must restore the trigger before snippet expansion.")
    }

    func testSandboxCleanupDisabledDeliversRaw() async throws {
        let settings = SettingsStore(defaults: freshDefaults())
        settings.cleanupEnabled = false
        let result = try await runSandbox(settings: settings, said: "hello")
        XCTAssertNil(result.cleanedText)
        XCTAssertEqual(result.engineId, "sandbox-stt")
        XCTAssertEqual(result.rawText, "hello")
        XCTAssertEqual(result.cleanupStatus, .skipped)
    }

    func testSandboxCleanupLevelNoneDeliversRaw() async throws {
        let settings = SettingsStore(defaults: freshDefaults())
        settings.cleanupLevel = .none
        let result = try await runSandbox(settings: settings, said: "hello")
        XCTAssertNil(result.cleanedText)
        XCTAssertEqual(result.engineId, "sandbox-stt")
        XCTAssertEqual(result.cleanupStatus, .skipped)
    }

    func testSandboxNilCleanerDeliversRaw() async throws {
        let settings = SettingsStore(defaults: freshDefaults())
        let result = try await runSandbox(settings: settings, said: "hello", cleaner: nil)
        XCTAssertNil(result.cleanedText)
        XCTAssertEqual(result.rawText, "hello")
        XCTAssertEqual(result.cleanupStatus, .skipped)
    }

    func testSandboxCleanerReceivesEffectiveVocabulary() async throws {
        let settings = SettingsStore(defaults: freshDefaults())
        settings.customVocabulary = ["GraphQL"]
        settings.acousticCorrections = [AcousticCorrection(heard: "cubectl", typed: "kubectl")]
        let cleaner = SandboxCleaner()
        _ = try await runSandbox(settings: settings, said: "hello", cleaner: cleaner)
        guard case .styled(_, _, let vocab) = cleaner.lastMode else {
            XCTFail("Expected .styled cleanup mode, got \(String(describing: cleaner.lastMode))")
            return
        }
        XCTAssertEqual(vocab, ["GraphQL", "kubectl"])
    }

    /// Command Mode path (`includeCleanup: false`): no cleaner is wired even
    /// when cleanup is on — the instruction capture is transcriber-only.
    func testAuxiliarySessionWithoutCleanupDeliversRaw() async throws {
        let settings = SettingsStore(defaults: freshDefaults())
        let engine = SpeakEngine(
            transcriber: SandboxTranscriber(text: "make it formal"),
            cleaner: SandboxCleaner(),
            inserter: nil,
            history: NullHistory(),
            settings: settings,
            isMicrophoneAuthorized: { true }
        )
        let session = try await engine.beginAuxiliarySession(includeCleanup: false)
        let result = try await engine.endAuxiliarySession(session)
        XCTAssertNil(result.cleanedText)
        XCTAssertEqual(result.rawText, "make it formal")
        XCTAssertEqual(result.cleanupStatus, .skipped)
    }
}
