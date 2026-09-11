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

    /// Callback to trigger permission resolution via Onboarding flow.
    var showOnboarding: (() -> Void)?

    /// Publisher that fires when a dictation completes. Used by the Home pane to
    /// refresh recent dictations list. [decision P11-c: allows the dashboard to
    /// stay up-to-date when opened alongside active dictation.]
    /// `var` so that `DashboardWindowController.updateContext()` can refresh it at show-time.
    var dictationCompletedPublisher: AnyPublisher<Void, Never>?

    /// Publisher to programmatically navigate to a dashboard section or .settings mode.
    var navigateToSectionPublisher: AnyPublisher<DashboardSection, Never>?

    /// The active hotkey combo, pre-rendered as keycap labels (e.g. ["Fn", "Fn"]).
    /// Supplied by the controller from the live `HotkeyMonitor.binding`.
    var hotkeyCombo: [String]

    /// The live active HotkeyBinding — read by the Settings pane to show the current binding.
    /// `var` so WindowPresenter refreshes it before each show().
    var activeBinding: HotkeyBinding

    /// Called by the Settings pane when the user saves a new hotkey. Routes to
    /// `DictationController.rebindHotkey(_:)`. Nil in preview contexts.
    var rebindHotkey: ((HotkeyBinding) -> Void)?

    /// The current extra (additive) hotkey bindings — mouse buttons and extra
    /// modifier shortcuts (V01-5). Read by the Settings Hotkeys category.
    var activeExtraBindings: ExtraBindingSet

    /// Called when the user edits the extra-bindings set. Routes to
    /// `DictationController.rebindExtraBindings(_:)`. Nil in preview contexts.
    var rebindExtraBindings: ((ExtraBindingSet) -> Void)?

    /// AVB-7 (specs/avb7-durable-calls-design.md): the durable-call store backing
    /// the Agent Inbox pane and the menubar badge count. Nil only in preview
    /// contexts. [decision: AVB-7]
    var agentCallStore: (any AgentCallStoring)?

    /// Agent Playground conversation persistence. Nil only in preview contexts.
    var conversationStore: (any ConversationStoring)?

    /// AVB-7: "Answer by voice" row action — routes through
    /// `DictationController.answerAgentCallByVoice(_:)` (the same capture path
    /// `speak_request_input` uses). Nil in preview contexts.
    var answerAgentCallByVoice: ((AgentCall) async -> HumanResponseOutcome)?

    /// AVB-7: "Decline" row action (no mic). Nil in preview contexts.
    var declineAgentCall: ((UUID) async -> Void)?

    /// AVB-7: "Dismiss" row action (no mic). Nil in preview contexts.
    var dismissAgentCall: ((UUID) async -> Void)?

    /// Triggers complete self-healing, hotkey tap re-arm, and engine recovery.
    var onSelfHeal: (() -> Void)?

    /// Start dictation via DictationController (opens HUD, streams levels/partials, AI clean).
    var onStartDictation: (() async -> Void)?

    /// Stop dictation via DictationController (triggers neat-writing and pastes at cursor).
    var onStopDictation: (() async -> Void)?

    /// Query whether dictation is actively recording.
    var isDictating: (() -> Bool)?

    /// Explicit init with optional engine/permission manager/publisher (P11-c).
    /// Previews can create a minimal context without these dependencies.
    init(
        settingsStore: SettingsStore,
        historyStore: any HistoryStoring,
        hotkeyCombo: [String],
        activeBinding: HotkeyBinding = .defaultBinding,
        snippetStore: SnippetStore = SnippetStore(),
        profileStore: ProfileStore = ProfileStore(),
        speakEngine: SpeakEngine? = nil,
        permissionManager: PermissionManager? = nil,
        showOnboarding: (() -> Void)? = nil,
        dictationCompletedPublisher: AnyPublisher<Void, Never>? = nil,
        navigateToSectionPublisher: AnyPublisher<DashboardSection, Never>? = nil,
        rebindHotkey: ((HotkeyBinding) -> Void)? = nil,
        activeExtraBindings: ExtraBindingSet = .empty,
        rebindExtraBindings: ((ExtraBindingSet) -> Void)? = nil,
        agentCallStore: (any AgentCallStoring)? = nil,
        conversationStore: (any ConversationStoring)? = nil,
        answerAgentCallByVoice: ((AgentCall) async -> HumanResponseOutcome)? = nil,
        declineAgentCall: ((UUID) async -> Void)? = nil,
        dismissAgentCall: ((UUID) async -> Void)? = nil,
        onSelfHeal: (() -> Void)? = nil,
        onStartDictation: (() async -> Void)? = nil,
        onStopDictation: (() async -> Void)? = nil,
        isDictating: (() -> Bool)? = nil
    ) {
        self.settingsStore = settingsStore
        self.historyStore = historyStore
        self.hotkeyCombo = hotkeyCombo
        self.activeBinding = activeBinding
        self.snippetStore = snippetStore
        self.profileStore = profileStore
        self.speakEngine = speakEngine
        self.permissionManager = permissionManager
        self.showOnboarding = showOnboarding
        self.dictationCompletedPublisher = dictationCompletedPublisher
        self.navigateToSectionPublisher = navigateToSectionPublisher
        self.rebindHotkey = rebindHotkey
        self.activeExtraBindings = activeExtraBindings
        self.rebindExtraBindings = rebindExtraBindings
        self.agentCallStore = agentCallStore
        self.conversationStore = conversationStore
        self.answerAgentCallByVoice = answerAgentCallByVoice
        self.declineAgentCall = declineAgentCall
        self.dismissAgentCall = dismissAgentCall
        self.onSelfHeal = onSelfHeal
        self.onStartDictation = onStartDictation
        self.onStopDictation = onStopDictation
        self.isDictating = isDictating
    }
}
