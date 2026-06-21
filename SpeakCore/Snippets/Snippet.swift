// SpeakCore/Snippets/Snippet.swift
//
// A text snippet: a spoken `trigger` that expands into longer `expansion` text,
// applied to the transcript BEFORE the LLM cleanup pass (acceleration-plan.md Wave B;
// verified Wispr behavior — trigger → expansion). Pure value type; persisted by
// `SnippetStore`, expanded by `SnippetExpander`.

import Foundation

// MARK: - Snippet

public struct Snippet: Codable, Sendable, Identifiable, Equatable, Hashable {

    /// Stable identity for SwiftUI lists + persistence. Defaults to a fresh UUID.
    public let id: UUID

    /// What the user says (the shorthand). Matched case-insensitively, whole-word.
    public let trigger: String

    /// What it expands to (inserted in place of the trigger).
    public let expansion: String

    public init(id: UUID = UUID(), trigger: String, expansion: String) {
        self.id = id
        self.trigger = trigger
        self.expansion = expansion
    }
}
