// SpeakCore/Profiles/PromptBuilder.swift
//
// The PromptBuilder — a PURE, deterministic assembler that turns a `Profile` +
// a raw transcript into the final prompt sent to the model (specs/profile-engine.md
// §2.2). The system prompt is the engine; the structured knobs are conveniences
// that only ADD clauses — they never override an explicit system prompt. This
// keeps "sensible defaults, infinite ceiling" true at the data-model level.
//
// PURITY: no I/O, no Date/random, no global state — same inputs always produce
// the same output. This is what makes it unit-testable and is the contract the
// small-models eval harness (#40) depends on.
//
// SMALL-MODEL DESIGN (profile-engine.md §6): clauses are short + imperative; the
// default knob cases (asIs / neutral / preserve) add NOTHING so we never dilute
// the model's attention with no-op instructions. Few-shot examples come last
// before the dictated speech — the strongest steering lever for a ~3B model.

import Foundation

// MARK: - PromptBuilder

public enum PromptBuilder {

    /// Assemble the final prompt for `profile` over `rawTranscript`.
    ///
    /// - Parameters:
    ///   - profile: the active profile (its systemPrompt + knobs + examples).
    ///   - rawTranscript: the dictated speech (already snippet-expanded upstream).
    ///   - context: values for the profile's `contextInputs` (selection, clipboard,
    ///     current file, app name). Only inputs that are BOTH in the profile's
    ///     `contextInputs` set AND present here are injected. Default: none.
    /// - Returns: the full prompt string, or — for the `.raw` model — the
    ///   transcript unchanged (the base-core passthrough; never an error).
    public static func build(
        profile: Profile,
        rawTranscript: String,
        context: [ContextInput: String] = [:]
    ) -> String {
        // Base-core bypass: the Raw profile passes the transcript through untouched.
        // No prompt is assembled — this is the immutable floor (profile-engine.md §2).
        if case .raw = profile.model {
            return rawTranscript
        }

        // Section 1: the system prompt (the editable heart).
        var sections: [String] = [profile.systemPrompt]

        // Section 2: knob clauses (each empty for its default case → appended only
        // when meaningful, so a small model never sees a no-op instruction).
        let knobClauses = [
            formatClause(profile.format),
            toneClause(profile.tone),
            lengthClause(profile.length)
        ].compactMap { $0 }
        if !knobClauses.isEmpty {
            sections.append(knobClauses.joined(separator: "\n"))
        }

        // Section 3: injected context (only inputs requested AND provided).
        if let injected = injectedContext(profile.contextInputs, values: context) {
            sections.append(injected)
        }

        // Section 4: few-shot examples (the strongest small-model lever).
        if let shots = fewShot(profile.examples) {
            sections.append(shots)
        }

        // Section 5: the dictated speech, always last.
        sections.append("Dictated speech:\n" + rawTranscript)

        // Blank line between sections keeps the structure legible to the model.
        return sections.joined(separator: "\n\n")
    }

    // MARK: - Knob clauses
    //
    // [decision] Clause wording is short + imperative (profile-engine.md §6 rule 1).
    // These are starting points tuned by the eval harness (#40), not law. The
    // default case of each knob returns nil → contributes nothing to the prompt.

    static func formatClause(_ format: OutputFormat) -> String? {
        switch format {
        case .asIs:      return nil
        case .paragraph: return "Format the result as flowing prose paragraphs."
        case .bullets:   return "Format the result as a bulleted list."
        case .numbered:  return "Format the result as a numbered list."
        case .codeBlock: return "Format the result as a single code block."
        case .verbatim:  return "Output the words verbatim; only fix obvious transcription errors."
        }
    }

    static func toneClause(_ tone: Tone) -> String? {
        switch tone {
        case .neutral: return nil
        case .terse:   return "Use a terse style."
        case .formal:  return "Use a formal tone."
        case .casual:  return "Use a casual tone."
        }
    }

    static func lengthClause(_ length: LengthBias) -> String? {
        switch length {
        case .preserve: return nil
        case .condense: return "Be more concise than the input."
        case .expand:   return "Add helpful detail while preserving the original meaning."
        }
    }

    // MARK: - Context injection

    /// Build a labeled context block from the inputs the profile requests AND that
    /// the caller supplied a value for. Returns nil when nothing applies.
    /// [decision] Stable label order (the enum's `allCases`) for deterministic output.
    static func injectedContext(
        _ inputs: Set<ContextInput>,
        values: [ContextInput: String]
    ) -> String? {
        let lines: [String] = ContextInput.allCases.compactMap { input in
            guard inputs.contains(input), let value = values[input], !value.isEmpty else {
                return nil
            }
            return "\(label(for: input)):\n\(value)"
        }
        return lines.isEmpty ? nil : lines.joined(separator: "\n\n")
    }

    private static func label(for input: ContextInput) -> String {
        switch input {
        case .selection:   return "Selected text"
        case .clipboard:   return "Clipboard"
        case .currentFile: return "Current file"
        case .appName:     return "Active app"
        }
    }

    // MARK: - Few-shot

    /// Render the examples as labeled Input/Output pairs. Returns nil when empty.
    /// [decision] "Input:/Output:" framing is compact and unambiguous for a small model.
    static func fewShot(_ examples: [Example]) -> String? {
        guard !examples.isEmpty else { return nil }
        let blocks = examples.map { "Input: \($0.spoken)\nOutput: \($0.written)" }
        return "Examples:\n" + blocks.joined(separator: "\n\n")
    }
}
