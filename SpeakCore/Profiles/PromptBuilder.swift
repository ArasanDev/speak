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
        context: [ContextInput: String] = [:],
        intensity: CleanupLevel = .medium,
        customVocabulary: [String] = []
    ) -> String {
        // Base-core bypass: the Raw profile passes the transcript through untouched.
        // No prompt is assembled — this is the immutable floor (profile-engine.md §2).
        if case .raw = profile.model {
            return rawTranscript
        }
        // Single-prompt assembly: instructions + the dictated speech, last.
        let instr = instructions(
            profile: profile, intensity: intensity,
            customVocabulary: customVocabulary, context: context
        )
        return instr + "\n\nDictated speech:\n" + rawTranscript
    }

    /// The instruction block for `profile` — system prompt + knob clauses +
    /// intensity + preserved-vocabulary + injected context + few-shot examples,
    /// WITHOUT the transcript. Used by instruction/prompt-separated models: e.g.
    /// `FoundationModelsCleaner` feeds this as the session instructions and the
    /// transcript (XML-wrapped) as the prompt.
    ///
    /// - intensity: how aggressively to rewrite (the cross-profile modifier carried
    ///   from the user's cleanup-level setting). `.medium` is the baseline and adds
    ///   NO clause; `.none` is unreachable here (cleaner is bypassed) and also adds none.
    /// - customVocabulary: proper nouns / specialist spellings to preserve verbatim.
    public static func instructions(
        profile: Profile,
        intensity: CleanupLevel = .medium,
        customVocabulary: [String] = [],
        context: [ContextInput: String] = [:]
    ) -> String {
        var sections: [String] = []
        if !profile.systemPrompt.isEmpty {
            sections.append(profile.systemPrompt)
        }

        // Knob clauses (each empty for its default case → appended only when
        // meaningful, so a small model never sees a no-op instruction).
        let knobClauses = [
            formatClause(profile.format),
            toneClause(profile.tone),
            lengthClause(profile.length),
            intensityClause(intensity)
        ].compactMap { $0 }
        if !knobClauses.isEmpty {
            sections.append(knobClauses.joined(separator: "\n"))
        }

        if let vocab = vocabularyClause(customVocabulary) {
            sections.append(vocab)
        }
        if let injected = injectedContext(profile.contextInputs, values: context) {
            sections.append(injected)
        }
        if let shots = fewShot(profile.examples) {
            sections.append(shots)
        }

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

    /// The cross-profile rewrite-intensity clause (carried from the user's cleanup
    /// level). `.medium` is the baseline → no clause; `.none` is unreachable here
    /// (the cleaner is bypassed when level is none) → no clause. [decision] wording
    /// mirrors the styled() ladder so behavior is consistent across both paths.
    static func intensityClause(_ level: CleanupLevel) -> String? {
        switch level {
        case .none, .medium:
            return nil
        case .light:
            return "Make only light edits: fix punctuation and capitalization and remove "
                + "obvious filler words; otherwise keep the speaker's words and structure intact."
        case .high:
            return "Rewrite thoroughly: tighten phrasing, remove redundancy, and restructure "
                + "into clear paragraphs where appropriate, preserving the speaker's meaning."
        }
    }

    /// Preserve-spellings clause for the user's custom dictionary. Empty list → nil.
    /// [decision] 50-term cap matches FoundationModelsCleaner.styledInstructions — the
    /// system-prompt budget for a small on-device model.
    static func vocabularyClause(_ terms: [String]) -> String? {
        let cleaned = terms.filter { !$0.isEmpty }
        guard !cleaned.isEmpty else { return nil }
        let list = cleaned.prefix(50).map { "\"\($0)\"" }.joined(separator: ", ")
        return "Preserve these terms exactly as spelled, including capitalization: \(list)."
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
