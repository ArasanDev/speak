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
// POSITION (Phase C): bottom-center of the active screen (spec §4).
//   "Active screen" = the screen whose `frame` contains the current mouse
//   location. This is the pragmatic signal used by VoiceInk-class apps: it
//   reliably follows the user without requiring Accessibility API access to the
//   focused window's frame (which can fail and requires an extra permission check).
//   Fallback: `NSScreen.main` (the menu-bar screen) when no screen contains the
//   mouse (edge case: pointer between screens in an unusual layout).
//   [decision: mouse-location-with-fallback per spec §4 + VoiceInk precedent;
//    AX-focused-window approach is more precise but heavier and failure-prone.]
//   [unverified — live multi-display mouse-tracking requires human dogfood.]
//   `yFromBottom` = 24 pt — breathing room above the Dock / screen edge. [decision:
//    spec §4 specifies "~24pt from minY"; matches standard Dock-gap heuristic.]
//   Repositioned on `NSApplication.didChangeScreenParametersNotification` so
//   multi-monitor hot-plug and display layout changes keep the HUD on screen.
//
// CREATION: the panel is created once (owned by `DictationController`) and
//   shown/hidden per dictation. Do NOT recreate it per dictation — the
//   `NSHostingView` is expensive to set up and the panel retains its position.

import AppKit
import SpeakCore
import SwiftUI

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

    init(
        overlayModel: OverlayViewModel,
        onSettingsPressed: @escaping () -> Void = {}
    ) {
        // Step 1: style mask — .nonactivatingPanel is the primary focus-steal guard.
        let mask: NSWindow.StyleMask = [
            .nonactivatingPanel,
            .borderless
        ]

        // Use the active screen (screen containing the mouse cursor); falls back to
        // NSScreen.main then a safe unit rect if no screen is available.
        let frame = Self.frameForActiveScreen()

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
        let hostingView = NSHostingView(
            rootView: TranscriptOverlayView(
                model: overlayModel,
                onSettingsPressed: onSettingsPressed
            )
        )
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
        // Re-center on the active screen at show-time so the HUD follows the cursor.
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

    /// Returns the index of the first screen whose `frame` contains `point`, or
    /// `nil` if no screen does (e.g. pointer between displays in an unusual layout).
    ///
    /// Factored as a pure function over `[CGRect]` so it can be unit-tested with
    /// synthetic screen geometries without requiring real `NSScreen` instances.
    ///
    /// Selection uses each screen's `frame` (full physical bounds) rather than
    /// `visibleFrame` because the mouse cursor can sit in the Dock/menu-bar band
    /// that is excluded from `visibleFrame`. The bottom-center placement math is
    /// then applied against that screen's `visibleFrame`.
    ///
    /// `NSEvent.mouseLocation` and `NSScreen.frame` share the same global screen
    /// coordinate space (bottom-left origin, y-up on macOS), so no coordinate
    /// conversion is needed. [verified: swiftc -typecheck against macOS 26 SDK]
    ///
    /// [unverified — live multi-display mouse-tracking requires human dogfood.]
    nonisolated static func indexOfScreen(containing point: CGPoint, frames: [CGRect]) -> Int? {
        frames.firstIndex { $0.contains(point) }
    }

    /// Compute the panel frame anchored to the bottom-center of the active screen's
    /// visible frame. The active screen is the one whose physical `frame` contains
    /// the current mouse location — the pragmatic, reliable signal for "the screen
    /// the user is working on." Falls back to `NSScreen.main` (the menu-bar screen)
    /// if no screen contains the mouse, then to a safe default if no screen exists.
    ///
    /// [decision: mouse-location-with-fallback; see §POSITION comment above.]
    /// [unverified — live multi-display mouse-tracking requires human dogfood.]
    private static func frameForActiveScreen() -> CGRect {
        let mousePoint = NSEvent.mouseLocation  // [verified: macOS 26 SDK]
        let allScreens = NSScreen.screens       // [verified: macOS 26 SDK]

        // Pick the screen containing the mouse; fall back to NSScreen.main.
        let activeScreen: NSScreen?
        if let idx = indexOfScreen(containing: mousePoint, frames: allScreens.map(\.frame)) {
            activeScreen = allScreens[idx]
        } else {
            activeScreen = NSScreen.main
        }

        // Use visibleFrame for placement so we respect the Dock and menu-bar insets.
        let sf = activeScreen?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        let xCenter = sf.midX - panelWidth / 2
        // Bottom-center: `minY` is the screen's lowest visible point (above Dock).
        // [decision: +24 pt gap per spec §4 — ~24pt from minY.]
        let yPosition = sf.minY + yFromBottom
        return CGRect(x: xCenter, y: yPosition, width: panelWidth, height: panelHeight)
    }

    private func reposition() {
        let newOrigin = Self.frameForActiveScreen().origin
        setFrameOrigin(newOrigin)
    }
}
