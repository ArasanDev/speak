// SpeakCore/Eval — tests for the SM-2 Phase0b metric redesign adopted 2026-07-04:
// edge-punctuation-normalizing tokenizer, multiReference correctness, and the
// noUnspokenIdentifiers anti-hallucination guard. See research/eval-metric-redesign-review.md.

import Foundation
@testable import SpeakCore
import XCTest

final class EvalScoringMetricRedesignTests: XCTestCase {
    /// A trailing-period-only difference must not cost correctness score.
    func testScoringCorrectnessIgnoresEdgePunctuation() throws {
        let withPeriod = correctness(
            output: "Fix the crash when opening the history pane.",
            expected: "Fix the crash when opening the history pane"
        )
        XCTAssertEqual(withPeriod, 1.0)
    }

    /// multiReference correctness: score is the max Jaccard over all acceptable
    /// phrasings, removing the single-phrasing ceiling.
    func testScoringMultiReferenceCorrectness() throws {
        let output = "Fix the paste issue after the first dictation."
        let reportOnly = "The paste isn't working after the first dictation."
        let imperative = "Fix the paste issue after the first dictation."

        XCTAssertLessThan(correctness(output: output, references: [reportOnly]), 0.80)
        XCTAssertEqual(correctness(output: output, references: [reportOnly, imperative]), 1.0)
        XCTAssertEqual(correctness(output: output, references: []), 0.0)
    }

    /// Anti-hallucination guard: an output that invents a file/symbol the speaker
    /// never said must be flagged.
    func testScoringNoUnspokenIdentifiersGuard() throws {
        let spoken = "fix the bug in capture session where paste only works the first time"

        // Legitimate identifier-ization of spoken words — grounded, should pass.
        XCTAssertTrue(noUnspokenIdentifiers(
            output: "Fix the bug in CaptureSession where paste only works the first time.",
            spoken: spoken
        ))

        // Invented file the speaker never mentioned — must fail.
        XCTAssertFalse(noUnspokenIdentifiers(
            output: "Fix the bug in PasteboardWriter.swift's writeOnce() function.",
            spoken: spoken
        ))
    }
}
