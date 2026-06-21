// SpeakTests/StyleModeTests.swift
//
// Wave B.1 — Style modes seam. Covers the two halves that are autonomously verifiable
// WITHOUT a live Foundation Models pass:
//   (1) SettingsStore persistence + defaults for cleanupStyle / cleanupLevel.
//   (2) FoundationModelsCleaner prompt composition for `.styled(style, level)` —
//       distinct, non-empty instructions per voice and per intensity.
//
// The live cleanup *quality* stays [inferred] until a Mac with Apple Intelligence runs
// the P13 dogfood; this suite proves the wiring + prompt mapping, which is what a unit
// test can own honestly.

import XCTest
@testable import SpeakCore

final class StyleModeTests: XCTestCase {

    // MARK: - SettingsStore defaults + persistence

    /// Named-suite defaults unique per test, auto-removed on teardown. `throws` +
    /// `XCTUnwrap` so test code never force-unwraps (swiftlint force_unwrapping rule).
    private func makeIsolatedDefaults() throws -> UserDefaults {
        let name = "StyleModeTests.\(UUID().uuidString)"
        let ud = try XCTUnwrap(UserDefaults(suiteName: name),
                               "UserDefaults(suiteName:) returned nil for a UUID name — impossible.")
        addTeardownBlock { ud.removePersistentDomain(forName: name) }
        return ud
    }

    private func freshStore() throws -> SettingsStore {
        SettingsStore(defaults: try makeIsolatedDefaults())
    }

    // W4.1: renamed to reflect the new default level (.medium, not .balanced)
    func testDefaultStyleIsDefaultAndLevelIsMedium() throws {
        let store = try freshStore()
        XCTAssertEqual(store.cleanupStyle, .default,
                       "Unset cleanupStyle must default to .default (behavior-neutral baseline).")
        // W4.1: default changed from .balanced to .medium (the equivalent in the 4-level scale).
        XCTAssertEqual(store.cleanupLevel, .medium,
                       "Unset cleanupLevel must default to .medium (W4.1 4-level scale).")
    }

    // W4.1: .thorough → .high, .basic → .light
    func testStyleAndLevelRoundTrip() throws {
        let store = try freshStore()
        store.cleanupStyle = .email
        store.cleanupLevel = .high
        XCTAssertEqual(store.cleanupStyle, .email)
        XCTAssertEqual(store.cleanupLevel, .high)
    }

    func testStylePersistsAcrossStoreInstances() throws {
        let defaults = try makeIsolatedDefaults()

        let writer = SettingsStore(defaults: defaults)
        writer.cleanupStyle = .professional
        writer.cleanupLevel = .light

        let reader = SettingsStore(defaults: defaults)
        XCTAssertEqual(reader.cleanupStyle, .professional, "cleanupStyle must persist across instances.")
        XCTAssertEqual(reader.cleanupLevel, .light, "cleanupLevel must persist across instances.")
    }

    // MARK: - Enum invariants

    func testAllStylesAndLevelsHaveNonEmptyDisplayNames() {
        XCTAssertEqual(CleanupStyle.allCases.count, 5, "Five voices: Default/Professional/Casual/Code/Email.")
        // W4.1: CleanupLevel is now a 4-level scale (None/Light/Medium/High).
        XCTAssertEqual(CleanupLevel.allCases.count, 4, "Four levels: None/Light/Medium/High (W4.1 transparency moat).")
        for style in CleanupStyle.allCases {
            XCTAssertFalse(style.displayName.isEmpty, "\(style) must have a display name.")
        }
        for level in CleanupLevel.allCases {
            XCTAssertFalse(level.displayName.isEmpty, "\(level) must have a display name.")
        }
    }

    // MARK: - Prompt composition (no live model)

    @available(macOS 26.0, *)
    func testStyledInstructionsAreNonEmptyForEveryCombination() {
        for style in CleanupStyle.allCases {
            for level in CleanupLevel.allCases {
                let prompt = FoundationModelsCleaner.styledInstructions(style: style, level: level)
                XCTAssertFalse(prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                               "styledInstructions(\(style), \(level)) must be non-empty.")
                XCTAssertTrue(prompt.contains("Return only"),
                              "Every prompt must keep the no-commentary footer.")
            }
        }
    }

    @available(macOS 26.0, *)
    func testDistinctVoicesProduceDistinctPrompts() {
        let level = CleanupLevel.medium   // W4.1: .balanced → .medium
        let prompts = CleanupStyle.allCases.map {
            FoundationModelsCleaner.styledInstructions(style: $0, level: level)
        }
        // All five voices must yield different instruction strings.
        XCTAssertEqual(Set(prompts).count, CleanupStyle.allCases.count,
                       "Each voice must compose a distinct prompt — no two styles collapse.")
    }

    @available(macOS 26.0, *)
    func testCodeVoicePreservesIdentifiersInstruction() {
        let prompt = FoundationModelsCleaner.styledInstructions(style: .code, level: .medium)   // W4.1: .balanced → .medium
        XCTAssertTrue(prompt.lowercased().contains("identifier"),
                      "The Code voice must instruct the model to preserve technical identifiers.")
    }

    // W4.1: renamed from testThoroughLevelIsMoreAggressiveThanBasic
    // (.basic/.thorough → .light/.high in the 4-level scale)
    @available(macOS 26.0, *)
    func testHighLevelIsMoreAggressiveThanLight() {
        let light = FoundationModelsCleaner.styledInstructions(style: .default, level: .light)
        let high = FoundationModelsCleaner.styledInstructions(style: .default, level: .high)
        XCTAssertNotEqual(light, high, "Light and High must compose different intensity clauses.")
        XCTAssertTrue(light.lowercased().contains("light touch"),
                      "Light must describe a light-touch edit.")
        // High must mention restructuring or paragraph (the distinguishing addition).
        let highLower = high.lowercased()
        XCTAssertTrue(highLower.contains("restructure") || highLower.contains("paragraph"),
                      "High must describe restructuring or paragraph breaks.")
    }

    // MARK: - .styled routes through instructions(for:)

    @available(macOS 26.0, *)
    func testInstructionsForStyledModeMatchesStyledInstructions() {
        // W4.1: use .high instead of removed .thorough
        let viaMode = FoundationModelsCleaner.instructions(for: .styled(.professional, .high))
        let direct = FoundationModelsCleaner.styledInstructions(style: .professional, level: .high)
        XCTAssertEqual(viaMode, direct,
                       "instructions(for: .styled(...)) must delegate to styledInstructions.")
    }

    // MARK: - Command Mode (Wave D) prompt core

    @available(macOS 26.0, *)
    func testCommandInstructions_embedsInstructionAndFooter() {
        let prompt = FoundationModelsCleaner.commandInstructions(instruction: "  make this more concise  ")
        XCTAssertTrue(prompt.contains("make this more concise"),
                      "The spoken instruction must be embedded (trimmed) in the prompt.")
        XCTAssertTrue(prompt.contains("return ONLY") || prompt.contains("ONLY"),
                      "Command prompt must constrain output to only the result.")
    }

    @available(macOS 26.0, *)
    func testInstructionsForCommandModeRoutesToCommandInstructions() {
        let viaMode = FoundationModelsCleaner.instructions(for: .command(instruction: "translate to Polish"))
        let direct = FoundationModelsCleaner.commandInstructions(instruction: "translate to Polish")
        XCTAssertEqual(viaMode, direct,
                       "instructions(for: .command(...)) must delegate to commandInstructions.")
    }
}
