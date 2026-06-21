// App/Dashboard/DashboardContext.swift
//
// The dependency bundle handed to every dashboard pane.
//
// WHY A BUNDLE: panes are built by different specialists (Wave A/B fan-out). Passing a
// single `DashboardContext` keeps every pane's initializer signature identical and
// STABLE, so a specialist filling in one pane never has to touch `DashboardView`'s
// routing or another pane's signature. Add a dependency here once; all panes can read it.
//
// All members are reference types owned by `DictationController` (the app's brain) and
// merely shared here — the context does NOT own their lifetimes.

import SwiftUI
import SpeakCore

// MARK: - DashboardContext

@MainActor
struct DashboardContext {

    /// The single source of truth for persisted preferences (cleanup, style, language,
    /// custom vocabulary, …). Panes bind to it via `@ObservedObject`.
    let settingsStore: SettingsStore

    /// The dictation history store (read for History + Insights panes).
    let historyStore: any HistoryStoring

    /// The snippets store (Snippets pane binds to it; the engine reads it at dictation start).
    let snippetStore: SnippetStore

    /// The active hotkey combo, pre-rendered as keycap labels (e.g. ["Fn", "Fn"]).
    /// Supplied by the controller from the live `HotkeyMonitor.binding`.
    let hotkeyCombo: [String]

    /// Explicit init with `snippetStore` defaulted to a fresh store, so SwiftUI
    /// previews can omit it; production call sites inject the shared store.
    init(
        settingsStore: SettingsStore,
        historyStore: any HistoryStoring,
        hotkeyCombo: [String],
        snippetStore: SnippetStore = SnippetStore()
    ) {
        self.settingsStore = settingsStore
        self.historyStore = historyStore
        self.hotkeyCombo = hotkeyCombo
        self.snippetStore = snippetStore
    }
}
