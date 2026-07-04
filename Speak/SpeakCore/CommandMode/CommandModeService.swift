// SpeakCore/CommandMode/CommandModeService.swift
//
// The orchestration core of Command Mode (Wave D): given the user's highlighted
// selection and a spoken instruction, run the on-device LLM transform and replace the
// selection with the result.
//
//     read selection ──► clean(selection, .command(instruction)) ──► replace selection
//
// This type is PURE orchestration over injected seams, so it is fully unit-testable
// without the Accessibility API or a live model:
//   - `SelectionAccessing` abstracts reading/replacing the frontmost app's selection.
//     The live AX implementation lives in the App layer (AXUIElement) and is
//     [deferred — human verification]; tests inject a mock.
//   - `LLMCleaning` is the same on-device cleaner used for dictation cleanup; the
//     `.command(instruction:)` mode (verified by StyleModeTests) carries the instruction.
//
// CONTRACT:
//   - Empty/blank selection → no-op (returns `.noSelection`); nothing is overwritten.
//   - Cleaner unavailable → no-op (returns `.modelUnavailable`); selection left intact
//     (we must never blank a user's selection just because the model is off).
//   - Success → selection replaced; returns `.replaced(result)`.

import Foundation

// MARK: - SelectionAccessing

/// Reads and replaces the current text selection in the frontmost application.
/// The live implementation (App layer) uses the Accessibility API; it is
/// [deferred — human verification] because AX behavior depends on the target app +
/// granted permissions. Tests inject a mock.
public protocol SelectionAccessing: Sendable {
    /// The current selected text in the focused element, or `nil` when there is none.
    func readSelectedText() throws -> String?
    /// Replace the current selection with `text`.
    func replaceSelectedText(with text: String) throws
}

// MARK: - CommandModeOutcome

public enum CommandModeOutcome: Sendable, Equatable {
    case replaced(String)
    case noSelection
    case modelUnavailable
}

// MARK: - CommandModeService

public struct CommandModeService: Sendable {

    private let selection: any SelectionAccessing
    private let cleaner: any LLMCleaning

    public init(selection: any SelectionAccessing, cleaner: any LLMCleaning) {
        self.selection = selection
        self.cleaner = cleaner
    }

    /// Apply `instruction` to the current selection on-device and replace it with the
    /// result. See the type contract for the no-op cases.
    @discardableResult
    public func run(instruction: String) async throws -> CommandModeOutcome {
        guard let selected = try selection.readSelectedText(),
              !selected.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            SpeakLog.engine.info("CommandMode: no selection — no-op.")
            return .noSelection
        }
        guard await cleaner.isAvailable else {
            // Never blank the selection because the model is unavailable.
            SpeakLog.engine.info("CommandMode: model unavailable — leaving selection intact.")
            return .modelUnavailable
        }
        let result = try await cleaner.clean(selected, mode: .command(instruction: instruction))
        try selection.replaceSelectedText(with: result)
        SpeakLog.engine.info(
            "CommandMode: replaced selection (\(selected.count, privacy: .public) → \(result.count, privacy: .public) chars)."
        )
        return .replaced(result)
    }
}
