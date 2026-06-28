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
    private var settingsController: SettingsWindowController?

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

    /// Lazily create and show the full-window dashboard (Phase-2 UI spine).
    /// Returns the controller — exposed as `internal` for testability.
    @discardableResult
    func ensureDashboardController() -> DashboardWindowController {
        if let existing = dashboardController {
            return existing
        }
        // P11-c: Pass speakEngine + permissionManager from the controller so the
        // dashboard Home pane can access live engine state and show hotkey status.
        // Also pass the dictation completion publisher so the dashboard can refresh
        // recent dictations after a new entry is saved.
        let context = DashboardContext(
            settingsStore: settingsStore,
            historyStore: historyStore,
            hotkeyCombo: hotkeyComboProvider(),
            snippetStore: snippetStore,
            speakEngine: dictationController?.engine,
            permissionManager: permissionManager,
            dictationCompletedPublisher: dictationController?.dictationCompletedPublisher
        )
        let controller = DashboardWindowController(context: context)
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
            dictationCompletedPublisher: dictationController?.dictationCompletedPublisher
        )
        controller.show()
    }

    // MARK: - Onboarding window

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

    // MARK: - Settings window

    /// Lazily create and show the Settings window.
    /// Returns the controller — exposed as `internal` for testability.
    @discardableResult
    func ensureSettingsController() -> SettingsWindowController? {
        if let existing = settingsController {
            return existing
        }
        guard let controller = dictationController else { return nil }
        let settingsController = SettingsWindowController(controller: controller)
        self.settingsController = settingsController
        return settingsController
    }

    /// Show the Settings window. The window controller is created lazily on first call.
    func showSettings() {
        ensureSettingsController()?.show()
    }
}
