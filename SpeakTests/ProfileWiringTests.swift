// SpeakTests/ProfileWiringTests.swift
//
// PE-0 → dictation-flow wiring (the increment that makes profiles felt):
//   • ProfileResolver (pure): frontmost-app bundle id → profile.
//   • PromptBuilder.instructions(): the no-transcript instruction block + the
//     threaded intensity / custom-vocabulary clauses.
//   • SpeakEngine.newSession(frontmostBundleID:): app-match → .profile mode;
//     no match / nil → the unchanged .styled default (zero regression).
//
// All autonomously verifiable without a live Foundation Models pass.

@testable import SpeakCore
import XCTest

final class ProfileWiringTests: XCTestCase {

    // MARK: - ProfileResolver (pure)

    func testResolverMatchesFrontmostApp() {
        let resolved = ProfileResolver.resolve(
            frontmostBundleID: "com.apple.dt.Xcode",
            profiles: DefaultProfiles.all,
            default: DefaultProfiles.defaultProfile
        )
        XCTAssertEqual(resolved.name, "Code", "Xcode is a Code-profile target app.")
    }

    func testResolverFallsBackToDefaultOnNoMatch() {
        let resolved = ProfileResolver.resolve(
            frontmostBundleID: "com.unknown.app",
            profiles: DefaultProfiles.all,
            default: DefaultProfiles.defaultProfile
        )
        XCTAssertEqual(resolved.id, DefaultProfiles.defaultProfile.id, "No match → global default.")
    }

    func testResolverFallsBackOnNilOrEmpty() {
        for id: String? in [nil, ""] {
            let resolved = ProfileResolver.resolve(
                frontmostBundleID: id, profiles: DefaultProfiles.all,
                default: DefaultProfiles.defaultProfile
            )
            XCTAssertEqual(resolved.id, DefaultProfiles.defaultProfile.id,
                           "nil/empty bundle id → global default.")
        }
    }

    // MARK: - PromptBuilder.instructions

    func testInstructionsExcludeTranscript() {
        let out = PromptBuilder.instructions(profile: DefaultProfiles.clean)
        XCTAssertFalse(out.contains("Dictated speech:"),
                       "instructions() is the no-transcript block (the transcript is fed separately).")
        XCTAssertTrue(out.contains("clean up dictated speech"),
                      "The Clean profile's system prompt must be present.")
    }

    func testIntensityClauseThreaded() {
        let light = PromptBuilder.instructions(profile: DefaultProfiles.clean, intensity: .light)
        let medium = PromptBuilder.instructions(profile: DefaultProfiles.clean, intensity: .medium)
        let high = PromptBuilder.instructions(profile: DefaultProfiles.clean, intensity: .high)
        XCTAssertTrue(light.contains("light edits"), "Light intensity must add its clause.")
        XCTAssertTrue(high.contains("thoroughly"), "High intensity must add its clause.")
        XCTAssertFalse(medium.contains("light edits") || medium.contains("thoroughly"),
                       "Medium is the baseline — it adds no intensity clause.")
        XCTAssertNil(PromptBuilder.intensityClause(.medium))
        XCTAssertNil(PromptBuilder.intensityClause(.none))
    }

    func testCustomVocabularyClauseThreaded() {
        let out = PromptBuilder.instructions(
            profile: DefaultProfiles.clean, customVocabulary: ["SpeakCore", "CGEvent"]
        )
        XCTAssertTrue(out.contains("SpeakCore") && out.contains("CGEvent"),
                      "Custom vocabulary terms must be preserved in the instructions.")
    }

    // MARK: - SpeakEngine.newSession(frontmostBundleID:)

    private struct NullTranscriber: Transcribing, @unchecked Sendable {
        let id = "null-stt"
        func startStream(locale: Locale) -> AsyncThrowingStream<TranscriptChunk, Error> {
            AsyncThrowingStream { $0.finish() }
        }
        func stop() async {}
    }

    private struct NullCleaner: LLMCleaning, @unchecked Sendable {
        let id = "null-cleaner"
        var isAvailable: Bool { get async { true } }
        func clean(_ text: String, mode: CleanupMode) async throws -> String { text }
    }

    private final class NullHistory: HistoryStoring, @unchecked Sendable {
        func save(_ entry: HistoryEntry) throws {}
        func recent(limit: Int) throws -> [HistoryEntry] { [] }
        func search(_ substring: String) throws -> [HistoryEntry] { [] }
        func clear() throws {}
        func export() throws -> String { "[]" }
    }

    private func makeEngine() throws -> SpeakEngine {
        let name = "ProfileWiringTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        addTeardownBlock { defaults.removePersistentDomain(forName: name) }
        // Defaults: cleanupEnabled == true, cleanupLevel == .medium → cleaner runs.
        let settings = SettingsStore(defaults: defaults)
        return SpeakEngine(
            transcriber: NullTranscriber(),
            cleaner: NullCleaner(),
            inserter: nil,
            history: NullHistory(),
            settings: settings
        )
    }

    func testNewSessionUsesProfileModeForMatchingApp() async throws {
        let engine = try makeEngine()
        let session = await engine.newSession(frontmostBundleID: "com.apple.dt.Xcode")
        guard case .profile(let profile, let level, _) = session.cleanupMode else {
            return XCTFail("A matching app must select the .profile cleanup mode.")
        }
        XCTAssertEqual(profile.name, "Code")
        XCTAssertEqual(level, .medium, "The user's cleanup level must thread through as intensity.")
    }

    func testNewSessionKeepsStyledDefaultForNoMatch() async throws {
        let engine = try makeEngine()
        for id: String? in [nil, "com.unknown.app"] {
            let session = await engine.newSession(frontmostBundleID: id)
            guard case .styled = session.cleanupMode else {
                return XCTFail("No app match must keep the unchanged .styled default (zero regression).")
            }
        }
    }
}
