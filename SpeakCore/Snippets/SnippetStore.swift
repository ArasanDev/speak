// SpeakCore/Snippets/SnippetStore.swift
//
// Persists the user's snippets as a JSON-encoded `[Snippet]` in UserDefaults.
//
// DESIGN (mirrors SettingsStore):
//   - `ObservableObject` so the Snippets pane binds via `@ObservedObject` and re-renders
//     on every mutation.
//   - `@unchecked Sendable` so `SpeakEngine` (an actor) can read `snippets` synchronously
//     at `newSession()` time (UserDefaults is documented thread-safe).
//   - Injected `UserDefaults` for test isolation (named suite), like SettingsStore.

import Foundation
import Combine
import os

// MARK: - SnippetStore

public final class SnippetStore: ObservableObject, @unchecked Sendable {

    private enum Keys {
        static let snippets = "speak.snippets.list"
    }

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// The persisted snippets, newest last. Reading decodes from UserDefaults each call;
    /// writing re-encodes and fires `objectWillChange` for SwiftUI.
    public var snippets: [Snippet] {
        get {
            guard let data = defaults.data(forKey: Keys.snippets),
                  let decoded = try? JSONDecoder().decode([Snippet].self, from: data) else {
                return []
            }
            return decoded
        }
        set {
            objectWillChange.send()
            if let data = try? JSONEncoder().encode(newValue) {
                defaults.set(data, forKey: Keys.snippets)
            } else {
                SpeakLog.storage.error("SnippetStore: failed to encode snippets — not persisted.")
            }
        }
    }

    // MARK: - Mutation helpers

    /// Append a snippet (trimming trigger/expansion; ignoring blank). Returns `false`
    /// when the input is blank and nothing was added.
    @discardableResult
    public func add(trigger: String, expansion: String) -> Bool {
        let t = trigger.trimmingCharacters(in: .whitespacesAndNewlines)
        let e = expansion.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, !e.isEmpty else { return false }
        snippets += [Snippet(trigger: t, expansion: e)]
        return true
    }

    /// Remove the snippet with the given id.
    public func remove(id: Snippet.ID) {
        snippets = snippets.filter { $0.id != id }
    }

    /// Build an expander from the current snippets (read at dictation start time).
    public func makeExpander() -> SnippetExpander {
        SnippetExpander(snippets: snippets)
    }
}
