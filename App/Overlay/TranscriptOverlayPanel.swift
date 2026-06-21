// App/Overlay/TranscriptOverlayPanel.swift
//
// A non-activating floating NSPanel that hosts the recording HUD SwiftUI view.
//
// FOCUS-STEAL PREVENTION (load-bearing — P4 core requirement):
//   The overlay must NEVER steal keyboard focus from the app the user is dictating
//   into (e.g. TextEdit, Slack). We achieve this via every required layer:
//
//   1. NSPanel subclass with `.nonactivatingPanel` in the styleMask — the system
//      won't activate this window even on click.
//   2. `isFloatingPanel = true` — kept above normal windows without focus change.
//   3. `hidesOnDeactivate = false` — stays visible when another app is frontmost.
//   4. `level = .floating` — floats above regular windows but below system UI.
//   5. `canBecomeKey` → false  — cannot receive keyboard events.
//   6. `canBecomeMain` → false — cannot become the main window.
//   7. Show via `orderFrontRegardless()` (NOT `makeKeyAndOrderFront`) — required
//      from LSUIElement (accessory) apps where `NSApp.activate` is not called.
//   8. Hide via `orderOut(nil)`.
//
//   Consequence: keyboard events always reach the *actually-focused* app.
//
// COLLECTION BEHAVIOR (Phase C additions):
//   `.canJoinAllSpaces`       — visible across all Mission Control spaces.
//   `.fullScreenAuxiliary`    — visible over full-screen apps.
//   `.stationary`             — does not move with Exposé/Mission Control sweeps.
//   `.ignoresCycle`           — excluded from Cmd+` window cycling.
//   [decision: .stationary + .ignoresCycle added in Phase C per spec §4 — VoiceInk
//    and Hex both set these to prevent the HUD from interfering with the user's
//    window management while dictating. benchmark.md §7.]
//
// POSITION (Phase C): bottom-center of the focused screen (spec §4).
//   VoiceInk, Wispr, and Handy all anchor to bottom-center; top placement risks
//   collision with the menubar or notch on MacBook. [decision: spec §4 consensus]
//   `yFromBottom` = 24 pt — breathing room above the Dock / screen edge. [decision:
//    spec §4 specifies "~24pt from minY"; matches standard Dock-gap heuristic.]
//   Repositioned on `NSApplication.didChangeScreenParametersNotification` so
//   multi-monitor hot-plug and display layout changes keep the HUD on screen.
//
// CREATION: the panel is created once (owned by `DictationController`) and
//   shown/hidden per dictation. Do NOT recreate it per dictation — the
//   `NSHostingView` is expensive to set up and the panel retains its position.

import AppKit
import SwiftUI
import SpeakCore

// MARK: - Panel subclass

/// A floating, non-activating window that hosts the live recording HUD.
final class TranscriptOverlayPanel: NSPanel {

    // MARK: - Constants

    /// Width of the overlay card. [decision: 340 pt gives ~60 chars at body size]
    private static let panelWidth: CGFloat = 340

    /// Height of the overlay card. [decision: 80 pt — tall enough for ~3 lines of text
    ///  plus the level meter row; matches original height.]
    private static let panelHeight: CGFloat = 80

    /// Distance from the bottom of the visible frame to the bottom edge of the panel.
    /// [decision: spec §4 specifies "~24pt from minY"; clears Dock + standard margin.]
    private static let yFromBottom: CGFloat = 24

    // MARK: - Screen change observer

    /// Token returned by `NotificationCenter.addObserver(forName:...)`. Stored so
    /// we can remove it in `deinit` and avoid a leak. [decision: block-based observer
    ///  with [weak self] capture; removed in deinit per macOS notification best practice.]
    private var screenChangeObserver: (any NSObjectProtocol)?

    // MARK: - Init

    init(overlayModel: OverlayViewModel) {
        // Step 1: style mask — .nonactivatingPanel is the primary focus-steal guard.
        let mask: NSWindow.StyleMask = [
            .nonactivatingPanel,
            .borderless
        ]

        // Use the main screen; fall back to a unit rect if no screen is available
        // (shouldn't happen on a real Mac, but guard to avoid force-unwrap).
        let frame = Self.frameForMainScreen()

        super.init(
            contentRect: frame,
            styleMask: mask,
            backing: .buffered,
            defer: true  // defer creation until the panel is first shown
        )

        // Step 2: panel-level attributes for floating + no-focus-steal.
        self.isFloatingPanel = true
        self.hidesOnDeactivate = false
        self.level = .floating
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = true

        // Step 3: collection behavior — join all spaces, visible over full-screen,
        // stationary during Mission Control, excluded from window cycling. (Phase C)
        self.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .stationary,       // [decision] spec §4 — Phase C addition
            .ignoresCycle      // [decision] spec §4 — Phase C addition
        ]

        // Step 4: host the SwiftUI recording HUD view.
        let hostingView = NSHostingView(rootView: TranscriptOverlayView(model: overlayModel))
        hostingView.frame = CGRect(origin: .zero, size: frame.size)
        hostingView.autoresizingMask = [NSView.AutoresizingMask.width, NSView.AutoresizingMask.height]
        self.contentView = hostingView

        // Step 5: reposition when screen geometry changes (multi-monitor / resolution).
        screenChangeObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.reposition()
        }
    }

    deinit {
        if let observer = screenChangeObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    // MARK: - Focus-steal guards (Step 5 + 6)

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    // MARK: - Show / Hide

    /// Show the panel (non-activating — does NOT steal focus).
    func show() {
        // Re-center on the current main screen in case the user moved windows.
        reposition()
        // `orderFrontRegardless()` brings the panel to front from an LSUIElement
        // app without activating it. `makeKeyAndOrderFront` must NOT be used here.
        orderFrontRegardless()
    }

    /// Hide the panel.
    func hide() {
        orderOut(nil)
    }

    // MARK: - Private

    /// Compute the panel frame anchored to the bottom-center of the main screen's
    /// visible frame. Falls back to a safe default if no screen is available.
    private static func frameForMainScreen() -> CGRect {
        let sf = NSScreen.main?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        let xCenter = sf.midX - panelWidth / 2
        // Bottom-center: `minY` is the screen's lowest visible point (above Dock).
        // [decision: +24 pt gap per spec §4 — ~24pt from minY.]
        let yPosition = sf.minY + yFromBottom
        return CGRect(x: xCenter, y: yPosition, width: panelWidth, height: panelHeight)
    }

    private func reposition() {
        let newOrigin = Self.frameForMainScreen().origin
        setFrameOrigin(newOrigin)
    }
}
