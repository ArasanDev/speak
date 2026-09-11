// SpeakCore/Vocabulary/AcousticCorrectionExpander.swift
//
// `SnippetExpanding` conformer that applies the acoustic-corrections table to a
// raw transcript. Replacement semantics are inherited from `SnippetExpander`:
// whole-word, case-insensitive, so "darker" in "a darker theme" becomes
// "a docker theme" while "darkness" is left alone.
//
// Composed into the session expander chain by `defaultExpander(for:)` BEFORE
// snippet expansion: corrections normalize what STT heard back to ground truth,
// so a snippet trigger the user actually said still fires even when the
// recognizer mangled it. [decision]

import Foundation

public struct AcousticCorrectionExpander: SnippetExpanding {

    private let expander: SnippetExpander

    public init(corrections: [AcousticCorrection]) {
        self.expander = SnippetExpander(
            snippets: corrections.map { Snippet(trigger: $0.heard, expansion: $0.typed) }
        )
    }

    public func expand(_ text: String) -> String {
        expander.expand(text)
    }
}
