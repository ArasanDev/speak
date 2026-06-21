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

import AppKit
import SwiftUI
import SpeakCore
import os

// MARK: - DashboardWindowController

@MainActor
final class DashboardWindowController {

    // MARK: - Private

    private var window: NSWindow?
    private let context: DashboardContext
    private let log = SpeakLog.storage

    // MARK: - Init

    init(context: DashboardContext) {
        self.context = context
    }

    // MARK: - Public API

    /// Show the dashboard window, creating it if needed. Brings it to front.
    /// Calling when already visible re-orders it to front (no duplicate window).
    func show() {
        if let existing = window, existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let contentView = DashboardView(context: context)
        let hosting = NSHostingView(rootView: contentView)

        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 880, height: 600),
            styleMask: [.titled, .closable, .resizable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        win.title = "speak"
        win.titlebarAppearsTransparent = false
        win.contentView = hosting
        win.isReleasedWhenClosed = false
        win.setFrameAutosaveName("speak.dashboard")
        win.center()
        self.window = win

        win.makeKeyAndOrderFront(nil)
        // `activate` is required for a menubar-only (LSUIElement) app so the window
        // becomes frontmost rather than appearing behind the active app.
        // [deferred — whether this suffices without a Dock icon needs a live run]
        NSApp.activate(ignoringOtherApps: true)
        log.info("DashboardWindowController: window shown.")
    }

    /// Close the dashboard window.
    func close() {
        window?.close()
        window = nil
        log.info("DashboardWindowController: window closed.")
    }
}
