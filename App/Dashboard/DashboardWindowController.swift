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
import Combine
import os
import SpeakCore
import SwiftUI

// MARK: - DashboardWindowController

@MainActor
final class DashboardWindowController: NSObject, NSWindowDelegate {

    // MARK: - Private

    private var window: NSWindow?
    /// `var` so that `updateHotkeyCombo(_:)` can refresh the combo before each show().
    /// DashboardContext is a value-type bundle; the new combo is picked up by the
    /// NSHostingView created at the start of the next show() call.
    private var context: DashboardContext
    private let initialSection: DashboardSection
    private let log = SpeakLog.storage

    // MARK: - Init

    init(context: DashboardContext, initialSection: DashboardSection = .home) {
        self.context = context
        self.initialSection = initialSection
        super.init()
    }

    // MARK: - Public API

    /// Refresh the stored hotkey combo, engine/permissions, and publisher so the next show() call
    /// picks up current bindings and controller state. Call this from `WindowPresenter.showDashboard()`
    /// before `show()` so a hotkey rebind is reflected the next time the window opens.
    /// [decision: update-before-show is safe because context is consumed only inside
    ///  show(); if the window is already visible, the update takes effect on re-open.]
    func updateContext(
        hotkeyCombo: [String]? = nil,
        speakEngine: SpeakEngine? = nil,
        permissionManager: PermissionManager? = nil,
        dictationCompletedPublisher: AnyPublisher<Void, Never>? = nil
    ) {
        if let hotkeyCombo {
            context.hotkeyCombo = hotkeyCombo
        }
        if let speakEngine {
            context.speakEngine = speakEngine
        }
        if let permissionManager {
            context.permissionManager = permissionManager
        }
        if let dictationCompletedPublisher {
            context.dictationCompletedPublisher = dictationCompletedPublisher
        }
    }

    /// Legacy method — calls updateContext with hotkeyCombo only. Kept for compatibility.
    func updateHotkeyCombo(_ combo: [String]) {
        updateContext(hotkeyCombo: combo)
    }

    /// Show the dashboard window, creating it if needed. Brings it to front and
    /// promotes the app to a regular Dock-present app for the window's lifetime.
    /// Calling when already visible re-orders it to front (no duplicate window).
    func show() {
        if let existing = window, existing.isVisible {
            // Already visible — bring to front without re-promoting (already .regular).
            bringToFront(existing)
            return
        }

        // Promote to a real Dock app + app menu while the main window is open.
        // The return value tells us whether the policy actually changed so we can
        // decide whether to defer the front-ordering by one runloop turn.
        let didPromote = promoteToRegularApp()

        let contentView = DashboardView(context: context, initialSection: initialSection)
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
        // A menubar app's window should open on the user's CURRENT Space, not whichever
        // Space it was first created on. [decision: moveToActiveSpace — matches how
        // menubar-app windows are expected to appear.]
        win.collectionBehavior.insert(.moveToActiveSpace)
        win.center()
        self.window = win

        if didPromote {
            // The activation-policy change needs one runloop pass to propagate before
            // the window can reliably surface above the previously-focused app.
            // `DispatchQueue.main.async` gives AppKit that single pass without sleeping.
            // [decision: one async hop is the minimum deterministic delay; no magic
            //  number — this is a single enqueue, not a duration.]
            // [unverified — human dogfood required: whether one hop suffices on all
            //  macOS 26 builds; extend if the window still loses the race in practice.]
            DispatchQueue.main.async { [weak self] in
                guard let self, let w = self.window else { return }
                self.bringToFront(w)
            }
        } else {
            // Policy was already .regular (e.g. another window is open) — no race.
            bringToFront(win)
        }
        log.info("DashboardWindowController: window shown (promoted=\(didPromote, privacy: .public)).")
    }

    /// Close the dashboard window.
    func close() {
        window?.close()
        // `windowWillClose(_:)` handles demotion; nil-out happens there too.
    }

    // MARK: - NSWindowDelegate

    /// When the dashboard window closes, demote back to menubar-only (.accessory) so the
    /// Dock icon disappears and speak returns to being a background dictation tool —
    /// but ONLY if no other visible titled window is still open and we are currently .regular.
    /// Skipping demotion when another window is visible prevents yanking the Dock icon
    /// out from under an open History or Settings window.
    ///
    /// SAFETY NOTE (Bug 4): `DashboardWindowController` holds no reference to
    /// `HotkeyMonitor`, `SpeakEngine`, or `DictationController`. Closing this window
    /// cannot reach or disarm the `CGEventTap`. The menubar app and hotkey remain alive.
    func windowWillClose(_ notification: Notification) {
        window = nil
        // Guard: only demote if currently .regular and no other visible titled window
        // will be left open after this one closes.
        guard NSApp.activationPolicy() == .regular else { return }
        let otherVisible = NSApp.windows.contains { w in
            w !== (notification.object as? NSWindow) && w.isVisible && !w.title.isEmpty
        }
        guard !otherVisible else {
            log.info("DashboardWindowController: window closed — demotion skipped (other windows visible).")
            return
        }
        NSApp.setActivationPolicy(.accessory)
        log.info("DashboardWindowController: window closed (demoted to .accessory).")
    }

    // MARK: - Private helpers

    /// Activate the app then order the window to front.
    /// Activates FIRST so the app is the frontmost process before the window
    /// requests key status — prevents the window landing behind the previously-active
    /// app. [decision: activate-then-orderFront is the correct sequence for a
    /// backgrounded LSUIElement app surfacing a window.]
    private func bringToFront(_ win: NSWindow) {
        NSApp.activate(ignoringOtherApps: true)
        win.makeKeyAndOrderFront(nil)
    }

    /// Promote to a regular, Dock-present app with a standard app menu.
    /// - Returns: `true` if the policy was actually changed (`.accessory` → `.regular`);
    ///            `false` if it was already `.regular` (idempotent, no-op).
    @discardableResult
    private func promoteToRegularApp() -> Bool {
        guard NSApp.activationPolicy() != .regular else { return false }
        NSApp.setActivationPolicy(.regular)
        log.info("DashboardWindowController: activation policy → .regular (Dock + app menu).")
        return true
    }
}
