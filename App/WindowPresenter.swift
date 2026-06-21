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
import SwiftUI
import SpeakCore

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

    // MARK: - Init

    init(
        historyStore: any HistoryStoring,
        permissionManager: PermissionManager,
        settingsStore: SettingsStore,
        snippetStore: SnippetStore,
        hotkeyComboProvider: @escaping @MainActor () -> [String]
    ) {
        self.historyStore = historyStore
        self.permissionManager = permissionManager
        self.settingsStore = settingsStore
        self.snippetStore = snippetStore
        self.hotkeyComboProvider = hotkeyComboProvider
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
        let context = DashboardContext(
            settingsStore: settingsStore,
            historyStore: historyStore,
            hotkeyCombo: hotkeyComboProvider(),
            snippetStore: snippetStore
        )
        let controller = DashboardWindowController(context: context)
        dashboardController = controller
        return controller
    }

    /// Show the dashboard window. The window controller is created lazily on first call.
    func showDashboard() {
        ensureDashboardController().show()
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
            onboardingController = OnboardingWindowController(
                permissionManager: permissionManager,
                settings: settingsStore
            )
        }
        onboardingController?.show()
    }
}
