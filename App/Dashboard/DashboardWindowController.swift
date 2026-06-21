// App/Dashboard/DashboardWindowController.swift
//
// Manages the full-window dashboard NSWindow for the menubar-only (LSUIElement) app.
//
// WHY NSWindow DIRECTLY (not a SwiftUI WindowGroup scene): same rationale as
// HistoryWindowController / OnboardingWindowController — programmatic windows from a
// MenuBarExtra app are unreliable via WindowGroup; an NSWindow + NSHostingView is the
// direct, well-tested approach. [decision: mirrors the existing window controllers]
//
// HONESTY BOUNDARY: whether the window appears frontmost and renders correctly is
// [deferred — needs human verification], like the other windows. Tests assert lazy
// single-instance construction, not live presentation.
//
// THREADING: @MainActor throughout — NSWindow is main-thread-only.
//
// HYBRID FULL-APP ACTIVATION (verified Wispr pattern, 2026-06-21):
//   speak ships LSUIElement=true → it lives in the menubar as the always-on dictation
//   listener with no Dock icon. But the dashboard is the *main application window*, so
//   while it is open the app promotes itself to a regular, Dock-present app with a
//   standard app menu (`NSApp.setActivationPolicy(.regular)`), then demotes back to
//   `.accessory` (menubar-only) when the window closes. This is the macOS-native
//   "menubar tool that becomes a real windowed app on demand" model. We are the
//   NSWindowDelegate so we can observe the close. [decision: research/wispr-flow-ui-verified.md]

import AppKit
import SwiftUI
import SpeakCore
import os

// MARK: - DashboardWindowController

@MainActor
final class DashboardWindowController: NSObject, NSWindowDelegate {

    // MARK: - Private

    private var window: NSWindow?
    private let context: DashboardContext
    private let log = SpeakLog.storage

    // MARK: - Init

    init(context: DashboardContext) {
        self.context = context
        super.init()
    }

    // MARK: - Public API

    /// Show the dashboard window, creating it if needed. Brings it to front and
    /// promotes the app to a regular Dock-present app for the window's lifetime.
    /// Calling when already visible re-orders it to front (no duplicate window).
    func show() {
        // Promote to a real Dock app + app menu while the main window is open.
        promoteToRegularApp()

        if let existing = window, existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let contentView = DashboardView(context: context)
        let hosting = NSHostingView(rootView: contentView)

        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 920, height: 640),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        win.title = "speak"
        win.contentView = hosting
        win.isReleasedWhenClosed = false
        win.setFrameAutosaveName("speak.dashboard")
        win.delegate = self            // observe close → demote back to menubar-only
        win.center()
        self.window = win

        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        log.info("DashboardWindowController: window shown (promoted to .regular).")
    }

    /// Close the dashboard window.
    func close() {
        window?.close()
        // `windowWillClose(_:)` handles demotion; nil-out happens there too.
    }

    // MARK: - NSWindowDelegate

    /// When the main window closes, demote back to menubar-only (.accessory) so the
    /// Dock icon disappears and speak returns to being a background dictation tool.
    func windowWillClose(_ notification: Notification) {
        window = nil
        NSApp.setActivationPolicy(.accessory)
        log.info("DashboardWindowController: window closed (demoted to .accessory).")
    }

    // MARK: - Activation policy

    /// Promote to a regular, Dock-present app with a standard app menu. Idempotent —
    /// AppKit ignores a redundant set to the same policy.
    private func promoteToRegularApp() {
        if NSApp.activationPolicy() != .regular {
            NSApp.setActivationPolicy(.regular)
            log.info("DashboardWindowController: activation policy → .regular (Dock + app menu).")
        }
    }
}
