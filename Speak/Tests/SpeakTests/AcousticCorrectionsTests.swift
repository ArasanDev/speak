// SpeakTests/AcousticCorrectionsTests.swift
//
// Tests for the "acoustic slips" table (Settings ▸ Vocabulary): the pure edit
// rules, the `SnippetExpanding`-conforming correction pass, the corrections →
// snippets expander chain ordering, the settings persistence round-trip, and
// `effectiveVocabulary` merging (correction targets bias the recognizer AND
// the cleanup prompt).

@testable import SpeakCore
import XCTest

final class AcousticCorrectionsTests: XCTestCase {

    private func freshDefaults() -> UserDefaults {
        let name = "speak.tests.acoustic.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: name) else {
            XCTFail("UserDefaults(suiteName:) returned nil")
            return .standard
        }
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    // MARK: - Edit rules (AcousticCorrections.upsert / .removing)

    func testUpsertAppendsNewCorrection() {
        let list = AcousticCorrections.upsert(heard: "rippo", typed: "repo", in: [])
        XCTAssertEqual(list, [AcousticCorrection(heard: "rippo", typed: "repo")])
    }

    func testUpsertTrimsBothFields() {
        let list = AcousticCorrections.upsert(heard: "  cubectl ", typed: " kubectl ", in: [])
        XCTAssertEqual(list.first?.heard, "cubectl")
        XCTAssertEqual(list.first?.typed, "kubectl")
    }

    func testUpsertIgnoresBlankFields() {
        XCTAssertTrue(AcousticCorrections.upsert(heard: "", typed: "repo", in: []).isEmpty)
        XCTAssertTrue(AcousticCorrections.upsert(heard: "rippo", typed: "   ", in: []).isEmpty)
    }

    func testUpsertReplacesCaseInsensitivelyInPlace() {
        var list = AcousticCorrections.upsert(heard: "rippo", typed: "repo", in: [])
        list = AcousticCorrections.upsert(heard: "darker", typed: "docker", in: list)
        list = AcousticCorrections.upsert(heard: "RIPPO", typed: "repository", in: list)
        XCTAssertEqual(list.count, 2, "Same heard term must not duplicate the row.")
        XCTAssertEqual(list[0].typed, "repository", "Re-add updates typed in place.")
        XCTAssertEqual(list[1].heard, "darker")
    }

    func testRemovingDropsCaseInsensitiveMatches() {
        let list = [
            AcousticCorrection(heard: "rippo", typed: "repo"),
            AcousticCorrection(heard: "cubectl", typed: "kubectl")
        ]
        let next = AcousticCorrections.removing(heard: "CUBECTL", from: list)
        XCTAssertEqual(next.count, 1)
        XCTAssertEqual(next.first?.heard, "rippo")
    }

    // MARK: - AcousticCorrectionExpander

    func testExpanderReplacesHeardWithTypedWholeWord() {
        let expander = AcousticCorrectionExpander(corrections: [
            AcousticCorrection(heard: "rippo", typed: "repo")
        ])
        XCTAssertEqual(expander.expand("open the rippo"), "open the repo")
        XCTAssertEqual(expander.expand("open the RIPPO"), "open the repo",
                       "Match must be case-insensitive like SnippetExpander.")
    }

    func testExpanderLeavesSubstringsAlone() {
        let expander = AcousticCorrectionExpander(corrections: [
            AcousticCorrection(heard: "darker", typed: "docker")
        ])
        XCTAssertEqual(expander.expand("a darker theme"), "a docker theme")
        XCTAssertEqual(expander.expand("the darkness grows"), "the darkness grows",
                       "Whole-word matching: 'darker' inside 'darkness' must not fire.")
    }

    func testExpanderHandlesMultiWordSlips() {
        let expander = AcousticCorrectionExpander(corrections: [
            AcousticCorrection(heard: "insane c", typed: "in sync")
        ])
        XCTAssertEqual(expander.expand("are they insane c yet"), "are they in sync yet")
    }

    // MARK: - CompositeExpander ordering

    /// Corrections run BEFORE snippets: a snippet trigger the user actually
    /// said still fires even though the recognizer mangled it.
    func testCorrectionsBeforeSnippetsOrdering() {
        let expander = CompositeExpander([
            AcousticCorrectionExpander(corrections: [
                AcousticCorrection(heard: "rippo", typed: "repo")
            ]),
            SnippetExpander(snippets: [Snippet(trigger: "repo", expansion: "my-repo")])
        ])
        XCTAssertEqual(expander.expand("open the rippo"), "open the my-repo",
                       "Correction must restore the trigger before snippet expansion.")
    }

    // MARK: - defaultExpander factory

    /// The seeded built-in slip table means the expander is never nil —
    /// built-ins are active even with zero user configuration.
    /// [decision: built-in slips merge under user entries]
    func testDefaultExpanderAlwaysPresentViaBuiltIns() {
        let store = SettingsStore(defaults: freshDefaults())
        let expander = defaultExpander(for: store, snippetStore: nil)
        XCTAssertNotNil(expander)
        XCTAssertEqual(expander?.expand("paste this into cloth code"), "paste this into Claude Code")
    }

    /// A user row for the same `heard` must win over the built-in — including
    /// an identity row used to disable a built-in slip.
    func testUserCorrectionOverridesBuiltIn() {
        let store = SettingsStore(defaults: freshDefaults())
        store.acousticCorrections = [AcousticCorrection(heard: "codecs", typed: "codecs")]
        let expander = defaultExpander(for: store, snippetStore: nil)
        XCTAssertEqual(expander?.expand("the codecs we ship"), "the codecs we ship")
    }

    func testDefaultExpanderAppliesCorrectionsThenSnippets() {
        let store = SettingsStore(defaults: freshDefaults())
        store.acousticCorrections = [AcousticCorrection(heard: "rippo", typed: "repo")]
        let snippets = SnippetStore(defaults: freshDefaults())
        XCTAssertTrue(snippets.add(trigger: "repo", expansion: "the repo"))

        let expander = defaultExpander(for: store, snippetStore: snippets)
        XCTAssertNotNil(expander)
        XCTAssertEqual(expander?.expand("push to rippo"), "push to the repo")
    }

    // MARK: - Persistence

    func testAcousticCorrectionsRoundTrip() {
        let defaults = freshDefaults()
        let store = SettingsStore(defaults: defaults)
        XCTAssertTrue(store.acousticCorrections.isEmpty)

        let rows = [
            AcousticCorrection(heard: "rippo", typed: "repo"),
            AcousticCorrection(heard: "cubectl", typed: "kubectl"),
            AcousticCorrection(heard: "insane c", typed: "in sync")
        ]
        store.acousticCorrections = rows

        let reloaded = SettingsStore(defaults: defaults)
        XCTAssertEqual(reloaded.acousticCorrections, rows)
    }

    func testEffectiveVocabularyMergesAndDedupes() {
        let store = SettingsStore(defaults: freshDefaults())
        store.customVocabulary = ["GraphQL", "repo"]
        store.acousticCorrections = [
            AcousticCorrection(heard: "rippo", typed: "repo"),
            AcousticCorrection(heard: "cubectl", typed: "kubectl")
        ]
        XCTAssertEqual(store.effectiveVocabulary, ["GraphQL", "repo", "kubectl"],
                       "Correction targets merge into vocabulary; 'repo' deduped.")
    }

    // MARK: - Feedback flags + reset

    func testFeedbackDefaults() {
        let store = SettingsStore(defaults: freshDefaults())
        XCTAssertTrue(store.dictationFeedbackSounds, "Chime defaults on.")
        XCTAssertFalse(store.dictationFeedbackHaptics, "Haptics are opt-in.")
    }

    func testFeedbackRoundTrip() {
        let defaults = freshDefaults()
        let store = SettingsStore(defaults: defaults)
        store.dictationFeedbackSounds = false
        store.dictationFeedbackHaptics = true
        let reloaded = SettingsStore(defaults: defaults)
        XCTAssertFalse(reloaded.dictationFeedbackSounds)
        XCTAssertTrue(reloaded.dictationFeedbackHaptics)
    }

    func testResetToDefaultsClearsCorrectionsAndFeedback() {
        let defaults = freshDefaults()
        let store = SettingsStore(defaults: defaults)
        store.acousticCorrections = [AcousticCorrection(heard: "rippo", typed: "repo")]
        store.dictationFeedbackSounds = false
        store.dictationFeedbackHaptics = true

        store.resetToDefaults()

        XCTAssertTrue(store.acousticCorrections.isEmpty)
        XCTAssertTrue(store.dictationFeedbackSounds)
        XCTAssertFalse(store.dictationFeedbackHaptics)
    }
}
