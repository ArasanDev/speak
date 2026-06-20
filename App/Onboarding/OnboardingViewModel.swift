// App/Onboarding/OnboardingViewModel.swift
//
// The `@MainActor ObservableObject` that drives the onboarding window.
//
// RESPONSIBILITIES:
//   - Owns a `PermissionManager` reference (shared from DictationController).
//   - Exposes the current `OnboardingEvaluation` as a `@Published` property.
//   - Handles the "Grant Microphone" action (async prompt) and the
//     "Open System Settings" deep-link for Accessibility + Input Monitoring.
//   - Polls `PermissionManager.status()` for the two manual-grant permissions
//     when onboarding is visible (they can only change in System Settings).
//   - Calls `settings.hasCompletedOnboarding = true` on finish.
//
// POLL INTERVAL: 1.5 s [decision: long enough to avoid hammering TCC/IOKit
//   but short enough that the checkmark appears within ~2 s of a System
//   Settings toggle. 0.5 s was considered but doubled the call rate with no
//   perceivable UX benefit — 1.5 s is the tradeoff point.]
//
// THREADING:
//   - `@MainActor` throughout. `requestMicrophone()` is `async` and `await`-ed.
//   - The poll `Task` captures `[weak self]` to avoid a retain cycle.

import SwiftUI
import AppKit
import SpeakCore
import os

// MARK: - OnboardingViewModel

@MainActor
final class OnboardingViewModel: ObservableObject {

    // MARK: - Published state

    /// The current evaluation result (step, completeness, blockers).
    @Published private(set) var evaluation: OnboardingEvaluation

    /// `true` while `requestMicrophone()` is in-flight (shows a spinner).
    @Published private(set) var isRequestingMic: Bool = false

    // MARK: - Private

    private let permissionManager: PermissionManager
    private let settings: SettingsStore

    /// The displayed step while navigating forward. Starts at `.welcome` so
    /// the user sees the title card first, regardless of permission state.
    @Published private(set) var displayedStep: OnboardingStep = .welcome

    /// Backing poll task — cancelled when the view model is deallocated.
    private var pollTask: Task<Void, Never>?

    private let log = SpeakLog.permissions

    // MARK: - Init

    init(permissionManager: PermissionManager, settings: SettingsStore) {
        self.permissionManager = permissionManager
        self.settings = settings
        // Evaluate once at init so the initial state is accurate.
        self.evaluation = OnboardingStateMachine.evaluate(
            manager: permissionManager,
            hasCompletedOnboarding: settings.hasCompletedOnboarding
        )
    }

    deinit {
        pollTask?.cancel()
    }

#if DEBUG
    // MARK: - Debug (verification harness only)

    /// Forces the onboarding view to display a specific step, bypassing the
    /// normal permission-gated auto-advance. Also suppresses the polling loop
    /// so TCC state on the test machine does not inadvertently advance the step.
    ///
    /// Called only from the `--debug-open onboarding-<step>` launch-arg path in
    /// `DebugLaunchDispatcher`. Never called in release builds.
    ///
    /// - Parameter step: The `OnboardingStep` to display.
    func forceStep(_ step: OnboardingStep) {
        pollTask?.cancel()
        pollTask = nil
        displayedStep = step
        log.info("OnboardingViewModel [DEBUG]: forced step to \(String(describing: step), privacy: .public)")
    }
#endif

    // MARK: - Lifecycle

    /// Call when the onboarding window appears. Starts the status-poll loop.
    func onAppear() {
        startPolling()
    }

    /// Call when the onboarding window disappears. Stops polling.
    func onDisappear() {
        pollTask?.cancel()
        pollTask = nil
    }

    // MARK: - Actions

    /// Request microphone access. Shows the system dialog (first run only).
    /// Updates `evaluation` when the user responds.
    func requestMicrophone() {
        guard !isRequestingMic else { return }
        isRequestingMic = true
        Task { [weak self] in
            guard let self else { return }
            _ = await self.permissionManager.requestMicrophone()
            self.isRequestingMic = false
            self.refreshEvaluation()
            self.advanceStepIfGranted(kind: .microphone)
        }
    }

    /// Primary action for the Accessibility step. Calls the prompting API so the
    /// app is **registered in the Accessibility list** (and a system prompt shows
    /// when not yet trusted), then opens System Settings so the user can toggle it
    /// on. Without this, the app never appears in the list and the deep-link lands
    /// on an empty pane — the toggle has nothing to act on.
    func requestAccessibility() {
        let trusted = permissionManager.requestAccessibility()
        refreshEvaluation()
        if trusted {
            advanceStepIfGranted(kind: .accessibility)
        } else {
            openSystemSettings(for: .accessibility)
        }
    }

    /// Primary action for the Input Monitoring step. Registers the app in the
    /// Input Monitoring list (and prompts), then opens System Settings. Same
    /// rationale as `requestAccessibility()`.
    func requestInputMonitoring() {
        let granted = permissionManager.requestInputMonitoring()
        refreshEvaluation()
        if granted {
            advanceStepIfGranted(kind: .inputMonitoring)
        } else {
            openSystemSettings(for: .inputMonitoring)
        }
    }

    /// Opens System Settings to the given privacy pane via deep-link.
    ///
    /// Deep-link anchors on macOS 13+ (`Privacy_Accessibility`,
    /// `Privacy_ListenEvent`) open the correct pane directly.
    /// [deferred — needs human verification that the correct sub-pane opens on
    ///  macOS 26 Tahoe: human-verification.md §4.4]
    func openSystemSettings(for kind: PermissionKind) {
        let urlString: String
        switch kind {
        case .microphone:
            // Microphone is prompted programmatically (requestMicrophone), but if
            // denied the user must re-enable it manually in System Settings.
            urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"
        case .accessibility:
            urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        case .inputMonitoring:
            urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent"
        }
        guard let url = URL(string: urlString) else {
            let kindDescription = String(describing: kind)
            log.error("OnboardingViewModel: failed to construct System Settings URL for \(kindDescription, privacy: .public)")
            return
        }
        NSWorkspace.shared.open(url)
        log.info("OnboardingViewModel: opened System Settings for \(String(describing: kind), privacy: .public)")
    }

    /// Advance to the next step in the flow. Called by the "Continue" / "Next" buttons.
    func advance() {
        let nextStep = stepAfter(displayedStep)
        if nextStep == .done {
            finish()
        } else {
            displayedStep = nextStep
        }
    }

    /// Skip onboarding entirely — sets the flag so it doesn't show again.
    /// The user can return to Settings to grant permissions later.
    ///
    /// Risk #4 mitigation (quality.md §8): avoids a >25% drop-off by providing
    /// an escape hatch. The engine degrades gracefully when permissions are missing.
    func skip() {
        finish()
    }

    // MARK: - Private

    /// Mark onboarding complete and stop polling.
    private func finish() {
        settings.hasCompletedOnboarding = true
        pollTask?.cancel()
        pollTask = nil
        refreshEvaluation()
        displayedStep = .done
        log.info("OnboardingViewModel: onboarding finished.")
    }

    /// Re-evaluate the machine from the current live permission states.
    private func refreshEvaluation() {
        evaluation = OnboardingStateMachine.evaluate(
            manager: permissionManager,
            hasCompletedOnboarding: settings.hasCompletedOnboarding
        )
    }

    /// If the given kind is now granted, advance the displayed step forward.
    private func advanceStepIfGranted(kind: PermissionKind) {
        guard permissionManager.status(kind) == .granted else { return }
        let next = stepAfter(displayedStep)
        if next != .done {
            displayedStep = next
        }
    }

    /// The step immediately following `step` in the canonical sequence.
    private func stepAfter(_ step: OnboardingStep) -> OnboardingStep {
        switch step {
        case .welcome:        return .microphone
        case .microphone:     return .accessibility
        case .accessibility:  return .inputMonitoring
        case .inputMonitoring: return .hotkey
        case .hotkey:         return .done
        case .done:           return .done
        }
    }

    /// Start polling `PermissionManager.status()` for the two manual-grant
    /// permissions (accessibility + inputMonitoring). The poll runs until
    /// onboarding is complete or the view model is deallocated.
    ///
    /// Poll interval: 1.5 s [decision: see file header]
    private func startPolling() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            // 1.5 s expressed in nanoseconds: 1_500_000_000 ns = 1.5 s
            // [decision: 1.5 s poll interval — see file header for derivation]
            let pollIntervalNanoseconds: UInt64 = 1_500_000_000
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: pollIntervalNanoseconds)
                guard let self, !Task.isCancelled else { break }
                self.refreshEvaluation()
                // If the currently displayed step's permission just became granted,
                // auto-advance so the user doesn't need to tap a button.
                switch self.displayedStep {
                case .accessibility:
                    if self.permissionManager.status(.accessibility) == .granted {
                        self.displayedStep = .inputMonitoring
                    }
                case .inputMonitoring:
                    if self.permissionManager.status(.inputMonitoring) == .granted {
                        self.displayedStep = .hotkey
                    }
                default:
                    break
                }
            }
        }
    }
}
