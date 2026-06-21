// SpeakCore/Snippets/SnippetExpander.swift
//
// Expands snippet triggers in a transcript BEFORE the LLM cleanup pass. Injected into
// `CaptureSession` (optional — nil means no expansion, all prior behavior unchanged).
//
// Matching rule: whole-word, case-insensitive. A trigger only matches when bounded by
// non-word characters (or string ends), so "addr" won't fire inside "address". The
// expansion is substituted verbatim. Running BEFORE cleanup means the LLM smooths any
// seams the expansion introduces. Pure + Sendable so the actor can use it freely.

import Foundation

// MARK: - SnippetExpanding

public protocol SnippetExpanding: Sendable {
    /// Return `text` with every snippet trigger replaced by its expansion.
    func expand(_ text: String) -> String
}

// MARK: - SnippetExpander

public struct SnippetExpander: SnippetExpanding {

    private let snippets: [Snippet]

    public init(snippets: [Snippet]) {
        // Longer triggers first so a longer trigger wins over a shorter prefix overlap.
        self.snippets = snippets.sorted { $0.trigger.count > $1.trigger.count }
    }

    public func expand(_ text: String) -> String {
        guard !snippets.isEmpty, !text.isEmpty else { return text }
        var result = text
        for snippet in snippets {
            let trigger = snippet.trigger.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trigger.isEmpty else { continue }
            result = Self.replaceWholeWords(of: trigger, with: snippet.expansion, in: result)
        }
        return result
    }

    // MARK: - Whole-word replacement

    /// Replace whole-word, case-insensitive occurrences of `trigger` with `replacement`.
    /// Uses a regex word boundary built from the escaped trigger so partial matches
    /// inside larger words are not replaced.
    private static func replaceWholeWords(of trigger: String, with replacement: String, in text: String) -> String {
        let escaped = NSRegularExpression.escapedPattern(for: trigger)
        // \b doesn't work for triggers ending in non-word chars, so bound on word edges
        // around an alphanumeric trigger; fall back to a plain pattern otherwise.
        let pattern = "\\b\(escaped)\\b"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return text
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        // Escape `$` and `\` in the replacement so they're treated literally, not as
        // regex template references.
        let template = NSRegularExpression.escapedTemplate(for: replacement)
        return regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: template)
    }
}
