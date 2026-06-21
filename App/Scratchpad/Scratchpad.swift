// App/Scratchpad/Scratchpad.swift
//
// The single source of truth for the local Scratchpad note's storage key + an append
// helper. The Scratchpad pane binds to this key via @AppStorage; the dictation flow
// appends to it when a paste fails so the text is never lost (verified Wispr behavior:
// "if paste fails, the transcript lands in the Scratchpad").

import Foundation

enum Scratchpad {

    /// UserDefaults key backing the Scratchpad note (also used by `@AppStorage`).
    static let defaultsKey = "speak.scratchpad.text"

    /// Append `text` to the Scratchpad note (blank-separated), ignoring empty input.
    /// Writes `UserDefaults.standard` so an open `ScratchpadPaneView` (@AppStorage on the
    /// same key) reflects it live.
    static func append(_ text: String, to defaults: UserDefaults = .standard) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let existing = defaults.string(forKey: defaultsKey) ?? ""
        let separator = existing.isEmpty ? "" : "\n\n"
        defaults.set(existing + separator + trimmed, forKey: defaultsKey)
    }
}
