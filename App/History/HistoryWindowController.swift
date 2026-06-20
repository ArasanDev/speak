// App/History/HistoryWindowController.swift
//
// Manages the History NSWindow for the menubar-only (LSUIElement) app.
//
// WHY NSWindow DIRECTLY (not a SwiftUI WindowGroup scene):
//   Same rationale as OnboardingWindowController — programmatic windows from a
//   MenuBarExtra app are unreliable via WindowGroup; an NSWindow + NSHostingView
//   is the direct, well-tested approach.
//   [decision: NSWindow + NSHostingView vs WindowGroup scene, mirrors onboarding]
//
// HONESTY BOUNDARY:
//   Whether the window appears in front and renders correctly is
//   [deferred — needs human verification: human-verification.md §4.5].
//
// THREADING: @MainActor throughout — NSWindow is main-thread-only.

import AppKit
import SwiftUI
import SpeakCore
import os

// MARK: - HistoryWindowController

@MainActor
final class HistoryWindowController {

    // MARK: - Private

    private var window: NSWindow?
    private let viewModel: HistoryViewModel
    private let log = SpeakLog.storage

    // MARK: - Init

    init(store: any HistoryStoring) {
        self.viewModel = HistoryViewModel(store: store)
    }

    // MARK: - Public API

    /// Show the History window, creating it if needed. Brings it to front.
    /// Calling when already visible re-orders it to the front (no duplicate).
    func show() {
        if let existing = window, existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let contentView = HistoryView(viewModel: viewModel)
        let hosting = NSHostingView(rootView: contentView)

        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 460),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        win.title = "Dictation History"
        win.contentView = hosting
        win.isReleasedWhenClosed = false
        win.center()
        self.window = win

        win.makeKeyAndOrderFront(nil)
        // `activate` is required for a menubar-only (LSUIElement) app so the
        // window becomes frontmost rather than appearing behind the active app.
        // [deferred — whether this suffices without a Dock icon needs a live run]
        NSApp.activate(ignoringOtherApps: true)
        log.info("HistoryWindowController: window shown.")
    }

    /// Close the History window.
    func close() {
        window?.close()
        window = nil
        log.info("HistoryWindowController: window closed.")
    }
}
