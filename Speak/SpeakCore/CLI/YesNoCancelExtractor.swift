// SpeakCore/CLI/YesNoCancelExtractor.swift
//
// H-3 (specs/horizon-voice-os.md Pillar 3): deterministic yes/no/cancel extraction
// for `speak_confirm`. No LLM call — a pure function, table-driven, so the result is
// reproducible and auditable. [decision: H-3]
//
// Normalization: lowercase, trim whitespace, strip punctuation, collapse internal
// whitespace runs to a single space — then exact-match the normalized string against
// three phrase lists. Anything that doesn't match any list is `.unclear`: we never
// guess a yes/no from an ambiguous or unrecognized answer.

import Foundation

/// The deterministic outcome of matching a spoken answer against the yes/no/cancel
/// phrase lists. `.unclear` is a first-class outcome, not an error — the caller
/// (`DictationController.cliConfirm`, `CLIPortServer`) decides how to surface it.
public enum YesNoCancelResult: String, Sendable, Equatable {
    case yes
    case no
    case cancel
    case unclear
}

/// Pure phrase-list matcher — no I/O, no LLM, safe to unit test exhaustively.
public enum YesNoCancelExtractor {

    /// [decision: H-3 — phrase lists per the horizon-voice-os spec's tool contract]
    private static let yesPhrases: Set<String> = [
        "yes", "yeah", "yep", "sure", "correct", "affirmative", "right", "okay", "ok"
    ]

    private static let noPhrases: Set<String> = [
        "no", "nope", "negative", "nah", "not really"
    ]

    private static let cancelPhrases: Set<String> = [
        "cancel", "never mind", "nevermind", "stop", "forget it"
    ]

    /// Extract a deterministic yes/no/cancel from a raw spoken-answer transcript.
    /// Empty or whitespace-only input is `.unclear`.
    public static func extract(_ rawAnswer: String) -> YesNoCancelResult {
        let normalized = normalize(rawAnswer)
        guard !normalized.isEmpty else { return .unclear }

        if cancelPhrases.contains(normalized) { return .cancel }
        if yesPhrases.contains(normalized) { return .yes }
        if noPhrases.contains(normalized) { return .no }
        return .unclear
    }

    /// lowercase → trim → strip punctuation → collapse whitespace runs.
    /// Not `private` — `RequestInputExtractor` (AVB-5) reuses it for `.choice`
    /// mode's option matching so the two extractors stay byte-for-byte
    /// consistent about what "the same normalized word" means. [decision: AVB-5]
    static func normalize(_ raw: String) -> String {
        let lowered = raw.lowercased()
        let strippedPunctuation = String(lowered.unicodeScalars.filter { scalar in
            !CharacterSet.punctuationCharacters.contains(scalar)
        })
        let words = strippedPunctuation
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
        return words.joined(separator: " ")
    }
}
