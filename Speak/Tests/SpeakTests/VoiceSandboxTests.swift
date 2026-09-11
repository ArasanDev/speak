// SpeakTests/VoiceSandboxTests.swift
//
// Tests for `VoiceSandbox` — the "Test My Voice" session factory backing
// Settings ▸ AI Models. Mock engines only; the assertion surface is wiring:
//
//   - inserter is nil → the run is paste-free by construction
//   - acoustic corrections apply to the delivered rawText (expander chain)
//   - cleaner gated on cleanupEnabled && cleanupLevel != .none
//   - cleaner receives the corrected text + merged vocabulary mode
//   - state machine reaches .done (not .error) on a clean run

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

    private func runSandbox(
        settings: SettingsStore,
        said: String,
        cleaner: SandboxCleaner? = SandboxCleaner(),
        snippetStore: SnippetStore? = nil
    ) async throws -> TranscriptionResult {
        let sandbox = VoiceSandbox(
            settings: settings,
            transcriber: SandboxTranscriber(text: said),
            cleaner: cleaner
        )
        // Inject the snippet store through the production path when supplied:
        // the test seam sets snippetStore to nil, so build the expander the
        // same way makeSession() does when snippets matter.
        let session: CaptureSession
        if snippetStore != nil {
            let levelIsNone = settings.cleanupLevel == .none
            session = CaptureSession(
                transcriber: SandboxTranscriber(text: said),
                cleaner: (settings.cleanupEnabled && !levelIsNone) ? cleaner : nil,
                inserter: nil,
                locale: settings.language,
                cleanupMode: .styled(settings.cleanupStyle, settings.cleanupLevel,
                                     customVocabulary: settings.effectiveVocabulary),
                expander: defaultExpander(for: settings, snippetStore: snippetStore)
            )
        } else {
            session = sandbox.makeSession()
        }
        try await session.start()
        return try await session.stop()
    }

    func testSandboxReturnsResultWithoutPaste() async throws {
        let settings = SettingsStore(defaults: freshDefaults())
        let result = try await runSandbox(settings: settings, said: "um hello world")
        XCTAssertEqual(result.rawText, "um hello world")
        XCTAssertEqual(result.cleanedText, "um hello world [cleaned]")
        XCTAssertEqual(result.engineId, "sandbox-stt+sandbox-cleaner")
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
    }

    func testSandboxCleanupLevelNoneDeliversRaw() async throws {
        let settings = SettingsStore(defaults: freshDefaults())
        settings.cleanupLevel = .none
        let result = try await runSandbox(settings: settings, said: "hello")
        XCTAssertNil(result.cleanedText)
        XCTAssertEqual(result.engineId, "sandbox-stt")
    }

    func testSandboxNilCleanerDeliversRaw() async throws {
        let settings = SettingsStore(defaults: freshDefaults())
        let result = try await runSandbox(settings: settings, said: "hello", cleaner: nil)
        XCTAssertNil(result.cleanedText)
        XCTAssertEqual(result.rawText, "hello")
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
}
