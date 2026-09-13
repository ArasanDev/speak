// App/WindowPresenter.swift
//
// Owns presentation of the History and Onboarding windows.
//
// Responsibilities:
//   - Lazily constructs and holds `HistoryWindowController` and
//     `OnboardingWindowController` — each is created at most once per session,
//     matching the "lazy var" pattern from the original `DictationController`.
//   - `showHistory()` — ensures the history controller exists, then shows it.
//   - `showOnboardingIfNeeded()` — evaluates `OnboardingStateMachine`, skips if
//     onboarding is already complete, creates the controller lazily, then shows it.
//
// Honesty boundary:
//   - Window visibility (`NSWindow.show()`) is live-window-server behaviour — not
//     autonomously verifiable in unit tests. Tests should assert that the controller
//     is lazily constructed (same instance on second call) WITHOUT calling show().
//   - `ensureHistoryController()` is `internal` for @testable access from SpeakTests.
//
// Threading:
//   - `WindowPresenter` is `@MainActor`. All NSWindow / NSWindowController
//     operations run on the main thread (AppKit requirement).
//
// Retained references:
//   - `permissionManager` and `settingsStore` are passed in from `DictationController`
//     and are NOT owned by `WindowPresenter` — we hold weak-equivalent references
//     via value/reference semantics appropriate to each type.

import AppKit
import Combine
import SpeakCore
import SwiftUI

// MARK: - WindowPresenter

@MainActor
final class WindowPresenter {

    // MARK: - Private components

    private let historyStore: any HistoryStoring
    private let permissionManager: PermissionManager
    private let settingsStore: SettingsStore
    private let snippetStore: SnippetStore

    // MARK: - Lazy window controllers

    private var historyController: HistoryWindowController?
    private var onboardingController: OnboardingWindowController?
    private var dashboardController: DashboardWindowController?

    /// Supplies the live hotkey combo (e.g. ["Fn", "Fn"]) for the dashboard at show
    /// time. Injected by `DictationController`, which owns the `HotkeyMonitor`. Read
    /// lazily so a trigger-mode change is reflected the next time the window opens.
    private let hotkeyComboProvider: @MainActor () -> [String]

    /// Publisher that fires on the main thread each time the hotkey triggers dictation.
    /// Derived from `DictationController.$icon` (`.listening` edge) by the caller,
    /// so no second iterator on `HotkeyMonitor.events` is created.
    /// Used by the onboarding flow's "Try it now" live test pill.
    private let hotkeyFiredPublisher: AnyPublisher<Void, Never>?

    // MARK: - Init

    // Store reference to DictationController for SettingsWindowController
    private weak var dictationController: DictationController?

    init(
        historyStore: any HistoryStoring,
        permissionManager: PermissionManager,
        settingsStore: SettingsStore,
        snippetStore: SnippetStore,
        hotkeyComboProvider: @escaping @MainActor () -> [String],
        hotkeyFiredPublisher: AnyPublisher<Void, Never>? = nil,
        dictationController: DictationController? = nil
    ) {
        self.historyStore = historyStore
        self.permissionManager = permissionManager
        self.settingsStore = settingsStore
        self.snippetStore = snippetStore
        self.hotkeyComboProvider = hotkeyComboProvider
        self.hotkeyFiredPublisher = hotkeyFiredPublisher
        self.dictationController = dictationController
    }

    // MARK: - History window

    /// Lazily create and show the History window (P9).
    /// Returns the controller — exposed as `internal` for testability.
    @discardableResult
    func ensureHistoryController() -> HistoryWindowController {
        if let existing = historyController {
            return existing
        }
        let controller = HistoryWindowController(store: historyStore)
        historyController = controller
        return controller
    }

    /// Show the History window. The window controller is created lazily on first call.
    func showHistory() {
        ensureHistoryController().show()
    }

    // MARK: - Dashboard window

    /// Assemble a `DashboardContext` bound to the live stores, engine, and
    /// controller closures. Shared by `ensureDashboardController()` (the desk
    /// window) and the standalone `Settings` scene (Cmd+,), which hosts the
    /// same `SettingsExperienceView` so every entry point renders one surface.
    /// [decision: extracted so the SwiftUI Settings scene reuses the identical
    ///  wiring instead of a second, divergent Settings implementation.]
    func makeDashboardContext() -> DashboardContext {
        // P11-c: Pass speakEngine + permissionManager from the controller so the
        // dashboard Home pane can access live engine state and show hotkey status.
        // Also pass the dictation completion publisher so the dashboard can refresh
        // recent dictations after a new entry is saved.
        DashboardContext(
            settingsStore: settingsStore,
            historyStore: historyStore,
            hotkeyCombo: hotkeyComboProvider(),
            activeBinding: dictationController?.activeBinding ?? .defaultBinding,
            snippetStore: snippetStore,
            profileStore: dictationController?.profileStore ?? ProfileStore(),
            speakEngine: dictationController?.engine,
            permissionManager: permissionManager,
            showOnboarding: { [weak self] in self?.showOnboarding() },
            dictationCompletedPublisher: dictationController?.dictationCompletedPublisher,
            rebindHotkey: { [weak self] binding in self?.dictationController?.rebindHotkey(binding) },
            activeExtraBindings: dictationController?.activeExtraBindings ?? .empty,
            rebindExtraBindings: { [weak self] set in
                self?.dictationController?.rebindExtraBindings(set)
            },
            voiceOut: dictationController?.voiceOut,
            agentSessionRegistry: dictationController?.agentSessionRegistry,
            agentCallStore: dictationController?.agentCallStore,
            answerAgentCallByVoice: { [weak self] call in
                await self?.dictationController?.answerAgentCallByVoice(call) ?? .cancelled
            },
            declineAgentCall: { [weak self] callId in
                await self?.dictationController?.declineAgentCall(callId)
            },
            dismissAgentCall: { [weak self] callId in
                await self?.dictationController?.dismissAgentCall(callId)
            },
            onSelfHeal: { [weak self] in
                self?.dictationController?.selfHeal()
            },
            onStartDictation: { [weak self] in
                _ = await self?.dictationController?.beginDictation()
            },
            onStopDictation: { [weak self] in
                await self?.dictationController?.endDictation()
            },
            isDictating: { [weak self] in
                self?.dictationController?.icon == .listening
            }
        )
    }

    /// Lazily create and show the full-window dashboard (Phase-2 UI spine).
    /// Returns the controller — exposed as `internal` for testability.
    @discardableResult
    func ensureDashboardController() -> DashboardWindowController {
        if let existing = dashboardController {
            return existing
        }
        let controller = DashboardWindowController(context: makeDashboardContext())
        dashboardController = controller
        return controller
    }

    /// Show the dashboard window. The window controller is created lazily on first call.
    ///
    /// Refreshes the hotkey combo, speakEngine, and permissionManager from the live
    /// provider before each show so that a hotkey rebind or permission change is reflected
    /// the next time the dashboard opens, not just at first construction.
    func showDashboard() {
        let controller = ensureDashboardController()
        // Read the provider lazily at show-time so any rebind since construction is
        // picked up. Also pass live engine + permissions + publisher so recent dictations
        // can refresh and permission status is current. The update is a no-op if unchanged.
        controller.updateContext(
            hotkeyCombo: hotkeyComboProvider(),
            speakEngine: dictationController?.engine,
            permissionManager: permissionManager,
            dictationCompletedPublisher: dictationController?.dictationCompletedPublisher,
            activeExtraBindings: dictationController?.activeExtraBindings,
            onStartDictation: { [weak self] in
                _ = await self?.dictationController?.beginDictation()
            },
            onStopDictation: { [weak self] in
                await self?.dictationController?.endDictation()
            },
            isDictating: { [weak self] in
                self?.dictationController?.icon == .listening
            }
        )
        controller.show()
    }

    // MARK: - Onboarding window

    /// Evaluates onboarding state and shows Onboarding if setup is needed;
    /// otherwise opens the Dashboard window so the user always receives a visible UI on launch.
    func showInitialWindowIfNeeded() {
        let eval = OnboardingStateMachine.evaluate(
            manager: permissionManager,
            hasCompletedOnboarding: settingsStore.hasCompletedOnboarding
        )
        if !eval.isComplete {
            showOnboardingIfNeeded()
        } else {
            showDashboard()
        }
    }

    /// Evaluate the onboarding state machine and show the onboarding window if needed.
    ///
    /// Skips silently when onboarding is already complete. Lazily creates the
    /// `OnboardingWindowController` on first call (and reuses it on subsequent calls).
    func showOnboardingIfNeeded() {
        let eval = OnboardingStateMachine.evaluate(
            manager: permissionManager,
            hasCompletedOnboarding: settingsStore.hasCompletedOnboarding
        )
        guard !eval.isComplete else { return }
        SpeakLog.permissions.info(
            "WindowPresenter: onboarding required — step=\(String(describing: eval.currentStep), privacy: .public)"
        )
        if onboardingController == nil {
            let controller = OnboardingWindowController(
                permissionManager: permissionManager,
                settings: settingsStore,
                hotkeyFiredPublisher: hotkeyFiredPublisher
            )
            // On first completion only: open the dashboard after the onboarding window
            // auto-closes. `[weak self]` breaks the reference cycle (WindowPresenter
            // owns `onboardingController`; a strong capture back would be a cycle).
            // "First-completion only" is guaranteed by the onboarding gate above:
            // on every subsequent launch `hasCompletedOnboarding == true` →
            // `eval.isComplete` → early return before this path is reached.
            controller.onCompletion = { [weak self] in
                self?.showDashboard()
                // [App-L3] onboardingController is not nilled here because the gate at
                // the top of showOnboardingIfNeeded() returns early on subsequent calls
                // (hasCompletedOnboarding == true). Held for app lifetime; cost is small
                // (one NSWindowController + OnboardingViewModel) and the pattern is uniform.
            }
            onboardingController = controller
        }
        onboardingController?.show()
    }

    /// Force show the onboarding setup flow regardless of `hasCompletedOnboarding`.
    /// Called when the user clicks "Resolve" or "Fix Permissions" in the app UI.
    func showOnboarding() {
        if onboardingController == nil {
            let controller = OnboardingWindowController(
                permissionManager: permissionManager,
                settings: settingsStore,
                hotkeyFiredPublisher: hotkeyFiredPublisher
            )
            controller.onCompletion = { [weak self] in
                self?.showDashboard()
            }
            onboardingController = controller
        }
        onboardingController?.show()
    }

    // MARK: - Settings

    /// Show the Settings pane inside the Dashboard (the single configuration surface).
    /// Routes to .settings initial section so the user lands directly on preferences.
    func showSettings() {
        let controller = ensureDashboardController()
        controller.updateContext(
            hotkeyCombo: hotkeyComboProvider(),
            speakEngine: dictationController?.engine,
            permissionManager: permissionManager,
            dictationCompletedPublisher: dictationController?.dictationCompletedPublisher,
            activeExtraBindings: dictationController?.activeExtraBindings
        )
        controller.show(initialSection: .settings)
    }

    /// A fresh `DashboardContext` for the standalone Settings surface (the
    /// SwiftUI `Settings` scene, Cmd+,). Same wiring as the desk window so both
    /// entry points render identical controls.
    func makeSettingsContext() -> DashboardContext {
        makeDashboardContext()
    }

    /// Open the dashboard at a specific desk section — used by standalone
    /// Settings "Open MCP & Agents"-style links, which hand off to the desk.
    func showDashboardSection(_ section: DashboardSection) {
        let controller = ensureDashboardController()
        controller.updateContext(
            hotkeyCombo: hotkeyComboProvider(),
            speakEngine: dictationController?.engine,
            permissionManager: permissionManager,
            dictationCompletedPublisher: dictationController?.dictationCompletedPublisher,
            activeExtraBindings: dictationController?.activeExtraBindings
        )
        controller.show(initialSection: section)
    }
}
