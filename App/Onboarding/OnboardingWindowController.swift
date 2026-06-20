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
import SpeakCore
import os

// MARK: - OnboardingWindowController

@MainActor
final class OnboardingWindowController {

    // MARK: - Private

    private var window: NSWindow?
    private let viewModel: OnboardingViewModel
    private let log = SpeakLog.permissions

    // MARK: - Init

    init(permissionManager: PermissionManager, settings: SettingsStore) {
        self.viewModel = OnboardingViewModel(
            permissionManager: permissionManager,
            settings: settings
        )
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

        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 400),
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

    /// Polls the view model's `evaluation.isComplete` to auto-close the window
    /// once onboarding finishes (finish() / skip() path).
    ///
    /// This replaces a Combine subscription to keep the App target free of
    /// Combine for this thin coordinator (OnboardingViewModel does the state work).
    /// The poll runs at 0.5 s cadence — just for the close event, not for TCC.
    /// [decision: 0.5 s close-watch poll — close-latency vs overhead tradeoff]
    private func watchForCompletion() {
        let closeWatchIntervalNanoseconds: UInt64 = 500_000_000 // 0.5 s [decision above]
        Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: closeWatchIntervalNanoseconds)
                guard let self else { break }
                if self.viewModel.displayedStep == .done {
                    // Brief pause so the "You're all set!" screen is visible.
                    // Duration: 1.5 s [decision: enough to read the text, not so long
                    // it feels like the app froze. 1.0 s tested too brief for comfort.]
                    try? await Task.sleep(nanoseconds: 1_500_000_000)
                    self.close()
                    break
                }
            }
        }
    }

    // MARK: - Window close delegate bridge

    /// A thin NSWindowDelegate that logs when the user closes the window manually.
    private lazy var windowCloseDelegate: WindowCloseDelegate = WindowCloseDelegate(log: log)
}

// MARK: - WindowCloseDelegate

/// Minimal `NSWindowDelegate` — logs user-initiated close (the X button).
/// This is intentional: closing the onboarding window manually is equivalent
/// to "skip" — the user dismissed it. The `hasCompletedOnboarding` flag is NOT
/// set here; that only happens via `OnboardingViewModel.finish()` or `.skip()`.
private final class WindowCloseDelegate: NSObject, NSWindowDelegate, @unchecked Sendable {
    private let log: Logger

    init(log: Logger) {
        self.log = log
    }

    func windowWillClose(_ notification: Notification) {
        log.info("OnboardingWindowController: user closed the onboarding window manually.")
    }
}
