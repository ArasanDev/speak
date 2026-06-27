// App/Onboarding/OnboardingViewModel.swift
//
// The `@MainActor ObservableObject` that drives the onboarding window.
//
// RESPONSIBILITIES:
//   - Owns a `PermissionManager` reference (shared from DictationController).
//   - Exposes the current `OnboardingEvaluation` as a `@Published` property.
//   - Handles the "Grant Microphone" action (async prompt) and the
//     "Open System Settings" deep-link for Accessibility.
//   - Polls `PermissionManager.status()` for manual-grant permissions
//     when onboarding is visible (they can only change in System Settings).
//   - Calls `settings.hasCompletedOnboarding = true` on finish.
//
// POLL INTERVAL: 1.5 s [decision: long enough to avoid hammering TCC
//   but short enough that the checkmark appears within ~2 s of a System
//   Settings toggle. 0.5 s was considered but doubled the call rate with no
//   perceivable UX benefit — 1.5 s is the tradeoff point.]
//
// THREADING:
//   - `@MainActor` throughout. `requestMicrophone()` is `async` and `await`-ed.
//   - The poll `Task` captures `[weak self]` to avoid a retain cycle.

import AppKit
import Combine
import os
import SpeakCore
import SwiftUI

// MARK: - OnboardingViewModel

@MainActor
final class OnboardingViewModel: ObservableObject {

    // MARK: - Published state

    /// The current evaluation result (step, completeness, blockers).
    @Published private(set) var evaluation: OnboardingEvaluation

    /// `true` while `requestMicrophone()` is in-flight (shows a spinner).
    @Published private(set) var isRequestingMic: Bool = false

    /// `true` once the user has fired the hotkey at least once during the hotkey step.
    /// Turns the "Try it now" pill green.
    @Published private(set) var hotkeyTriggered: Bool = false

    /// `true` for Accessibility after the first tap — TCC prompt has been fired,
    /// waiting for the user to toggle the switch in System Settings.
    /// Used by the view to disable the primary button and show "Waiting…" label.
    @Published private(set) var isWaitingForAccessibility: Bool = false

    // MARK: - Live hotkey display string

    /// The human-readable description of the current hotkey binding gesture.
    ///
    /// Derived from `UserDefaultsBindingStore` (the same key the monitor reads) so
    /// onboarding always shows the user's persisted choice. The trigger is mirrored
    /// from `settings.triggerMode` — `SettingsStore` is the authoritative source for
    /// the effective trigger (the monitor applies it via `HotkeyBinding.with(trigger:)`
    /// on start). Falls back to `HotkeyBinding.defaultBinding.displayString` when no
    /// persisted binding exists (first run).
    ///
    /// Examples: "⌘⌘ Right Command", "Fn ×2", "⌘ Right Command (hold)".
    ///
    /// Cached as a `@Published` property so SwiftUI body re-renders read an already-
    /// computed value instead of allocating a `UserDefaultsBindingStore` and hitting
    /// UserDefaults on every body evaluation. Refreshed in `refreshEvaluation()` and
    /// at `init` time.
    ///
    /// [decision: read UserDefaultsBindingStore in-seam — avoids an out-of-seam
    ///  dependency on DictationController while producing the same value. 2026-06-22]
    /// [decision: cached @Published — no hotkey rebind is expected during onboarding;
    ///  refreshEvaluation() is called after every user action, covering the trigger-
    ///  mode change path. benchmark.md §7]
    @Published private(set) var currentHotkeyDisplayString: String = ""

    // MARK: - Private

    private let permissionManager: any PermissionManaging
    private let settings: SettingsStore

    /// The displayed step while navigating forward. Starts at `.welcome` so
    /// the user sees the title card first, regardless of permission state.
    @Published private(set) var displayedStep: OnboardingStep = .welcome

    /// Tracks which manual-grant permissions have had their TCC registration
    /// prompt fired this session. Guards against re-firing `AXIsProcessTrustedWithOptions`
    /// on subsequent taps (which would spawn a second system dialog).
    ///
    /// A `true` entry means the prompt has been shown; subsequent taps only open
    /// System Settings, never re-trigger the TCC dialog.
    private var hasPrompted: Set<PermissionKind> = []

    /// Backing poll task — cancelled when the view model is deallocated.
    private var pollTask: Task<Void, Never>?

    /// Task that subscribes to the hotkey-fired publisher for the "Try it now" pill.
    /// Cancelled on disappear (along with pollTask) so it doesn't outlive the window.
    private var hotkeyListenTask: Task<Void, Never>?

    private let log = SpeakLog.permissions

    // MARK: - Init

    init(permissionManager: any PermissionManaging, settings: SettingsStore) {
        self.permissionManager = permissionManager
        self.settings = settings
        // Evaluate once at init so the initial state is accurate.
        self.evaluation = OnboardingStateMachine.evaluate(
            manager: permissionManager,
            hasCompletedOnboarding: settings.hasCompletedOnboarding
        )
        // Compute the display string once at init rather than on every SwiftUI body
        // render (avoids repeated UserDefaults reads and BindingStore allocations).
        self.currentHotkeyDisplayString = Self.computeHotkeyDisplayString(settings: settings)
    }

    deinit {
        pollTask?.cancel()
        hotkeyListenTask?.cancel()
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

    /// Call when the onboarding window disappears. Stops polling and hotkey listening.
    func onDisappear() {
        pollTask?.cancel()
        pollTask = nil
        hotkeyListenTask?.cancel()
        hotkeyListenTask = nil
    }

    // MARK: - Hotkey live test

    /// Subscribe to a publisher that fires each time the user triggers the hotkey.
    ///
    /// Called by `OnboardingWindowController` so the onboarding flow can show a
    /// live "Try it now" pill (turns green on first trigger).
    ///
    /// The publisher is derived from `DictationController.$icon` (`.listening` edge)
    /// by the caller — no second iterator on `HotkeyMonitor.events` is created here,
    /// so the single-consumer contract on that AsyncStream is preserved.
    ///
    /// [deferred — human verification: that the publisher fires during onboarding
    ///  once AX is granted and the tap is armed.]
    func startListeningForHotkey(publisher: AnyPublisher<Void, Never>) {
        hotkeyListenTask?.cancel()
        hotkeyListenTask = Task { [weak self] in
            // Await each element of the Combine publisher via AsyncPublisher.
            // [verified: AnyPublisher.values (AsyncPublisher) Swift 5.5+, 2026-06-21]
            for await _ in publisher.values {
                guard let self, !Task.isCancelled else { break }
                if !self.hotkeyTriggered {
                    self.hotkeyTriggered = true
                    self.log.info("OnboardingViewModel: hotkey fired during onboarding — pill turned green.")
                }
                // Continue listening so multiple triggers don't accumulate background work;
                // the flag is idempotent (already true), so subsequent fires are cheap no-ops.
            }
        }
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

    /// Primary action for the Accessibility step.
    ///
    /// SINGLE-ACTION DESIGN:
    /// On the first tap: fires `AXIsProcessTrustedWithOptions(prompt:true)` to
    /// **register `speak` in the Accessibility list** and show the system TCC dialog.
    /// The system dialog's own "Open System Settings" button navigates the user to the
    /// correct pane — we do NOT also call `NSWorkspace.open` in the same tap (that was
    /// the double-fire bug). Then the button becomes "Waiting for permission…" (disabled)
    /// so re-tapping cannot spawn a second TCC dialog.
    ///
    /// On subsequent taps (already prompted, not yet granted): calls `openSystemSettings`
    /// only — brings the user back to the pane without re-prompting. This handles the
    /// case where the user dismissed the system dialog without navigating.
    ///
    /// If already granted at tap time: auto-advances immediately (no dialog shown).
    func requestAccessibility() {
        // Already granted — advance immediately without touching TCC.
        if permissionManager.status(.accessibility) == .granted {
            refreshEvaluation()
            advanceStepIfGranted(kind: .accessibility)
            return
        }

        if hasPrompted.contains(.accessibility) {
            // Re-tap after prompt already fired: open Settings only, never re-prompt.
            openSystemSettings(for: .accessibility)
            return
        }

        // First tap: register in Accessibility list + fire TCC dialog (once only).
        hasPrompted.insert(.accessibility)
        isWaitingForAccessibility = true
        let trusted = permissionManager.requestAccessibility()
        refreshEvaluation()
        if trusted {
            // Already trusted (e.g. granted in a prior run). Clear waiting state and advance.
            isWaitingForAccessibility = false
            advanceStepIfGranted(kind: .accessibility)
        }
        // If not trusted: leave isWaitingForAccessibility = true. The poll loop clears it
        // when `.accessibility` transitions to `.granted` and auto-advances the step.
    }

    /// Opens System Settings to the given privacy pane via deep-link.
    ///
    /// Deep-link anchors on macOS 13+ (`Privacy_Accessibility`) open the correct
    /// pane directly.
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
        // Refresh the cached display string in case trigger mode changed.
        currentHotkeyDisplayString = Self.computeHotkeyDisplayString(settings: settings)
    }

    /// Compute the hotkey display string from UserDefaults (reads once per call).
    /// Extracted as a `static` helper so it can be called both from `init` (before
    /// `self` is fully initialised) and from `refreshEvaluation()`.
    private static func computeHotkeyDisplayString(settings: SettingsStore) -> String {
        let base = UserDefaultsBindingStore().load() ?? HotkeyBinding.defaultBinding
        let effective = base.with(trigger: settings.triggerMode)
        return effective.displayString
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
        case .accessibility:  return .hotkey
        case .hotkey:         return .done
        case .done:           return .done
        }
    }

    /// Start polling `PermissionManager.status()` for the Accessibility permission.
    /// The poll runs until onboarding is complete or the view model is deallocated.
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
                // auto-advance and clear any "waiting" state so no stale widget lingers.
                switch self.displayedStep {
                case .accessibility:
                    if self.permissionManager.status(.accessibility) == .granted {
                        self.isWaitingForAccessibility = false
                        self.displayedStep = .hotkey
                    }

                default:
                    break
                }
            }
        }
    }
}
