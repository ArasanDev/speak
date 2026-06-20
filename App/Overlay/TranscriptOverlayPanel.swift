// App/Overlay/TranscriptOverlayPanel.swift
//
// A non-activating floating NSPanel that hosts the partial-transcript SwiftUI view.
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
// COLLECTION BEHAVIOR:
//   `.canJoinAllSpaces`       — visible across all Mission Control spaces.
//   `.fullScreenAuxiliary`    — visible over full-screen apps.
//
// CREATION: the panel is created once (owned by `DictationController`) and
//   shown/hidden per dictation. Do NOT recreate it per dictation — the
//   `NSHostingView` is expensive to set up and the panel retains its position.
//
// POSITION: top-center of the main screen, near the menubar.
//   `yFromTop` = 60 pt — below the menubar (24 pt) + breathing room. [decision]
//   This is the simplest v0 placement; cursor-follow is P4 polish.
//   The 60 pt gap is chosen so the panel clears the macOS 26 menubar + notch
//   on all Apple Silicon Mac configurations. [decision — review at P8 polish]

import AppKit
import SwiftUI
import SpeakCore

// MARK: - Panel subclass

/// A floating, non-activating window that hosts the live partial transcript.
final class TranscriptOverlayPanel: NSPanel {

    // MARK: - Constants

    /// Width of the overlay card. [decision: 340 pt gives ~60 chars at body size]
    private static let panelWidth: CGFloat = 340

    /// Height of the overlay card. [decision: tall enough for ~3 lines of text]
    private static let panelHeight: CGFloat = 80

    /// Distance from the top of the screen to the top edge of the panel. [decision]
    /// Chosen to clear the macOS menubar (~24 pt) plus a comfortable gap.
    private static let yFromTop: CGFloat = 60

    // MARK: - Init

    init(overlayModel: OverlayViewModel) {
        // Step 1: style mask — .nonactivatingPanel is the primary focus-steal guard.
        let mask: NSWindow.StyleMask = [
            .nonactivatingPanel,
            .borderless
        ]

        // Use the main screen; fall back to a unit rect if no screen is available
        // (shouldn't happen on a real Mac, but guard to avoid force-unwrap).
        let screenFrame = NSScreen.main?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        let xCenter = screenFrame.midX - Self.panelWidth / 2
        let yPosition = screenFrame.maxY - Self.yFromTop - Self.panelHeight
        let frame = CGRect(x: xCenter, y: yPosition, width: Self.panelWidth, height: Self.panelHeight)

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

        // Step 3: collection behavior — join all spaces, visible over full-screen.
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        // Step 4: host the SwiftUI overlay view.
        let hostingView = NSHostingView(rootView: TranscriptOverlayView(model: overlayModel))
        hostingView.frame = CGRect(origin: .zero, size: frame.size)
        hostingView.autoresizingMask = [.width, .height]
        self.contentView = hostingView
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

    private func reposition() {
        guard let screen = NSScreen.main else { return }
        let sf = screen.visibleFrame
        let xCenter = sf.midX - Self.panelWidth / 2
        let yPosition = sf.maxY - Self.yFromTop - Self.panelHeight
        setFrameOrigin(CGPoint(x: xCenter, y: yPosition))
    }
}
