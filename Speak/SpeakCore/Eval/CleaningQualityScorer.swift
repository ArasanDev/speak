// SpeakCore/Eval/CleaningQualityScorer.swift
//
// `#if DEBUG`: eval-only scoring, consumed by SpeakTests which always builds
// SpeakCore in Debug — kept out of release binaries [audit fix].
#if DEBUG
//
// Reference-free scoring of a raw→cleaned dictation pair. The primary use case
// is evaluating real history rows (HistoryEntry.rawText / .cleanedText), which
// have no human-authored "expected" text — so we score over-editing and cleanup
// hygiene structurally rather than against a reference.
//
// Over-editing is measured by content retention: how much of the raw transcript
// (minus legitimately-removed filler words) survives in the cleaned output. A
// model that paraphrases, condenses, or drops words scores low. The other gates
// catch the classic small-model cleanup failures: filler left in, hallucinated
// identifiers, preamble chatter, and an implausibly large content shrink.

import Foundation

// MARK: - CleaningQualityReport

/// Result of scoring one raw→cleaned pair.
public struct CleaningQualityReport: Equatable {
    /// Jaccard similarity between the cleaned output and the raw transcript with
    /// filler words removed. 1.0 = every non-filler raw word survived; low = over-editing.
    public let contentRetention: Double

    /// `true` when no common filler word remains in the cleaned output.
    public let fillerRemoved: Bool

    /// `true` when no identifier-like token in the output is ungrounded in the raw text.
    public let noHallucinatedIdentifiers: Bool

    /// `true` when the output does not start with assistant chatter and is not wholly quoted.
    public let noPreamble: Bool

    /// cleanedTokenCount / rawTokenCount. A large drop is an over-editing signal;
    /// values near 1.0 mean the edit was conservative.
    public let lengthRatio: Double

    /// The names of the gates that failed. Empty when `passed` is true.
    public let failedChecks: [String]

    /// `true` iff every gate passes.
    public var passed: Bool { failedChecks.isEmpty }
}

// MARK: - Filler vocabulary

/// Filler tokens whose removal is legitimate and therefore must not count against
/// content retention. These mirror the model prompts' filler guidance and are
/// treated leniently: stripping them from the raw side avoids penalizing a
/// legitimate filler removal, while real words are still retained. [decision]
private let strippableFillers: Set<String> = [
    "um", "uh", "like", "hmm", "okay", "basically"
]

/// Unambiguous spoken disfluencies that should NEVER survive cleanup. These are
/// the only tokens checked by the `fillerRemoved` gate, so a legitimate word such
/// as "like" ("I like this") or "okay" ("Okay, let's proceed") is not a false
/// positive. [decision]
private let hardDisfluencies: Set<String> = [
    "um", "uh", "hmm", "er", "ah"
]

// MARK: - Tokenization helpers

/// Lowercased, whitespace-split, edge-punctuation-normalized word tokens.
private func wordTokens(_ text: String) -> [String] {
    let edgePunctuation = CharacterSet(charactersIn: ".,;:!?\"'`()[]{}…")
    return text
        .lowercased()
        .split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" || $0 == "\r" })
        .map { String($0).trimmingCharacters(in: edgePunctuation) }
        .filter { !$0.isEmpty }
}

private func tokenCount(_ text: String) -> Int {
    wordTokens(text).count
}

/// Remove strippable filler tokens from `text` and return a normalized, single-spaced
/// string. Kept deterministic and side-effect-free; feeding this to
/// `correctness(_:expected:)` gives the over-editing detector without penalizing
/// legitimate filler removal.
public func fillerStrippedTokens(_ text: String) -> String {
    wordTokens(text).filter { !strippableFillers.contains($0) }.joined(separator: " ")
}

// MARK: - Filler detection

/// Word-boundary hard-disfluency check for the `fillerRemoved` gate. Unlike
/// `BuiltInFormatChecks.noFiller` (substring `contains`), this tokenizes so that
/// "um"/"uh" do not false-positive inside real words, and it checks only
/// unambiguous disfluencies so legitimate "like"/"okay" usage passes.
private func containsHardDisfluency(_ text: String) -> Bool {
    wordTokens(text).contains { hardDisfluencies.contains($0) }
}

/// Detects the assistant-chatter patterns a small cleanup model emits when it
/// mistakes an edit for a conversational turn. Also rejects whole-output quoting.
private func isPreamble(_ text: String) -> Bool {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return true }

    let lower = trimmed.lowercased()
    let prefixes = [
        "here is", "here's", "sure", "i've cleaned", "i have cleaned",
        "here you go", "your cleaned", "cleaned text", "the cleaned"
    ]
    if prefixes.contains(where: { lower.hasPrefix($0) }) {
        return true
    }

    // Whole-output wrapping quotes: a model that returns "\"transcript text\"".
    if trimmed.count >= 2,
       trimmed.first == "\"",
       trimmed.last == "\"",
       !trimmed.dropFirst().dropLast().contains("\"") {
        return true
    }

    return false
}

// MARK: - Scoring

/// Score a raw→cleaned pair without a reference.
///
/// - Parameters:
///   - raw: The raw transcript as stored in `HistoryEntry.rawText`.
///   - cleaned: The model's cleaned output (`HistoryEntry.cleanedText`).
/// - Returns: A `CleaningQualityReport` with per-gate results and a combined pass flag.
public func scoreCleaning(raw: String, cleaned: String) -> CleaningQualityReport {
    let fillerStripped = fillerStrippedTokens(raw)

    let retention = correctness(output: cleaned, expected: fillerStripped)

    let fillerRemoved = !containsHardDisfluency(cleaned)

    let noHallucinated = noUnspokenIdentifiers(output: cleaned, spoken: raw)
    let noPreamble = !isPreamble(cleaned)

    let rawCount = tokenCount(raw)
    let cleanedCount = tokenCount(cleaned)
    let lengthRatio = rawCount == 0 ? 1.0 : Double(cleanedCount) / Double(rawCount)

    // Thresholds traced to benchmark.md §7 [decision]: content retention must stay
    // high for a cleanup transform (0.80 Jaccard), and a >40% token drop means the
    // model condensed rather than cleaned. Guard against a raw==cleaned empty pair.
    let retentionPass = retention >= 0.80
    let lengthPass = lengthRatio >= 0.60

    var failed: [String] = []
    if !retentionPass { failed.append("contentRetention") }
    if !fillerRemoved { failed.append("fillerRemoved") }
    if !noHallucinated { failed.append("noHallucinatedIdentifiers") }
    if !noPreamble { failed.append("noPreamble") }
    if !lengthPass { failed.append("lengthRatio") }

    return CleaningQualityReport(
        contentRetention: retention,
        fillerRemoved: fillerRemoved,
        noHallucinatedIdentifiers: noHallucinated,
        noPreamble: noPreamble,
        lengthRatio: lengthRatio,
        failedChecks: failed
    )
}

#endif
