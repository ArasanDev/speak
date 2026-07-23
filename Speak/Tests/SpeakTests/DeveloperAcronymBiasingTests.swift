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

    func testAppleSpeechTranscriberVocabularyInitPreservesTerms() {
        let customTerms = ["FTS5", "SQLite", "CustomEngine"]
        let transcriber = AppleSpeechTranscriber(vocabulary: customTerms)
        XCTAssertEqual(transcriber.vocabulary, customTerms)
    }
}
