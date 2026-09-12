// SpeakCore/Vocabulary/AcousticCorrection.swift
//
// The "acoustic slips" table: what the recognizer hears → what should be typed.
// Distinct from `customVocabulary` (contextual hints to the recognizer) and
// `Snippet` (deliberate trigger → expansion): a correction maps a *mishearing*
// ("rippo", "cubectl", "darker") back to ground truth ("repo", "kubectl",
// "docker") so the error never reaches the document.
//
// Two consumption points:
//   1. `AcousticCorrectionExpander` — a `SnippetExpanding` conformer applied to
//      the raw transcript before snippet expansion and the LLM pass.
//   2. `SettingsStore.effectiveVocabulary` — the `typed` terms are merged into
//      the vocabulary sent to SpeechAnalyzer contextualStrings and the
//      Foundation Models prompt normalizer.
//
// Persisted as Codable JSON in `SettingsStore.acousticCorrections`.

import Foundation

// MARK: - AcousticCorrection

/// One acoustic-slip mapping: `heard` is what STT produces, `typed` is the
/// ground-truth text that should appear instead.
public struct AcousticCorrection: Codable, Sendable, Equatable, Hashable, Identifiable {
    /// Identity is the normalized heard form — one row per distinct slip.
    public var id: String { heard.lowercased() }

    /// What the recognizer hears (e.g. "rippo").
    public let heard: String
    /// What gets typed (e.g. "repo").
    public let typed: String

    public init(heard: String, typed: String) {
        self.heard = heard
        self.typed = typed
    }
}

// MARK: - AcousticCorrections (edit rules)

/// Pure, testable edit logic for the acoustic-corrections table — mirrors
/// `CustomVocabulary`'s rules so both editors behave identically.
///
/// Rules:
///   - upsert: trim both fields; ignore when either is blank; case-insensitive
///     match on `heard` replaces the existing row's `typed` value in place;
///     otherwise append (most-recent last).
///   - remove: delete every case-insensitive `heard` match.
public enum AcousticCorrections {

    /// Built-in slips seeded for every install — common recognizer manglings
    /// of the product/tool names in `AppleSpeechTranscriber.developerTerms`.
    /// `defaultExpander` merges these under user entries so a user's explicit
    /// `heard` always wins (incl. an identity row to disable a built-in).
    /// [evidence: live dictation 2026-09-12 — Claude Code→"cloth code",
    ///  Codex→"codecs"]
    public static let builtIn: [AcousticCorrection] = [
        AcousticCorrection(heard: "cloth code", typed: "Claude Code"),
        AcousticCorrection(heard: "clod code", typed: "Claude Code"),
        AcousticCorrection(heard: "cloud code", typed: "Claude Code"),
        AcousticCorrection(heard: "codecs", typed: "Codex"),
        AcousticCorrection(heard: "chat gpt", typed: "ChatGPT"),
        AcousticCorrection(heard: "whisper flow", typed: "Wispr Flow"),
        AcousticCorrection(heard: "whisperflow", typed: "Wispr Flow"),
        AcousticCorrection(heard: "devin", typed: "Devin"),
        AcousticCorrection(heard: "ollama", typed: "Ollama"),
        AcousticCorrection(heard: "whisper kit", typed: "WhisperKit"),
        AcousticCorrection(heard: "swift ui", typed: "SwiftUI"),
        AcousticCorrection(heard: "open ai", typed: "OpenAI"),
    ]

    /// Insert or update the correction for `heard`. A re-add of an existing
    /// `heard` (any case) updates its `typed` value in place rather than
    /// duplicating the row.
    public static func upsert(
        heard: String,
        typed: String,
        in list: [AcousticCorrection]
    ) -> [AcousticCorrection] {
        let h = heard.trimmingCharacters(in: .whitespacesAndNewlines)
        let t = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !h.isEmpty, !t.isEmpty else { return list }
        let corrected = AcousticCorrection(heard: h, typed: t)
        if let index = list.firstIndex(where: {
            $0.heard.caseInsensitiveCompare(h) == .orderedSame
        }) {
            var next = list
            next[index] = corrected
            return next
        }
        return list + [corrected]
    }

    /// Returns a new list with every case-insensitive `heard` match removed.
    public static func removing(
        heard: String,
        from list: [AcousticCorrection]
    ) -> [AcousticCorrection] {
        list.filter { $0.heard.caseInsensitiveCompare(heard) != .orderedSame }
    }
}
