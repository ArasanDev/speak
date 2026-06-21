// App/Onboarding/OnboardingWindowController.swift
//
// Manages the onboarding NSWindow for a menubar-only (LSUIElement) app.
//
// WHY NSWindow DIRECTLY (not a SwiftUI WindowGroup scene):
//   A `WindowGroup` / `Window` scene opened programmatically from `openWindow`
//   in a MenuBarExtra app is unreliable — it requires the window ID to be known
//   at compile time and the WindowGroup's side effects (e.g., visible in the
//   Dock task switcher) can be unexpected for a pure menubar app.
//   An NSWindow backed by a SwiftUI view via `NSHostingView` is the direct,
//   well-tested approach for a menubar-only app that needs a transient window.
//   [decision: NSWindow + NSHostingView vs WindowGroup scene, 2026-06-21]
//
// HONESTY BOUNDARY:
//   Whether the window appears in front, takes focus correctly, and looks right
//   is [deferred — needs human verification: human-verification.md §4.4].
//
// THREADING:
//   @MainActor throughout — NSWindow must only be touched on the main thread.

import AppKit
import SwiftUI
import Combine
import SpeakCore
import os

// MARK: - OnboardingWindowController

@MainActor
final class OnboardingWindowController {

    // MARK: - Private

    private var window: NSWindow?
    private let viewModel: OnboardingViewModel
    private let hotkeyFiredPublisher: AnyPublisher<Void, Never>?

    /// Task owning the auto-close countdown after the Done step is shown.
    /// Cancelled if the user clicks away (windowDidResignKey) before it fires.
    private var autoCloseTask: Task<Void, Never>?

    /// Called once — on the main thread — immediately after the onboarding window
    /// auto-closes following the `.done` step. Used by `WindowPresenter` to open
    /// the dashboard on first completion. Not fired on manual close or skip.
    ///
    /// "First-completion only" is free: the caller sets this once at construction
    /// time; subsequent launches never reach `.done` auto-close because
    /// `hasCompletedOnboarding == true` causes `showOnboardingIfNeeded()` to skip.
    var onCompletion: (() -> Void)?

    private let log = SpeakLog.permissions

    // MARK: - Init

    /// `hotkeyFiredPublisher` fires (on the main thread) each time the user triggers
    /// the hotkey during onboarding. Derived from `DictationController.$icon` by the
    /// caller — no second iterator on `HotkeyMonitor.events` is created here.
    /// Pass `nil` in tests or when the monitor is not yet running.
    init(
        permissionManager: PermissionManager,
        settings: SettingsStore,
        hotkeyFiredPublisher: AnyPublisher<Void, Never>? = nil
    ) {
        self.viewModel = OnboardingViewModel(
            permissionManager: permissionManager,
            settings: settings
        )
        self.hotkeyFiredPublisher = hotkeyFiredPublisher
    }

    // MARK: - Public API

    /// Shows the onboarding window, creating it if needed. Brings it to front.
    ///
    /// Calling when already visible is a no-op (brings to front).
    func show() {
        if let existing = window, existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let contentView = OnboardingView(viewModel: viewModel)
        let hosting = NSHostingView(rootView: contentView)

        // Height: 460pt [decision: matches OnboardingView.frame height, W1.2 — accommodates
        // conflict card + try pill on the hotkey step without clipping other steps.]
        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 460),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        win.title = "Welcome to speak"
        win.contentView = hosting
        win.isReleasedWhenClosed = false
        win.center()

        // Observe the `done` step — close the window automatically once the
        // view model transitions to `.done` (finish() or skip() was called).
        win.delegate = windowCloseDelegate
        self.window = win

        win.makeKeyAndOrderFront(nil)
        // `activate` is required for a menubar-only (LSUIElement) app: without it
        // the window appears but the app does not become the frontmost application,
        // so the window may appear behind the current app.
        // [deferred — whether this is sufficient without a Dock icon needs a live run]
        NSApp.activate(ignoringOtherApps: true)
        log.info("OnboardingWindowController: window shown.")

        // Wire the live hotkey test publisher if we have one.
        if let publisher = hotkeyFiredPublisher {
            viewModel.startListeningForHotkey(publisher: publisher)
        }

        // Watch for evaluation → done so we can auto-close.
        watchForCompletion()
    }

    /// Hides the onboarding window.
    func close() {
        window?.close()
        window = nil
        log.info("OnboardingWindowController: window closed.")
    }

    // MARK: - Private

    /// Watches for the Done step and schedules an auto-close after a brief pause
    /// so the "You're all set!" screen is visible. The close task is cancellable:
    /// if the user clicks away (windowDidResignKey) before the delay expires, we
    /// cancel and leave the window open — they may return to it.
    ///
    /// Named constant for the delay:
    ///   `doneAutoCloseDelayNanoseconds` — 2.5 s
    ///   [decision: enough to read "You're all set." comfortably; DoneStepView copy
    ///    promises auto-close, so it must not feel frozen. 2.0 s was the lower bound
    ///    considered; 3.0 s felt long after repeated runs. 2.5 s is the tradeoff.]
    ///
    /// Poll cadence 0.5 s [decision: close-latency vs overhead; same as before].
    private func watchForCompletion() {
        // Named constant: 2.5 s auto-close delay after Done step [decision above].
        let doneAutoCloseDelayNanoseconds: UInt64 = 2_500_000_000
        // Poll cadence: 0.5 s [decision: close-latency vs overhead tradeoff]
        let closeWatchIntervalNanoseconds: UInt64 = 500_000_000
        Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: closeWatchIntervalNanoseconds)
                guard let self else { break }
                if self.viewModel.displayedStep == .done {
                    // Store a cancellable reference so windowDidResignKey can cancel it.
                    let closeTask = Task { [weak self] in
                        try? await Task.sleep(nanoseconds: doneAutoCloseDelayNanoseconds)
                        guard !Task.isCancelled else { return }
                        await MainActor.run { [weak self] in
                            guard let self else { return }
                            self.close()
                            // Fire after close() so the onboarding window is gone before
                            // the dashboard promotion to .regular happens. One runloop
                            // turn is NOT inserted here — DashboardWindowController.show()
                            // already does `DispatchQueue.main.async` when it promotes to
                            // .regular, providing the sequencing buffer.
                            self.onCompletion?()
                        }
                    }
                    self.autoCloseTask = closeTask
                    break
                }
            }
        }
    }

    // MARK: - Window close delegate bridge

    /// A thin NSWindowDelegate that logs when the user closes the window manually
    /// and cancels the auto-close task if the user clicks away from the Done step.
    private lazy var windowCloseDelegate: WindowCloseDelegate = WindowCloseDelegate(
        log: log,
        onResignKey: { [weak self] in
            // Cancel the pending auto-close if the user clicks away.
            // The window stays open — they can return and read it.
            self?.autoCloseTask?.cancel()
            self?.autoCloseTask = nil
        }
    )

#if DEBUG
    // MARK: - Debug (verification harness only)

    /// Shows the onboarding window forced to a specific step. The normal
    /// permission-gated polling and the auto-close watchForCompletion task are
    /// both suppressed so the step stays visible for screenshotting regardless
    /// of TCC state or step completion.
    ///
    /// Called only from `DebugLaunchDispatcher`. Never compiled into release builds.
    func showForcedStep(_ step: OnboardingStep) {
        // Force the VM step first (suppresses polling inside forceStep()).
        viewModel.forceStep(step)

        if let existing = window, existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let contentView = OnboardingView(viewModel: viewModel)
        let hosting = NSHostingView(rootView: contentView)

        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 460),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        win.title = "Welcome to speak (debug)"
        win.contentView = hosting
        win.isReleasedWhenClosed = false
        win.center()
        self.window = win

        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        // Note: watchForCompletion() is intentionally NOT called here so the
        // window does not auto-close when the step is .done.
        log.info("OnboardingWindowController [DEBUG]: window shown forced to step \(String(describing: step), privacy: .public)")
    }
#endif
}

// MARK: - WindowCloseDelegate

/// Minimal `NSWindowDelegate` — logs user-initiated close (the X button) and
/// fires `onResignKey` when the window loses key focus (e.g., user clicks away).
///
/// Closing the onboarding window manually is equivalent to "skip" — the user
/// dismissed it. The `hasCompletedOnboarding` flag is NOT set here; that only
/// happens via `OnboardingViewModel.finish()` or `.skip()`.
private final class WindowCloseDelegate: NSObject, NSWindowDelegate, @unchecked Sendable {
    private let log: Logger
    private let onResignKey: () -> Void

    init(log: Logger, onResignKey: @escaping () -> Void) {
        self.log = log
        self.onResignKey = onResignKey
    }

    func windowWillClose(_ notification: Notification) {
        log.info("OnboardingWindowController: user closed the onboarding window manually.")
    }

    /// Cancel the pending auto-close if the user clicks away from the Done step.
    func windowDidResignKey(_ notification: Notification) {
        onResignKey()
    }
}
