// SpeakTests/CustomVocabularyTests.swift
//
// Wave B.3 — unit tests for the pure custom-vocabulary edit rules backing the
// Dictionary pane. No UI, no UserDefaults — just the list transforms.

@testable import SpeakCore
import XCTest

final class CustomVocabularyTests: XCTestCase {

    // MARK: - adding

    func testAdding_appendsTrimmedTerm() {
        let result = CustomVocabulary.adding("  Tamil  ", to: ["Swift"])
        XCTAssertEqual(result, ["Swift", "Tamil"], "Term must be trimmed and appended last.")
    }

    func testAdding_ignoresBlank() {
        XCTAssertEqual(CustomVocabulary.adding("   ", to: ["a"]), ["a"])
        XCTAssertEqual(CustomVocabulary.adding("", to: ["a"]), ["a"])
    }

    func testAdding_dedupesCaseInsensitively() {
        let result = CustomVocabulary.adding("swift", to: ["Swift"])
        XCTAssertEqual(result, ["Swift"], "A case-insensitive duplicate must not be added.")
    }

    func testAdding_keepsFirstSpelling() {
        // Adding "SWIFT" when "Swift" exists keeps the original spelling.
        let result = CustomVocabulary.adding("SWIFT", to: ["Swift"])
        XCTAssertEqual(result, ["Swift"])
    }

    func testAdding_toEmptyList() {
        XCTAssertEqual(CustomVocabulary.adding("Kubernetes", to: []), ["Kubernetes"])
    }

    // MARK: - removing

    func testRemoving_deletesCaseInsensitiveMatch() {
        let result = CustomVocabulary.removing("swift", from: ["Swift", "Rust"])
        XCTAssertEqual(result, ["Rust"])
    }

    func testRemoving_noMatch_isUnchanged() {
        XCTAssertEqual(CustomVocabulary.removing("Go", from: ["Swift", "Rust"]), ["Swift", "Rust"])
    }

    func testRemoving_removesAllDuplicatesDefensively() {
        // Should never happen (adding dedupes), but removing must clear any stray dupes.
        let result = CustomVocabulary.removing("x", from: ["x", "X", "y"])
        XCTAssertEqual(result, ["y"])
    }
}
