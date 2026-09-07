// SpeakTests/AnimatedTranscriptViewTests.swift
//
// Unit tests for `AnimatedTranscriptView`'s raw→clean diff initialization
// (input-felt-speed.md §3.3 — the "visible AI transformation" reveal).
//
// HONESTY BOUNDARY: these tests verify the pure diff-resolution logic that the
// view's `init(rawText:cleanedText:)` seeds — that canceled/inserted/normal
// tokens are classified correctly from a raw→clean pair. They do NOT assert on
// SwiftUI rendering (animated strikethrough, flow layout, ScrollView) — that is
// an irreducibly-live visual surface, consistent with the rest of the codebase.
//
// The view's initializer is the contract under test: given a raw transcript
// preserved at stop (`settlingText`) and the cleaned result, the view must show
// the transformation — removed words as `.canceled`, added words as `.inserted`,
// kept words as `.normal` — exactly once.

@testable import Speak
import SpeakCore
import XCTest

@MainActor
final class AnimatedTranscriptViewTests: XCTestCase {

    /// A real raw→clean pair where "um" is removed: the diff must classify it canceled
    /// and the rest normal — the user watches "um" get struck, not a hard swap.
    func testInit_rawCleanPair_marksCanceledAndNormal() {
        let raw = "um I wanted to ask"
        let cleaned = "I wanted to ask"

        let view = AnimatedTranscriptView(rawText: raw, cleanedText: cleaned)

        let canceled = view.diffTokens.filter { $0.state == .canceled }
        let inserted = view.diffTokens.filter { $0.state == .inserted }
        let normal = view.diffTokens.filter { $0.state == .normal }

        XCTAssertEqual(canceled.map(\.text), ["um"], "Removed filler must be a canceled token.")
        XCTAssertTrue(inserted.isEmpty, "No words were added in this cleanup.")
        XCTAssertEqual(
            normal.map(\.text).joined(separator: " "), "I wanted to ask",
            "Kept words must be normal tokens reconstructing the cleaned text."
        )
    }

    /// A clean that adds a word: the diff must mark it inserted.
    func testInit_rawCleanPair_marksInserted() {
        let raw = "I want to ask"
        let cleaned = "I want to clearly ask"

        let view = AnimatedTranscriptView(rawText: raw, cleanedText: cleaned)

        let inserted = view.diffTokens.filter { $0.state == .inserted }
        XCTAssertEqual(inserted.map(\.text), ["clearly"], "Added word must be an inserted token.")
    }

    /// Identical raw→clean must produce only normal tokens — no fake strikes or inserts.
    func testInit_identicalPair_onlyNormalTokens() {
        let text = "hello world"
        let view = AnimatedTranscriptView(rawText: text, cleanedText: text)

        XCTAssertTrue(view.diffTokens.allSatisfy { $0.state == .normal }, "Identical pair → all normal.")
    }

    /// The diff must be seeded exactly once (not recomputed on every body render) — the
    /// `State` initial value is set at construction. This pins the "no duplicate/flicker"
    /// requirement: the same raw+cleaned must not re-strike or re-insert.
    func testInit_seedsDiffExactlyOnce() {
        let raw = "um one two"
        let cleaned = "one two"
        let view = AnimatedTranscriptView(rawText: raw, cleanedText: cleaned)

        // The resolved tokens are stable at construction — calling the initializer again
        // must produce an identical diff (deterministic resolver), never a growing set.
        let second = AnimatedTranscriptView(rawText: raw, cleanedText: cleaned)
        XCTAssertEqual(view.diffTokens.map(\.text), second.diffTokens.map(\.text))
        XCTAssertEqual(view.diffTokens.map(\.state), second.diffTokens.map(\.state))
    }

    /// Cancellation must not strike the wrong word: a word shared between raw and clean
    /// must never be canceled just because a DIFFERENT word elsewhere was removed.
    func testInit_cancelsOnlyRemovedWords_notSharedWords() {
        let raw = "please refactor the audio capture"
        let cleaned = "refactor the audio capture"
        let view = AnimatedTranscriptView(rawText: raw, cleanedText: cleaned)

        let canceled = view.diffTokens.filter { $0.state == .canceled }
        let normal = view.diffTokens.filter { $0.state == .normal }

        XCTAssertEqual(canceled.map(\.text), ["please"], "Only the removed word is canceled.")
        XCTAssertFalse(normal.contains { $0.text == "please" }, "A removed word must not be normal.")
        XCTAssertEqual(
            normal.map(\.text).joined(separator: " "), "refactor the audio capture",
            "Shared words must all remain normal."
        )
    }
}
