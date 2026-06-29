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
    ///   - intensity: cross-profile rewrite intensity (default: .medium).
    ///   - category: Agent-specific sub-category (ignored for non-Agent profiles).
    ///   - customVocabulary: proper-noun spellings to preserve verbatim.
    /// - Returns: the full prompt string, or — for the `.raw` model — the
    ///   transcript unchanged (the base-core passthrough; never an error).
    public static func build(
        profile: Profile,
        rawTranscript: String,
        context: [ContextInput: String] = [:],
        intensity: CleanupLevel = .medium,
        category: AgentCategory = .task,
        customVocabulary: [String] = []
    ) -> String {
        // Base-core bypass: the Raw profile passes the transcript through untouched.
        // No prompt is assembled — this is the immutable floor (profile-engine.md §2).
        if case .raw = profile.model {
            return rawTranscript
        }
        // Single-prompt assembly: instructions + the dictated speech, last.
        let instr = instructions(
            profile: profile, intensity: intensity, category: category,
            customVocabulary: customVocabulary, context: context
        )
        return instr + "\n\nDictated speech:\n" + rawTranscript
    }

    /// The instruction block for `profile` — system prompt + category fragment (if Agent) +
    /// knob clauses + intensity + preserved-vocabulary + injected context + few-shot examples,
    /// WITHOUT the transcript. Used by instruction/prompt-separated models: e.g.
    /// `FoundationModelsCleaner` feeds this as the session instructions and the
    /// transcript (XML-wrapped) as the prompt.
    ///
    /// - intensity: how aggressively to rewrite (the cross-profile modifier carried
    ///   from the user's cleanup-level setting). `.medium` is the baseline and adds
    ///   NO clause; `.none` is unreachable here (cleaner is bypassed) and also adds none.
    /// - category: Agent-specific sub-category (only appended if profile is Agent destination).
    /// - customVocabulary: proper nouns / specialist spellings to preserve verbatim.
    public static func instructions(
        profile: Profile,
        intensity: CleanupLevel = .medium,
        category: AgentCategory = .task,
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

        // For Agent categories that define their own output format (commit, shell, code),
        // the Agent profile's task-format few-shot examples contaminate the output: the
        // model copies the task-form examples rather than following the category fragment.
        // Suppressing the examples for these categories leaves the category fragment as
        // the sole format anchor, which is sufficient. For task/fix/ask — which share the
        // task prose format — keep the examples for stronger anchoring. [decision SM-2 round 4]
        let shouldShowProfileExamples: Bool
        if profile.id == DefaultProfiles.agent.id {
            switch category {
            case .commit, .shell, .code:
                shouldShowProfileExamples = false
            case .task, .fix, .ask:
                shouldShowProfileExamples = true
            }
        } else {
            shouldShowProfileExamples = true
        }
        if shouldShowProfileExamples, let shots = fewShot(profile.examples) {
            sections.append(shots)
        }

        // Append the category fragment LAST — after the few-shot examples (when shown) —
        // so it is the freshest instruction before the transcript. For task/fix/ask the
        // fragment comes after the task-format examples (reinforcing them); for
        // commit/shell/code the examples are suppressed so the fragment is the sole anchor.
        // [decision SM-2 round 4: verified empirically — commit category copied task-form
        // few-shot examples when fragment appeared before them]
        if profile.id == DefaultProfiles.agent.id, let categoryFragment = categoryFragment(category) {
            sections.append(categoryFragment)
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

    /// The Agent-category fragment appended to the Agent system prompt.
    /// [decision] One short imperative line per category (PT-1 spec).
    static func categoryFragment(_ category: AgentCategory) -> String? {
        switch category {
        case .task:
            return "Focus on a concrete implementation task or refactoring request."

        case .fix:
            // [decision SM-2] "structure clearly" caused model to propose solutions (confirmed empirically).
            // Must explicitly prohibit fix proposals.
            return "Output ONLY a structured bug report: state what is broken and where. Do not propose a fix or suggest a solution."

        case .ask:
            // [decision SM-2] Force question form. Small models default to task format
            // for Agent profile. Must preserve the speaker's question word (empirically,
            // model changes "what's the best way" → task form without this constraint).
            // [decision SM-2 round 4] "what's the best way" questions cause model to output
            // an implementation answer (RLHF override). Added explicit prohibition: even
            // advice-seeking questions ("what's the best way", "what would you recommend")
            // must be kept as questions, never answered.
            return "Output ONLY the question text — nothing else. Keep the exact question word from the input "
                + "(How, What, Why, What's, etc.). End with '?'. Do NOT answer, implement, suggest, or provide "
                + "the best way to do anything — even if the question asks for advice. "
                + "Your only job: clean the spoken question into a well-formed question ending with '?'."

        case .commit:
            // [decision SM-2] Add inline examples + lowercase-type requirement. Model capitalised
            // "Fix:" (confirmed empirically); must specify lowercase. Two examples anchor the pattern.
            // [decision SM-2 round 4] Changed example from "fix: paste fails on retry" to a neutral
            // one — model was copying the example verbatim when the fixture input resembled it.
            // Also added explicit type-inference guidance for "docs:" (empirically: model omitted type
            // prefix for spec/documentation additions without this rule).
            return "Output ONLY a Conventional Commits message in the format 'type: imperative-summary' "
                + "(lowercase type, no trailing period). Use imperative present tense in the summary "
                + "(e.g., 'add', 'fix', 'update' — not 'added', 'fixed'). Derive the summary from the spoken input. "
                + "Type rules: 'fix' for bug fixes only; 'docs' for any file that documents something "
                + "(specs, READMEs, guides, system prompts) — NOT 'feat'; 'feat' for new product features; "
                + "'refactor' for code cleanup; 'test' for test additions; 'chore' for tooling. "
                + "Format example (shows format only): 'fix: crash on photo import'. No prose, no preamble."

        case .shell:
            // [decision SM-2] Explicit flag-mapping hints + combined-flags rule. Empirically:
            // without hints model outputs prose; with -a hint but not -m model omits message flag;
            // 'ls -a -l' not combined without explicit instruction.
            // [decision SM-2 round 4] Added "no markdown fences, no code blocks": model wraps in
            // ```bash when category fragment appears after the few-shot examples in context.
            return "Output ONLY the exact shell command as plain text — no markdown fences, no code blocks, "
                + "no prose, no explanation, no trailing punctuation. "
                + "Translate: 'all/hidden files' → '-a', 'long format' → '-l'. "
                + "When both apply, combine as '-la' (l first, then a — always this order). "
                + "When committing with -a and -m flags, combine them as -am and quote the message string."

        case .code:
            // [decision SM-2] Explicit "no markdown fences", camelCase, no spaces around parens,
            // "output ALL lines". Empirically: model added ``` fences, used snake_case, truncated
            // multi-statement expressions after the first line.
            // [decision SM-2 round 4] Model outputs "foo ( )" with spaces inside parens despite
            // "no spaces around parentheses." Added explicit translation pair so the mapping is
            // unambiguous: "open paren close paren" → "()" (zero spaces, one token).
            return "Output ONLY the raw code — no prose, no sentences, no markdown fences. "
                + "Use camelCase identifiers (userName, not user_name). "
                + "Translate all spoken notation: 'equals' → '=', 'dot' → '.', "
                + "'open paren close paren' → '()' (zero spaces, one token), "
                + "'open paren' → '(', 'close paren' → ')'. "
                + "Output ALL lines and ALL parts of the expression."
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
