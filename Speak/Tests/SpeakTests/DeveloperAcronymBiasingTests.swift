// SpeakTests/DeveloperAcronymBiasingTests.swift
//
// Requirement R3.3: Developer Acronym Biasing unit tests.
// Verifies developer acronyms (CLI, API, SDK, FTS5, SQLite, etc.) are properly
// included in STT vocabulary biasing and preserved/capitalized by AI cleanup.

@testable import SpeakCore
import XCTest

@available(macOS 26.0, *)
final class DeveloperAcronymBiasingTests: XCTestCase {

    func testAppleSpeechTranscriberDeveloperTermsContainsRequiredAcronyms() {
        let terms = AppleSpeechTranscriber.developerTerms
        let required = ["CLI", "API", "SDK", "FTS5", "SQLite", "SQLite3", "UI", "LLM", "PR", "SQL"]

        for req in required {
            XCTAssertTrue(
                terms.contains(req),
                "AppleSpeechTranscriber.developerTerms must contain '\(req)'"
            )
        }
    }

    func testFixDeveloperAcronymsReplacesHomophonesAndFixesCapitalization() {
        let testCases: [(input: String, expectedSubstring: String)] = [
            ("CL line interface", "CLI interface"),
            ("CLA tools for developer", "CLI tools for developer"),
            ("A page endpoint", "API endpoint"),
            ("S D K version", "SDK version"),
            ("you I component", "UI component"),
            ("L L M model", "LLM model"),
            ("P R review", "PR review"),
            ("F T S 5 full text search", "FTS5 full text search"),
            ("fts5 index", "FTS5 index"),
            ("Fts5 database", "FTS5 database"),
            ("sqlite database engine", "SQLite database engine"),
            ("sequel light table", "SQLite table"),
            ("sql lite query", "SQLite query"),
            ("sqlite3 database", "SQLite3 database")
        ]

        for (input, expected) in testCases {
            let fixed = FoundationModelsCleaner.fixDeveloperAcronyms(input)
            XCTAssertTrue(
                fixed.contains(expected),
                "fixDeveloperAcronyms failed for input '\(input)': expected to contain '\(expected)', got '\(fixed)'"
            )
        }
    }

    /// Regression: the acronym rules used plain substring replacement, so short rules
    /// (`pr`, `ui`, `cli`, `api`) corrupted ordinary English mid-word. Observed live in
    /// dictation history on 2026-07-30, where a real dictation of "the project" cleaned
    /// to "the PRoject". Every case below is a word that CONTAINS an acronym spelling
    /// and must survive untouched.
    func testFixDeveloperAcronymsNeverRewritesAcronymsInsideOrdinaryWords() {
        let mustSurviveVerbatim = [
            // "pr"
            "project", "process", "approach", "improvement", "improving", "proper",
            "product", "progress", "prompt", "practice", "expression",
            // "ui"
            "build", "guide", "building", "quick", "require", "quality", "suite",
            // "cli"
            "client", "click", "clip", "decline", "clipboard",
            // "api"
            "rapid", "capital", "therapist",
            // "ui"/"pr" together, and other short rules
            "prebuilt", "sdkless", "llama", "pruning"
        ]

        for word in mustSurviveVerbatim {
            let fixed = FoundationModelsCleaner.fixDeveloperAcronyms(word)
            XCTAssertEqual(
                fixed, word,
                "fixDeveloperAcronyms corrupted the ordinary word '\(word)' into '\(fixed)'"
            )
        }
    }

    /// The exact sentence shape that reached the user, end to end.
    func testFixDeveloperAcronymsPreservesRealSentenceWhileStillFixingStandaloneAcronyms() {
        let input = "Explore the project and its main purpose, then improve the approach to the cli and api."
        let expected = "Explore the project and its main purpose, then improve the approach to the CLI and API."
        XCTAssertEqual(FoundationModelsCleaner.fixDeveloperAcronyms(input), expected)
    }

    /// Standalone acronyms must still be fixed regardless of the casing the LLM emitted.
    func testFixDeveloperAcronymsIsCaseInsensitiveForStandaloneTokens() {
        let cases: [(String, String)] = [
            ("open a pr for this", "open a PR for this"),
            ("open a PR for this", "open a PR for this"),
            ("the ui is slow", "the UI is slow"),
            ("the UI is slow", "the UI is slow"),
            ("Sqlite storage", "SQLite storage"),
            ("SQLITE storage", "SQLite storage"),
            ("Fts5 index", "FTS5 index")
        ]
        for (input, expected) in cases {
            XCTAssertEqual(
                FoundationModelsCleaner.fixDeveloperAcronyms(input), expected,
                "case-insensitive standalone fix failed for '\(input)'"
            )
        }
    }

    /// Overlapping rules must resolve the same way on every run. The old
    /// `[String: String]` map had nondeterministic iteration order, so `sqlite3` could
    /// lose to `sqlite` and orphan the digit.
    func testFixDeveloperAcronymsIsDeterministicAcrossRepeatedRuns() {
        let input = "sqlite3 and sqlite and sql lite 3 and fts5 and fts 5"
        let first = FoundationModelsCleaner.fixDeveloperAcronyms(input)
        for _ in 0..<50 {
            XCTAssertEqual(
                FoundationModelsCleaner.fixDeveloperAcronyms(input), first,
                "fixDeveloperAcronyms is not deterministic across runs"
            )
        }
        XCTAssertTrue(first.contains("SQLite3"), "expected SQLite3 to survive, got '\(first)'")
        XCTAssertFalse(first.contains("SQLite 3"), "sqlite3 was split into 'SQLite 3': '\(first)'")
    }

    func testAppleSpeechTranscriberVocabularyInitPreservesTerms() {
        let customTerms = ["FTS5", "SQLite", "CustomEngine"]
        let transcriber = AppleSpeechTranscriber(vocabulary: customTerms)
        XCTAssertEqual(transcriber.vocabulary, customTerms)
    }

    func testCollapseStuttersRemovesRepeatedWordsAndPhrases() {
        let cases: [(input: String, expected: String)] = [
            ("I will I will create a repo", "I will create a repo"),
            ("For, for water at all", "For water at all"),
            ("go, go back-end system", "go back-end system"),
            ("anything you, you ask the model", "anything you ask the model"),
            ("the the primary key", "the primary key")
        ]
        for (input, expected) in cases {
            let collapsed = DeveloperAcronymNormalizer.collapseStutters(input)
            XCTAssertEqual(collapsed, expected, "collapseStutters failed for '\(input)'")
        }
    }

    func testPruneConversationalPaddingsStripsPreambleAndTailQuestions() {
        let cases: [(input: String, expected: String)] = [
            ("Now what I want to tell you is like please fix the bug", "Please fix the bug"),
            ("Here is the information I want to give you: check the logs", "Check the logs"),
            ("Okay, correct. We should deploy today", "We should deploy today"),
            ("We can create multiple worktrees, and do you understand my point?", "We can create multiple worktrees"),
            ("Automate the pipeline once stable, can you relate this?", "Automate the pipeline once stable"),
            ("Check if the tests pass, is it clear?", "Check if the tests pass")
        ]
        for (input, expected) in cases {
            let pruned = DeveloperAcronymNormalizer.pruneConversationalPaddings(input)
            XCTAssertEqual(pruned, expected, "pruneConversationalPaddings failed for '\(input)'")
        }
    }
}
