// SpeakCore/Vocabulary/CustomVocabulary.swift
//
// Pure, testable edit logic for the custom-vocabulary term list (the Dictionary pane).
// The persisted list lives in `SettingsStore.customVocabulary` ([String], the H4 seam
// already wired into AppleSpeechTranscriber.contextualStrings). This type holds the
// add/remove *rules* so they can be unit-tested without any UI or UserDefaults.
//
// Rules:
//   - add: trim whitespace; ignore empty; case-insensitive dedupe (keep the first
//     spelling the user entered); append to the end (most-recent last).
//   - remove: delete the exact term (case-insensitive match).

import Foundation

// MARK: - CustomVocabulary

public enum CustomVocabulary {

    /// Returns a new list with `term` added per the rules above. If `term` is blank
    /// or a case-insensitive duplicate, the list is returned unchanged.
    public static func adding(_ term: String, to list: [String]) -> [String] {
        let trimmed = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return list }
        guard !list.contains(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame }) else {
            return list
        }
        return list + [trimmed]
    }

    /// Returns a new list with every case-insensitive match of `term` removed.
    public static func removing(_ term: String, from list: [String]) -> [String] {
        list.filter { $0.caseInsensitiveCompare(term) != .orderedSame }
    }
}
