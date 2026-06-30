// App/Settings/SettingsWindowController.swift
//
// Manages the Settings NSWindow for the menubar-only (LSUIElement) app.
//
// WHY NSWindow DIRECTLY (not a SwiftUI Settings scene):
//   SwiftUI's `Settings` scene and `SettingsLink` are designed for foreground apps.
//   From a menubar-only (LSUIElement) app, NSWindow + NSHostingView is the direct
//   approach — same pattern as OnboardingWindowController and HistoryWindowController.
//   [decision: NSWindow + NSHostingView vs Settings scene, mirrors onboarding/history]
//
// WHY setActivationPolicy(.regular) on show:
//   LSUIElement apps have .accessory policy — NSApp.activate() alone won't bring
//   windows to front reliably on macOS 13+. Temporarily switching to .regular on
//   show (and back to .accessory on close) is the documented workaround for
//   menubar-only apps that need to surface a panel. [decision: activation-policy-swap]
//
// WINDOW SIZE: 900 × 560 — matches SettingsView's 7-tab layout requirement.
//   [decision: PE-2 — wider than the old 560px to accommodate the AI Studio editor]
//
// THREADING: @MainActor throughout — NSWindow is main-thread-only.

import AppKit
import os
import SpeakCore
import SwiftUI

// MARK: - SettingsWindowController

@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {

    // MARK: - Private

    private var window: NSWindow?
    private let controller: DictationController
    private let log = SpeakLog.engine

    // MARK: - Init

    init(controller: DictationController) {
        self.controller = controller
    }

    // MARK: - Public API

    /// Show the Settings window, creating it if needed. Brings it to front.
    /// Calling when already visible re-orders it to the front (no duplicate).
    func show() {
        if let existing = window, existing.isVisible {
            bringToFront(existing)
            return
        }

        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 560),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        win.title = "speak — Settings"
        win.contentView = NSHostingView(rootView: SettingsView(controller: controller))
        win.isReleasedWhenClosed = false
        win.delegate = self
        win.center()
        self.window = win

        bringToFront(win)
        log.info("SettingsWindowController: window shown.")
    }

    /// Close the Settings window and restore accessory activation policy.
    func close() {
        window?.close()
    }

    // MARK: - NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        window = nil
        // Restore menubar-only policy so speak doesn't appear in the Dock or Cmd+Tab.
        NSApp.setActivationPolicy(.accessory)
        log.info("SettingsWindowController: window closed, policy restored to .accessory.")
    }

    // MARK: - Private

    /// Temporarily promote to .regular so the window surfaces above any foreground app,
    /// then make it key. On close, windowWillClose restores .accessory.
    private func bringToFront(_ win: NSWindow) {
        NSApp.setActivationPolicy(.regular)
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
