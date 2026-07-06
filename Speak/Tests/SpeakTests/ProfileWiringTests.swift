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
        XCTAssertEqual(resolved.name, "Agent", "Xcode is an Agent-destination target app.")
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
        let out = PromptBuilder.instructions(profile: DefaultProfiles.write)
        XCTAssertFalse(out.contains("Dictated speech:"),
                       "instructions() is the no-transcript block (the transcript is fed separately).")
        XCTAssertTrue(out.contains("clean up spoken words"),
                      "The Write profile's system prompt must be present.")
    }

    func testIntensityClauseThreaded() {
        let light = PromptBuilder.instructions(profile: DefaultProfiles.write, intensity: .light)
        let medium = PromptBuilder.instructions(profile: DefaultProfiles.write, intensity: .medium)
        let high = PromptBuilder.instructions(profile: DefaultProfiles.write, intensity: .high)
        XCTAssertTrue(light.contains("light edits"), "Light intensity must add its clause.")
        XCTAssertTrue(high.contains("thoroughly"), "High intensity must add its clause.")
        XCTAssertFalse(medium.contains("light edits") || medium.contains("thoroughly"),
                       "Medium is the baseline — it adds no intensity clause.")
        XCTAssertNil(PromptBuilder.intensityClause(.medium))
        XCTAssertNil(PromptBuilder.intensityClause(.none))
    }

    func testCustomVocabularyClauseThreaded() {
        let out = PromptBuilder.instructions(
            profile: DefaultProfiles.write, customVocabulary: ["SpeakCore", "CGEvent"]
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
        guard case .profile(let profile, let level, let category, _, _) = session.cleanupMode else {
            return XCTFail("A matching app must select the .profile cleanup mode.")
        }
        XCTAssertEqual(profile.name, "Agent")
        XCTAssertEqual(level, .medium, "The user's cleanup level must thread through as intensity.")
        XCTAssertEqual(category, .task, "Category defaults to .task.")
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

    // MARK: - V01-3 (per-app context, profile-native): Chat/Write split

    func testResolverMatchesSlackToChat() {
        let resolved = ProfileResolver.resolve(
            frontmostBundleID: "com.tinyspeck.slackmacgap",
            profiles: DefaultProfiles.all,
            default: DefaultProfiles.defaultProfile
        )
        XCTAssertEqual(resolved.name, "Chat", "Slack is a Chat-destination target app.")
        XCTAssertEqual(resolved.tone, .casual, "Chat must carry the casual tone knob.")
    }

    func testResolverMatchesMailToWrite() {
        let resolved = ProfileResolver.resolve(
            frontmostBundleID: "com.apple.mail",
            profiles: DefaultProfiles.all,
            default: DefaultProfiles.defaultProfile
        )
        XCTAssertEqual(resolved.name, "Write", "Mail stays on the formal-ish Write destination.")
        XCTAssertNotEqual(resolved.tone, .casual, "Write must not carry Chat's casual tone.")
    }

    func testResolverFallsBackToDefaultForUnknownBundle() {
        let resolved = ProfileResolver.resolve(
            frontmostBundleID: "com.totally.unknown.app",
            profiles: DefaultProfiles.all,
            default: DefaultProfiles.defaultProfile
        )
        XCTAssertEqual(resolved.id, DefaultProfiles.defaultProfile.id,
                       "An unrecognized bundle id must fall back to the global default.")
    }

    /// The bundle-ID map lives in exactly one place (`targetApps`) — no app should
    /// resolve to both Chat and Write.
    func testChatAndWriteTargetAppsDoNotOverlap() {
        let overlap = Set(DefaultProfiles.chat.targetApps).intersection(DefaultProfiles.write.targetApps)
        XCTAssertTrue(overlap.isEmpty,
                      "Chat and Write targetApps must not overlap: \(overlap)")
    }

    // MARK: - V01-3: perAppContextEnabled toggle

    private func makeEngine(perAppContextEnabled: Bool) throws -> SpeakEngine {
        let name = "ProfileWiringTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        addTeardownBlock { defaults.removePersistentDomain(forName: name) }
        let settings = SettingsStore(defaults: defaults)
        settings.perAppContextEnabled = perAppContextEnabled
        return SpeakEngine(
            transcriber: NullTranscriber(),
            cleaner: NullCleaner(),
            inserter: nil,
            history: NullHistory(),
            settings: settings
        )
    }

    func testTogglingPerAppContextOffIgnoresFrontmostAppEvenWhenMatching() async throws {
        let engine = try makeEngine(perAppContextEnabled: false)
        // Xcode would normally resolve to the Agent profile (see
        // testNewSessionUsesProfileModeForMatchingApp) — with the toggle off it must not.
        let session = await engine.newSession(frontmostBundleID: "com.apple.dt.Xcode")
        guard case .styled = session.cleanupMode else {
            return XCTFail(
                "perAppContextEnabled == false must reproduce the no-app-context baseline "
                + "(.styled default) regardless of a matching frontmost app."
            )
        }
    }

    func testTogglingPerAppContextOnRestoresMatching() async throws {
        let engine = try makeEngine(perAppContextEnabled: true)
        let session = await engine.newSession(frontmostBundleID: "com.apple.dt.Xcode")
        guard case .profile(let profile, _, _, _, _) = session.cleanupMode else {
            return XCTFail("perAppContextEnabled == true must restore app-matched profile selection.")
        }
        XCTAssertEqual(profile.name, "Agent")
    }
}
