// SpeakCore/Snippets/CompositeExpander.swift
//
// Chains several `SnippetExpanding` stages into one. Used by
// `defaultExpander(for:snippetStore:)` to run acoustic corrections and snippet
// expansion over the raw transcript in a defined order (corrections first —
// they restore ground truth so real snippet triggers still match).

import Foundation

public struct CompositeExpander: SnippetExpanding {

    private let stages: [any SnippetExpanding]

    public init(_ stages: [any SnippetExpanding]) {
        self.stages = stages
    }

    public func expand(_ text: String) -> String {
        stages.reduce(text) { $1.expand($0) }
    }
}
