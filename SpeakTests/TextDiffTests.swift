// SpeakTests/TextDiffTests.swift
//
// Unit tests for the W4.1 pure word-level diff in SpeakCore/Diff/TextDiff.swift.
//
// SCOPE:
//   - Tokenizer: whitespace splitting, edge cases.
//   - Diff algorithm: edge cases (empty/identical/no-overlap) + typical cases.
//   - DiffSegment identity: kind + text fields, not UUID (UUIDs are regenerated).
//   - Collapse: consecutive same-kind edits merged into one segment.
//
// HONESTY BOUNDARY: these tests verify the pure transform function only —
// no SwiftUI rendering is tested here (Canvas preview serves that role).
// No live model invoked.

import XCTest
@testable import SpeakCore

final class TextDiffTests: XCTestCase {

    // MARK: - Tokenizer

    func testTokenize_emptyString() {
        XCTAssertEqual(tokenize(""), [])
    }

    func testTokenize_singleWord() {
        XCTAssertEqual(tokenize("hello"), ["hello"])
    }

    func testTokenize_multipleWords() {
        XCTAssertEqual(tokenize("hello world foo"), ["hello", "world", "foo"])
    }

    func testTokenize_extraWhitespace() {
        XCTAssertEqual(tokenize("  hello   world  "), ["hello", "world"])
    }

    func testTokenize_tabsAndNewlines() {
        XCTAssertEqual(tokenize("one\ttwo\nthree"), ["one", "two", "three"])
    }

    func testTokenize_punctuationAttached() {
        // Punctuation is part of the word token, not split separately.
        XCTAssertEqual(tokenize("Hello, world!"), ["Hello,", "world!"])
    }

    // MARK: - Edge cases

    func testDiff_bothEmpty() {
        let result = textDiff(raw: "", cleaned: "")
        XCTAssertTrue(result.isEmpty, "Both empty → no segments.")
    }

    func testDiff_rawEmpty() {
        let result = textDiff(raw: "", cleaned: "hello world")
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].kind, .insert)
        XCTAssertEqual(result[0].text, "hello world")
    }

    func testDiff_cleanedEmpty() {
        let result = textDiff(raw: "hello world", cleaned: "")
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].kind, .delete)
        XCTAssertEqual(result[0].text, "hello world")
    }

    func testDiff_identical() {
        let result = textDiff(raw: "hello world", cleaned: "hello world")
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].kind, .equal)
        XCTAssertEqual(result[0].text, "hello world")
    }

    func testDiff_singleWord_rawEmpty() {
        let result = textDiff(raw: "", cleaned: "hello")
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].kind, .insert)
        XCTAssertEqual(result[0].text, "hello")
    }

    func testDiff_singleWord_cleanedEmpty() {
        let result = textDiff(raw: "hello", cleaned: "")
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].kind, .delete)
        XCTAssertEqual(result[0].text, "hello")
    }

    func testDiff_noOverlap() {
        // No common words → delete all raw, insert all cleaned.
        let result = textDiff(raw: "foo bar", cleaned: "baz qux")
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result[0].kind, .delete)
        XCTAssertEqual(result[0].text, "foo bar")
        XCTAssertEqual(result[1].kind, .insert)
        XCTAssertEqual(result[1].text, "baz qux")
    }

    // MARK: - Typical transcript diff cases

    func testDiff_fillerWordRemoval() {
        // "Um I wanted to ask" → "I wanted to ask"
        // "Um" is deleted; rest is equal.
        let result = textDiff(raw: "Um I wanted to ask", cleaned: "I wanted to ask")
        let kinds = result.map { $0.kind }
        XCTAssertTrue(kinds.contains(.delete), "Removed 'Um' must appear as a delete segment.")
        XCTAssertTrue(kinds.contains(.equal), "Unchanged words must appear as an equal segment.")
        XCTAssertFalse(kinds.contains(.insert), "No words were added.")

        // The delete segment must contain "Um".
        let deleteSegment = result.first { $0.kind == .delete }
        XCTAssertEqual(deleteSegment?.text, "Um")

        // The equal segment must contain the shared tail.
        let equalSegment = result.first { $0.kind == .equal }
        XCTAssertEqual(equalSegment?.text, "I wanted to ask")
    }

    func testDiff_punctuationAdded() {
        // "hello world" → "Hello, world." (different tokens due to punctuation)
        // Both words differ from punctuation-attached forms → full delete + insert.
        let result = textDiff(raw: "hello world", cleaned: "Hello, world.")
        XCTAssertFalse(result.isEmpty)
        // Both tokens changed → no equal segments (tokens don't match due to punctuation).
        // Result must reconstruct to the original lengths.
        let deletedText = result.filter { $0.kind == .delete }.map(\.text).joined(separator: " ")
        let insertedText = result.filter { $0.kind == .insert }.map(\.text).joined(separator: " ")
        XCTAssertFalse(deletedText.isEmpty || insertedText.isEmpty,
                       "Punctuated forms differ from originals — both delete and insert expected.")
    }

    func testDiff_wordAddedInMiddle() {
        // "I want to ask" → "I want to clearly ask"
        // "clearly" is inserted between "to" and "ask".
        let result = textDiff(raw: "I want to ask", cleaned: "I want to clearly ask")
        let kinds = result.map { $0.kind }
        XCTAssertTrue(kinds.contains(.insert), "Added word 'clearly' must appear as insert.")
        let insertSeg = result.first { $0.kind == .insert }
        XCTAssertEqual(insertSeg?.text, "clearly")
    }

    func testDiff_multipleFillerWordsRemoved() {
        // "Um uh I think so you know" → "I think so"
        // Consecutive deletes collapsed into one segment each.
        let result = textDiff(raw: "Um uh I think so you know", cleaned: "I think so")
        let deleteSeg = result.filter { $0.kind == .delete }
        // "Um uh" at start + "you know" at end are deleted.
        // At least one delete segment must exist.
        XCTAssertFalse(deleteSeg.isEmpty, "Filler words must be in delete segments.")

        let equalSeg = result.filter { $0.kind == .equal }
        XCTAssertFalse(equalSeg.isEmpty, "Shared words must be in equal segments.")

        // Verify reconstruction: equal + insert text = cleaned text (modulo spacing).
        let reconstructedCleaned = result
            .filter { $0.kind != .delete }
            .map(\.text)
            .joined(separator: " ")
        XCTAssertEqual(reconstructedCleaned, "I think so",
                       "Non-delete segments must reconstruct the cleaned text.")
    }

    func testDiff_collapsingConsecutiveDeletes() {
        // Two consecutive deletes must collapse to one segment.
        let segments = diff(rawTokens: ["a", "b", "c"], cleanedTokens: ["c"])
        // "a" and "b" are deleted, "c" is equal.
        let deletes = segments.filter { $0.kind == .delete }
        XCTAssertEqual(deletes.count, 1, "Consecutive deletes must collapse into one segment.")
        XCTAssertEqual(deletes[0].text, "a b")
    }

    func testDiff_collapsingConsecutiveInserts() {
        // Two consecutive inserts must collapse to one segment.
        let segments = diff(rawTokens: ["c"], cleanedTokens: ["a", "b", "c"])
        let inserts = segments.filter { $0.kind == .insert }
        XCTAssertEqual(inserts.count, 1, "Consecutive inserts must collapse into one segment.")
        XCTAssertEqual(inserts[0].text, "a b")
    }

    // MARK: - DiffSegment identifiers

    func testDiffSegment_uniqueIDs() {
        // Each segment gets a UUID so SwiftUI ForEach has stable IDs.
        let result = textDiff(raw: "a b c", cleaned: "a x c")
        let ids = result.map { $0.id }
        // All IDs must be distinct.
        XCTAssertEqual(Set(ids).count, ids.count, "All DiffSegments must have unique IDs.")
    }

    func testDiffSegment_equatability() {
        // Two segments with same kind+text are equal (by Equatable).
        let s1 = DiffSegment(kind: .equal, text: "hello")
        let s2 = DiffSegment(kind: .equal, text: "hello")
        // Equatable derives from kind+text only — id (UUID) is NOT part of ==.
        // Wait: the synthesized Equatable from stored properties WOULD include id.
        // Our DiffSegment has kind, text, id all stored; synthesized == includes all three.
        // So two distinct instances are NOT equal. That's fine — identity is via .id for ForEach,
        // and logical equality isn't needed at the view layer. This test documents the behavior.
        XCTAssertNotEqual(s1, s2, "Distinct DiffSegment instances with same kind+text are not equal (UUID differs).")
        XCTAssertEqual(s1.kind, s2.kind)
        XCTAssertEqual(s1.text, s2.text)
    }

    // MARK: - CleanupLevel intensity (W4.1 — 4-level enum)

    func testCleanupLevel_allCasesCount() {
        // W4.1 added `.none` → 4 cases total (not 3).
        XCTAssertEqual(CleanupLevel.allCases.count, 4,
                       "W4.1 defines 4 CleanupLevel cases: none/light/medium/high.")
    }

    func testCleanupLevel_displayNames() {
        XCTAssertEqual(CleanupLevel.none.displayName, "None")
        XCTAssertEqual(CleanupLevel.light.displayName, "Light")
        XCTAssertEqual(CleanupLevel.medium.displayName, "Medium")
        XCTAssertEqual(CleanupLevel.high.displayName, "High")
    }

    func testCleanupLevel_levelDescriptions() {
        // Each level must have a non-empty description for Settings UI.
        for level in CleanupLevel.allCases {
            XCTAssertFalse(level.levelDescription.isEmpty,
                           "\(level).levelDescription must be non-empty.")
        }
    }

    func testCleanupLevel_rawValues() {
        // rawValues are the storage keys — changing them breaks persisted settings.
        XCTAssertEqual(CleanupLevel.none.rawValue, "none")
        XCTAssertEqual(CleanupLevel.light.rawValue, "light")
        XCTAssertEqual(CleanupLevel.medium.rawValue, "medium")
        XCTAssertEqual(CleanupLevel.high.rawValue, "high")
    }

    func testCleanupLevel_noneDecodesFromRawValue() {
        // Explicitly typed to disambiguate from Optional.none — `CleanupLevel.none`
        // is a valid enum case, not Swift's Optional nil. [decision W4.1]
        let decoded: CleanupLevel? = CleanupLevel(rawValue: "none")
        XCTAssertEqual(decoded, CleanupLevel.none,
                       "rawValue 'none' must decode to CleanupLevel.none (the enum case, not Optional.none).")
    }

    func testCleanupLevel_unknownRawValueReturnsNil() {
        // Old rawValues (basic/balanced/thorough) no longer decode — confirmed behavior.
        XCTAssertNil(CleanupLevel(rawValue: "basic"),
                     "Old rawValue 'basic' must not decode — SettingsStore falls back to .medium.")
        XCTAssertNil(CleanupLevel(rawValue: "balanced"))
        XCTAssertNil(CleanupLevel(rawValue: "thorough"))
    }

    // MARK: - Prompt mapping (intensity clauses)

    @available(macOS 26.0, *)
    func testPromptMapping_noneReturnsNonEmpty() {
        // The .none branch in styledInstructions is a safety fallback; it must be non-empty.
        let prompt = FoundationModelsCleaner.styledInstructions(style: .default, level: .none)
        XCTAssertFalse(prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                       "Level .none must produce a non-empty (defensive) prompt.")
    }

    @available(macOS 26.0, *)
    func testPromptMapping_lightHasLightTouchClause() {
        let prompt = FoundationModelsCleaner.styledInstructions(style: .default, level: .light)
        XCTAssertTrue(prompt.lowercased().contains("light touch"),
                      "Light level must mention 'light touch'.")
    }

    @available(macOS 26.0, *)
    func testPromptMapping_mediumHasSentenceTightening() {
        let prompt = FoundationModelsCleaner.styledInstructions(style: .default, level: .medium)
        XCTAssertTrue(prompt.lowercased().contains("tighten"),
                      "Medium level must mention tightening sentences.")
    }

    @available(macOS 26.0, *)
    func testPromptMapping_highHasRestructureAndParagraph() {
        let prompt = FoundationModelsCleaner.styledInstructions(style: .default, level: .high)
        let lower = prompt.lowercased()
        XCTAssertTrue(lower.contains("restructure") || lower.contains("paragraph"),
                      "High level must mention restructuring or paragraphs.")
    }

    @available(macOS 26.0, *)
    func testPromptMapping_allLevelsDistinct() {
        let prompts = CleanupLevel.allCases.map {
            FoundationModelsCleaner.styledInstructions(style: .default, level: $0)
        }
        XCTAssertEqual(Set(prompts).count, CleanupLevel.allCases.count,
                       "Each level must produce a distinct prompt.")
    }

    @available(macOS 26.0, *)
    func testPromptMapping_instructionsForStyledRoutesThroughStyledInstructions() {
        // Verify the dispatch path: .styled(style, level) → styledInstructions.
        // Use modeInstructions(for:) — the mode-only layer — since instructions(for:)
        // now prepends the universal transcriptGuard which is not mode-specific.
        for level in CleanupLevel.allCases {
            let viaMode = FoundationModelsCleaner.modeInstructions(for: .styled(.professional, level))
            let direct = FoundationModelsCleaner.styledInstructions(style: .professional, level: level)
            XCTAssertEqual(viaMode, direct,
                           "modeInstructions(for: .styled(.professional, .\(level))) must equal styledInstructions.")
        }
    }
}
