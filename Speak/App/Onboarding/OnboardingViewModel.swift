// App/Onboarding/OnboardingViewModel.swift
//
// The `@MainActor @Observable` that drives the onboarding window.
//
// RESPONSIBILITIES:
//   - Owns a `PermissionManager` reference (shared from DictationController).
//   - Exposes the current `OnboardingEvaluation` as an observable property.
//   - Handles the "Grant Microphone" action (async prompt) and the
//     "Open System Settings" deep-link for Accessibility.
//   - Polls `PermissionManager.status()` and listens for app activation (`didBecomeActiveNotification`)
//     to immediately auto-advance when Accessibility or Microphone permissions are granted.
//   - Calls `settings.hasCompletedOnboarding = true` on finish.
//
// POLL INTERVAL: 1.0 s [decision: fast checkmark appearance within 1 s of System Settings toggle].

import AppKit
import Combine
import os
import SpeakCore
import SwiftUI

// MARK: - OnboardingViewModel

@Observable
@MainActor
final class OnboardingViewModel {

    // MARK: - Observable state

    /// The current evaluation result (step, completeness, blockers).
    private(set) var evaluation: OnboardingEvaluation

    /// `true` while `requestMicrophone()` is in-flight (shows a spinner).
    private(set) var isRequestingMic: Bool = false

    /// `true` once the user has fired the hotkey at least once during the hotkey step.
    /// Turns the "Try it now" pill green.
    private(set) var hotkeyTriggered: Bool = false

    /// `true` for Accessibility after the first tap — TCC prompt has been fired,
    /// waiting for the user to toggle the switch in System Settings.
    private(set) var isWaitingForAccessibility: Bool = false

    // MARK: - Live hotkey display string

    private(set) var currentHotkeyDisplayString: String = ""

    // MARK: - Private

    private let permissionManager: any PermissionManaging
    private let settings: SettingsStore

    /// The displayed step while navigating forward. Starts at `.welcome` so
    /// the user sees the title card first, regardless of permission state.
    private(set) var displayedStep: OnboardingStep = .welcome

    /// Tracks which manual-grant permissions have had their TCC registration prompt fired.
    private var hasPrompted: Set<PermissionKind> = []

    /// Backing poll task — cancelled when the view model is deallocated.
    private var pollTask: Task<Void, Never>?

    /// Task that subscribes to the hotkey-fired publisher for the "Try it now" pill.
    private var hotkeyListenTask: Task<Void, Never>?

    /// App activation observer token.
    private var appActiveObserver: Any?

    private let log = SpeakLog.permissions

    // MARK: - Init

    init(permissionManager: any PermissionManaging, settings: SettingsStore) {
        self.permissionManager = permissionManager
        self.settings = settings
        self.evaluation = OnboardingStateMachine.evaluate(
            manager: permissionManager,
            hasCompletedOnboarding: settings.hasCompletedOnboarding
        )
        self.currentHotkeyDisplayString = Self.computeHotkeyDisplayString(settings: settings)
    }

    #if DEBUG
    // MARK: - Debug (verification harness only)

    func forceStep(_ step: OnboardingStep) {
        pollTask?.cancel()
        pollTask = nil
        displayedStep = step
        log.info("OnboardingViewModel [DEBUG]: forced step to \(String(describing: step), privacy: .public)")
    }
    #endif

    // MARK: - Lifecycle

    /// Call when the onboarding window appears. Starts the status-poll loop and app-active listener.
    func onAppear() {
        refreshEvaluation()
        startPolling()
        startListeningForAppActivation()
    }

    /// Call when the onboarding window disappears. Stops polling, hotkey listening, and notification observers.
    func onDisappear() {
        pollTask?.cancel()
        pollTask = nil
        hotkeyListenTask?.cancel()
        hotkeyListenTask = nil
        if let observer = appActiveObserver {
            NotificationCenter.default.removeObserver(observer)
            appActiveObserver = nil
        }
    }

    private func startListeningForAppActivation() {
        if appActiveObserver != nil { return }
        appActiveObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshEvaluation()
            }
        }
    }

    // MARK: - Hotkey live test

    func startListeningForHotkey(publisher: AnyPublisher<Void, Never>) {
        hotkeyListenTask?.cancel()
        hotkeyListenTask = Task { [weak self] in
            for await _ in publisher.values {
                guard let self, !Task.isCancelled else { break }
                if !self.hotkeyTriggered {
                    self.hotkeyTriggered = true
                    self.log.info("OnboardingViewModel: hotkey fired during onboarding — pill turned green.")
                }
            }
        }
    }

    // MARK: - Actions

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

    func requestAccessibility() {
        if permissionManager.status(.accessibility) == .granted {
            isWaitingForAccessibility = false
            refreshEvaluation()
            advanceStepIfGranted(kind: .accessibility)
            return
        }

        if hasPrompted.contains(.accessibility) {
            openSystemSettings(for: .accessibility)
            return
        }

        hasPrompted.insert(.accessibility)
        isWaitingForAccessibility = true
        let trusted = permissionManager.requestAccessibility()
        refreshEvaluation()
        if trusted {
            isWaitingForAccessibility = false
            advanceStepIfGranted(kind: .accessibility)
        }
    }

    func openSystemSettings(for kind: PermissionKind) {
        let urlString: String
        switch kind {
        case .microphone:
            urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"

        case .accessibility:
            urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        }
        guard let url = URL(string: urlString) else {
            let kindDescription = String(describing: kind)
            log.error("OnboardingViewModel: failed to construct System Settings URL for \(kindDescription, privacy: .public)")
            return
        }
        NSWorkspace.shared.open(url)
        log.info("OnboardingViewModel: opened System Settings for \(String(describing: kind), privacy: .public)")
    }

    func advance() {
        let nextStep = stepAfter(displayedStep)
        if nextStep == .done {
            finish()
        } else {
            displayedStep = nextStep
        }
    }

    func skip() {
        finish()
    }

    // MARK: - Private

    private func finish() {
        settings.hasCompletedOnboarding = true
        pollTask?.cancel()
        pollTask = nil
        refreshEvaluation()
        displayedStep = .done
        log.info("OnboardingViewModel: onboarding finished.")
    }

    private func refreshEvaluation() {
        evaluation = OnboardingStateMachine.evaluate(
            manager: permissionManager,
            hasCompletedOnboarding: settings.hasCompletedOnboarding
        )
        currentHotkeyDisplayString = Self.computeHotkeyDisplayString(settings: settings)

        // Clear isWaitingForAccessibility and auto-advance when permissions are granted
        if permissionManager.status(.accessibility) == .granted {
            isWaitingForAccessibility = false
            if displayedStep == .accessibility {
                displayedStep = .hotkey
            }
        }
        if permissionManager.status(.microphone) == .granted && displayedStep == .microphone {
            displayedStep = .accessibility
        }
    }

    private static func computeHotkeyDisplayString(settings: SettingsStore) -> String {
        let base = UserDefaultsBindingStore().load() ?? HotkeyBinding.defaultBinding
        let effective = base.with(trigger: settings.triggerMode)
        return effective.displayString
    }

    private func advanceStepIfGranted(kind: PermissionKind) {
        guard permissionManager.status(kind) == .granted else { return }
        let next = stepAfter(displayedStep)
        if next != .done {
            displayedStep = next
        }
    }

    private func stepAfter(_ step: OnboardingStep) -> OnboardingStep {
        switch step {
        case .welcome:        return .microphone
        case .microphone:     return .accessibility
        case .accessibility:  return .hotkey
        case .hotkey:         return .done
        case .done:           return .done
        }
    }

    private func startPolling() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            let pollIntervalNanoseconds: UInt64 = 1_000_000_000
            while !Task.isCancelled {
                guard let self, !Task.isCancelled else { break }
                self.refreshEvaluation()
                try? await Task.sleep(nanoseconds: pollIntervalNanoseconds)
            }
        }
    }
}
