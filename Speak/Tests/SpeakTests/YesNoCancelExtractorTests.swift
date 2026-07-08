// SpeakTests/YesNoCancelExtractorTests.swift
//
// Table-driven coverage of `YesNoCancelExtractor` (H-3, specs/horizon-voice-os.md
// Pillar 3) — every phrase in all three lists, plus normalization edge cases
// (case, punctuation, whitespace) and unmatched input.

@testable import SpeakCore
import XCTest

final class YesNoCancelExtractorTests: XCTestCase {

    // MARK: - Yes phrases

    func testYesPhrases() {
        let phrases = ["yes", "yeah", "yep", "sure", "correct", "affirmative", "right", "okay", "ok"]
        for phrase in phrases {
            XCTAssertEqual(YesNoCancelExtractor.extract(phrase), .yes, "expected '\(phrase)' to extract as .yes")
        }
    }

    // MARK: - No phrases

    func testNoPhrases() {
        let phrases = ["no", "nope", "negative", "nah", "not really"]
        for phrase in phrases {
            XCTAssertEqual(YesNoCancelExtractor.extract(phrase), .no, "expected '\(phrase)' to extract as .no")
        }
    }

    // MARK: - Cancel phrases

    func testCancelPhrases() {
        let phrases = ["cancel", "never mind", "nevermind", "stop", "forget it"]
        for phrase in phrases {
            XCTAssertEqual(YesNoCancelExtractor.extract(phrase), .cancel, "expected '\(phrase)' to extract as .cancel")
        }
    }

    // MARK: - Normalization

    func testUppercaseIsNormalized() {
        XCTAssertEqual(YesNoCancelExtractor.extract("YES"), .yes)
        XCTAssertEqual(YesNoCancelExtractor.extract("No"), .no)
        XCTAssertEqual(YesNoCancelExtractor.extract("CANCEL"), .cancel)
    }

    func testTrailingPunctuationIsStripped() {
        XCTAssertEqual(YesNoCancelExtractor.extract("yes!"), .yes)
        XCTAssertEqual(YesNoCancelExtractor.extract("no."), .no)
        XCTAssertEqual(YesNoCancelExtractor.extract("okay?"), .yes)
    }

    func testSurroundingWhitespaceIsTrimmed() {
        XCTAssertEqual(YesNoCancelExtractor.extract("  yes  "), .yes)
        XCTAssertEqual(YesNoCancelExtractor.extract("\nno\n"), .no)
    }

    func testInternalWhitespaceRunsCollapse() {
        XCTAssertEqual(YesNoCancelExtractor.extract("never   mind"), .cancel)
        XCTAssertEqual(YesNoCancelExtractor.extract("not    really"), .no)
    }

    // MARK: - Unmatched input

    func testUnmatchedInputIsUnclear() {
        let unmatched = ["maybe", "I don't know", "what?", "coffee", "42"]
        for phrase in unmatched {
            XCTAssertEqual(YesNoCancelExtractor.extract(phrase), .unclear, "expected '\(phrase)' to be .unclear")
        }
    }

    func testEmptyStringIsUnclear() {
        XCTAssertEqual(YesNoCancelExtractor.extract(""), .unclear)
    }

    func testWhitespaceOnlyStringIsUnclear() {
        XCTAssertEqual(YesNoCancelExtractor.extract("   \n\t  "), .unclear)
    }

    // MARK: - No partial/fuzzy matching

    func testPhraseEmbeddedInLongerSentenceIsUnclear() {
        // The extractor exact-matches the normalized whole string — it does not
        // attempt to find "yes" inside "yes I think so", which could easily be a
        // sarcastic or qualified answer. Unmatched → unclear, never a guess.
        // [decision: H-3]
        XCTAssertEqual(YesNoCancelExtractor.extract("yes I think so"), .unclear)
        XCTAssertEqual(YesNoCancelExtractor.extract("well, no"), .unclear)
    }
}
