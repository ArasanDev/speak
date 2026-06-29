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

import Combine
import SpeakCore
import SwiftUI

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

    /// The profile store (AI Studio pane binds to it; the engine reads it at dictation
    /// start). The SAME instance the engine resolves against, so an edit is felt next dictation.
    let profileStore: ProfileStore

    /// The speech engine (for starting dictation from the Dashboard CTA button).
    /// [unverified: injected from DictationController in P11-c phase 3]
    /// `var` so that `DashboardWindowController.updateContext()` can refresh it at show-time.
    var speakEngine: SpeakEngine?

    /// The permission manager (for checking microphone and accessibility status).
    /// [unverified: injected from DictationController in P11-c phase 3]
    /// `var` so that `DashboardWindowController.updateContext()` can refresh it at show-time.
    var permissionManager: PermissionManager?

    /// Publisher that fires when a dictation completes. Used by the Home pane to
    /// refresh recent dictations list. [decision P11-c: allows the dashboard to
    /// stay up-to-date when opened alongside active dictation.]
    /// `var` so that `DashboardWindowController.updateContext()` can refresh it at show-time.
    var dictationCompletedPublisher: AnyPublisher<Void, Never>?

    /// The active hotkey combo, pre-rendered as keycap labels (e.g. ["Fn", "Fn"]).
    /// Supplied by the controller from the live `HotkeyMonitor.binding`.
    ///
    /// `var` so that `WindowPresenter.showDashboard()` can refresh this value each
    /// time the dashboard is shown — the provider closure is called lazily at show
    /// time rather than at controller construction, so a hotkey rebind is reflected
    /// the next time the window opens. [decision: refresh-at-show; DashboardContext
    /// is a value type captured by NSHostingView at window construction, so the
    /// update path is: mutate context before the hosting view reads it on show()]
    var hotkeyCombo: [String]

    /// Explicit init with optional engine/permission manager/publisher (P11-c).
    /// Previews can create a minimal context without these dependencies.
    init(
        settingsStore: SettingsStore,
        historyStore: any HistoryStoring,
        hotkeyCombo: [String],
        snippetStore: SnippetStore = SnippetStore(),
        profileStore: ProfileStore = ProfileStore(),
        speakEngine: SpeakEngine? = nil,
        permissionManager: PermissionManager? = nil,
        dictationCompletedPublisher: AnyPublisher<Void, Never>? = nil
    ) {
        self.settingsStore = settingsStore
        self.historyStore = historyStore
        self.hotkeyCombo = hotkeyCombo
        self.snippetStore = snippetStore
        self.profileStore = profileStore
        self.speakEngine = speakEngine
        self.permissionManager = permissionManager
        self.dictationCompletedPublisher = dictationCompletedPublisher
    }
}
