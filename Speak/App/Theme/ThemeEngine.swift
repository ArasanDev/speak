// App/Theme/ThemeEngine.swift
//
// The theme runtime owner — the analogue of t3code's `themePalette` store +
// `themeEditorStore`. Loads the selected theme + user-defined themes from
// `SettingsStore`, resolves the active palette, and repaints the app by:
//   1. assigning `SpeakThemeRuntime.active` (the registry `Color.speak*`
//      statics read through), and
//   2. publishing `activeTheme`, which `ThemedRoot` injects as
//      `\.speakTheme` — an environment change that re-evaluates every
//      descendant body, repainting the statics in place.
//
// DRAFT EDITING (t3code's ThemeEditorSession): a draft theme paints the live
// app while the editor is open — every `updateDraft` applies immediately so
// judging a palette means looking at the real app, not a mock. Discard
// restores the committed theme; commit persists + selects it.
//
// Owned by `DictationController` (the app brain), shared into every window
// root via `DashboardContext.themeEngine` / `ThemedRoot`.

import Combine
import Foundation
import SpeakCore
import SwiftUI

// MARK: - ThemeEngine

@MainActor
final class ThemeEngine: ObservableObject {

    /// The resolved active theme — published so `ThemedRoot` re-injects the
    /// environment value and the whole subtree repaints.
    @Published private(set) var activeTheme: SpeakTheme

    /// All selectable themes: built-ins first, then user customs (save order).
    @Published private(set) var themes: [SpeakTheme]

    /// The live-editing session, if the theme editor is open. Mutating it
    /// repaints the app immediately (draft paints the real app, t3code-style).
    @Published private(set) var draft: SpeakTheme?

    private let settingsStore: SettingsStore

    /// `settingsStore.themeID` is observed in `init` via `observeThemeID()` —
    /// writes by ANYONE (picker, "Reset All Settings", `defaults write`)
    /// repaint the live app. Same `withObservationTracking` one-shot/re-arm
    /// pattern as DictationController's trigger observer.
    init(settingsStore: SettingsStore) {
        self.settingsStore = settingsStore
        let customs = Self.decodeCustomThemes(settingsStore.customThemesJSON)
        self.themes = SpeakTheme.builtInThemes + customs
        let storedID = settingsStore.themeID
        let resolved = (SpeakTheme.builtInThemes + customs).first { $0.id == storedID }
            ?? .speak
        self.activeTheme = resolved
        SpeakThemeRuntime.active = resolved
        observeThemeID()
    }

    /// Apply the stored selection if it differs (called on themeID changes).
    private func applyStoredThemeSelection() {
        let id = settingsStore.themeID
        guard activeTheme.id != id,
              let theme = themes.first(where: { $0.id == id }) else { return }
        discardDraft()
        activeTheme = theme
        SpeakThemeRuntime.active = theme
    }

    private func observeThemeID() {
        withObservationTracking {
            _ = settingsStore.themeID
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.applyStoredThemeSelection()
                self.observeThemeID()
            }
        }
    }

    // MARK: - Selection

    /// Switch the active theme (built-in or custom). Unknown ids are ignored —
    /// the list UI only offers ids that exist.
    func select(_ id: String) {
        guard let theme = themes.first(where: { $0.id == id }) else { return }
        discardDraft()  // leaving the editor mid-draft restores the pick
        activeTheme = theme
        SpeakThemeRuntime.active = theme
        settingsStore.themeID = id
    }

    // MARK: - Draft editing

    /// Open a draft seeded from the active theme (t3code seeds from the active
    /// theme too). Returns the draft so the editor can bind to it.
    @discardableResult
    func beginDraft(seedName: String = "My Theme") -> SpeakTheme {
        var seeded = activeTheme
        seeded.id = "custom-\(UUID().uuidString.lowercased())"
        seeded.name = seedName
        draft = seeded
        SpeakThemeRuntime.active = seeded
        return seeded
    }

    /// Open an existing custom theme for in-place editing (commit updates the
    /// same id rather than appending).
    func editTheme(_ theme: SpeakTheme) {
        draft = theme
        SpeakThemeRuntime.active = theme
    }

    /// Live-apply one role's light/dark hex while the editor is open.
    func updateDraft(_ role: ThemeColorRole, light: String, dark: String) {
        guard var d = draft else { return }
        d.colors[role.rawValue] = ThemeHexPair(light: light, dark: dark)
        draft = d
        SpeakThemeRuntime.active = d
    }

    /// Nil a role's override (reverts it to the `speak` default; for `accent`
    /// that means the system accent color again).
    func clearDraftRole(_ role: ThemeColorRole) {
        guard var d = draft else { return }
        d.colors.removeValue(forKey: role.rawValue)
        draft = d
        SpeakThemeRuntime.active = d
    }

    func renameDraft(_ name: String) {
        draft?.name = name
    }

    /// Persist the draft as a custom theme and make it active.
    func commitDraft() {
        guard let d = draft else { return }
        var customs = themes.filter { !$0.isBuiltIn }
        if let idx = customs.firstIndex(where: { $0.id == d.id }) {
            customs[idx] = d
        } else {
            customs.append(d)
        }
        themes = SpeakTheme.builtInThemes + customs
        persistCustomThemes(customs)
        draft = nil
        select(d.id)
    }

    /// Abandon the draft — the committed active theme repaints immediately.
    func discardDraft() {
        guard draft != nil else { return }
        draft = nil
        SpeakThemeRuntime.active = activeTheme
    }

    /// Remove a custom theme. Deleting the active theme falls back to `speak`.
    func deleteCustomTheme(id: String) {
        let customs = themes.filter { !$0.isBuiltIn && $0.id != id }
        themes = SpeakTheme.builtInThemes + customs
        persistCustomThemes(customs)
        if draft?.id == id { draft = nil }
        if activeTheme.id == id { select(SpeakTheme.speak.id) }
    }

    // MARK: - Persistence

    private func persistCustomThemes(_ customs: [SpeakTheme]) {
        do {
            let data = try JSONEncoder().encode(customs)
            settingsStore.customThemesJSON = String(decoding: data, as: UTF8.self)
        } catch {
            SpeakLog.app.error(
                "ThemeEngine: failed to encode custom themes — \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    /// Lenient decode — a corrupt blob logs and yields no customs rather than
    /// throwing (mirrors t3code's `parseStoredThemes` drop-and-continue).
    private static func decodeCustomThemes(_ json: String) -> [SpeakTheme] {
        guard !json.isEmpty, let data = json.data(using: .utf8) else { return [] }
        do {
            return try JSONDecoder().decode([SpeakTheme].self, from: data)
                .filter { !SpeakTheme.builtInIDs.contains($0.id) }
        } catch {
            SpeakLog.app.error(
                "ThemeEngine: corrupt customThemesJSON ignored — \(error.localizedDescription, privacy: .public)"
            )
            return []
        }
    }
}
