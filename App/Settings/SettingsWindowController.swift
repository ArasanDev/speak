// App/Settings/SettingsWindowController.swift
//
// Manages the Settings NSWindow for the menubar-only (LSUIElement) app.
//
// WHY NSWindow DIRECTLY (not a SwiftUI Settings scene):
//   SwiftUI's `Settings` scene and `SettingsLink` are designed for foreground apps.
//   From a menubar-only (LSUIElement) app, programmatic window control via
//   NSWindow + NSHostingView is the direct, well-tested approach — same pattern
//   as OnboardingWindowController and HistoryWindowController.
//   [decision: NSWindow + NSHostingView vs Settings scene, mirrors onboarding/history]
//
// HONESTY BOUNDARY:
//   Whether the window appears in front and renders correctly is
//   [deferred — needs human verification: human-verification.md §4.5].
//
// THREADING: @MainActor throughout — NSWindow is main-thread-only.

import AppKit
import os
import SpeakCore
import SwiftUI

// MARK: - SettingsWindowController

@MainActor
final class SettingsWindowController {

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
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let contentView = SettingsView(controller: controller)
        let hosting = NSHostingView(rootView: contentView)

        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 480),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        win.title = "speak — Settings"
        win.contentView = hosting
        win.isReleasedWhenClosed = false
        win.center()
        self.window = win

        win.makeKeyAndOrderFront(nil)
        // `activate` is required for a menubar-only (LSUIElement) app so the
        // window becomes frontmost rather than appearing behind the active app.
        // [deferred — whether this suffices without a Dock icon needs a live run]
        NSApp.activate(ignoringOtherApps: true)
        log.info("SettingsWindowController: window shown.")
    }

    /// Close the Settings window.
    func close() {
        window?.close()
        window = nil
        log.info("SettingsWindowController: window closed.")
    }
}
