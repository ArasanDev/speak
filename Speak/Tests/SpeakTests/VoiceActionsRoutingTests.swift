// SpeakTests/VoiceActionsRoutingTests.swift
//
// H-1 (specs/horizon-voice-os.md, Pillar 1) — unit tests for `PrefixActionRouter`,
// the pure deterministic-prefix-gate router. No Process, no App-layer AX: this
// is exactly the "pure function, unit-testable without Process" piece the task
// brief calls for.

@testable import SpeakCore
import XCTest

final class VoiceActionsRoutingTests: XCTestCase {

    private let router = PrefixActionRouter(prefix: "hey speak")

    // MARK: - No prefix → dictation, unconditionally

    func testNoPrefix_routesToDictation() {
        XCTAssertEqual(router.route("write a haiku about the ocean", knownActionNames: []), .dictation)
    }

    func testPrefixMidSentence_doesNotMatch() {
        // The prefix must anchor at the START — "well hey speak" should NOT trigger.
        XCTAssertEqual(router.route("well hey speak open downloads", knownActionNames: []), .dictation)
    }

    func testEmptyTranscript_routesToDictation() {
        XCTAssertEqual(router.route("", knownActionNames: []), .dictation)
        XCTAssertEqual(router.route("   ", knownActionNames: []), .dictation)
    }

    func testEmptyPrefixConfig_disablesGateDefensively() {
        let disabledRouter = PrefixActionRouter(prefix: "")
        XCTAssertEqual(
            disabledRouter.route("hey speak open downloads", knownActionNames: ["Open Downloads"]),
            .dictation
        )
    }

    // MARK: - Prefix present, no known-action match → command

    func testPrefixWithFreeformRemainder_routesToCommand() {
        XCTAssertEqual(
            router.route("hey speak make this more formal", knownActionNames: []),
            .command(instruction: "make this more formal")
        )
    }

    func testPrefixIsCaseInsensitive() {
        XCTAssertEqual(
            router.route("HEY SPEAK make this more formal", knownActionNames: []),
            .command(instruction: "make this more formal")
        )
        XCTAssertEqual(
            router.route("Hey Speak make this more formal", knownActionNames: []),
            .command(instruction: "make this more formal")
        )
    }

    func testPrefixWithLeadingComma_isStripped() {
        XCTAssertEqual(
            router.route("hey speak, make this more formal", knownActionNames: []),
            .command(instruction: "make this more formal")
        )
    }

    func testPrefixWithOnlyWhitespaceRemainder_routesToDictation() {
        XCTAssertEqual(router.route("hey speak", knownActionNames: []), .dictation)
        XCTAssertEqual(router.route("hey speak   ", knownActionNames: []), .dictation)
    }

    func testCommandRemainderNotInCatalog_routesToCommand() {
        XCTAssertEqual(
            router.route("hey speak open my downloads", knownActionNames: ["Good Morning", "Wind Down"]),
            .command(instruction: "open my downloads")
        )
    }

    // MARK: - Prefix present, exact known-action match → action

    func testPrefixWithExactCatalogMatch_routesToAction() {
        XCTAssertEqual(
            router.route("hey speak good morning", knownActionNames: ["Good Morning", "Wind Down"]),
            .action(name: "Good Morning")
        )
    }

    func testActionMatchIsCaseInsensitive_butReturnsCanonicalCatalogCasing() {
        // Spoken casing ("GOOD MORNING") must not leak into the returned name —
        // `shortcuts run` may be case-sensitive, so the canonical catalog string wins.
        XCTAssertEqual(
            router.route("hey speak GOOD MORNING", knownActionNames: ["Good Morning"]),
            .action(name: "Good Morning")
        )
    }

    func testActionMatchRequiresExactRemainder_partialDoesNotMatch() {
        // "good morning routine" != "good morning" — no exact match, falls to command.
        XCTAssertEqual(
            router.route("hey speak good morning routine", knownActionNames: ["Good Morning"]),
            .command(instruction: "good morning routine")
        )
    }

    func testEmptyCatalog_neverProducesAction() {
        XCTAssertEqual(
            router.route("hey speak good morning", knownActionNames: []),
            .command(instruction: "good morning")
        )
    }

    // MARK: - Decision table (documents the full input → route mapping)

    func testDecisionTable() {
        let catalog = ["Good Morning"]
        let cases: [(String, VoiceRoute)] = [
            ("write a haiku about the ocean", .dictation),
            ("well hey speak good morning", .dictation),
            ("", .dictation),
            ("hey speak", .dictation),
            ("hey speak make this more formal", .command(instruction: "make this more formal")),
            ("hey speak good morning", .action(name: "Good Morning")),
            ("hey speak good morning routine", .command(instruction: "good morning routine"))
        ]
        for (input, expected) in cases {
            XCTAssertEqual(router.route(input, knownActionNames: catalog), expected,
                "input '\(input)' should route to \(expected)")
        }
    }
}
