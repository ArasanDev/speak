// App/Overlay/CaretOverlayController.swift
//
// A lightweight floating NSPanel anchored near the text insertion cursor,
// showing the live partial transcript while the user dictates.
//
// Falls back silently when CaretLocator returns nil (browsers, Electron,
// secure fields, terminal emulators). No warning log, no crash — the main
// HUD at the bottom of the screen already shows the partial text; this is
// an additive convenience, not load-bearing.
//
// Threading: @MainActor throughout. CaretLocator.caretScreenPosition requires
// the main thread and this controller is only called from DictationController
// (also @MainActor).
//
// Positioning [unverified — live placement requires human dogfood]:
//   CaretLocator returns Quartz screen coords (top-left origin, y-down).
//   AppKit window coords use bottom-left origin (y-up). Flip:
//     screenHeight = NSScreen.main?.frame.height ?? 0
//     appKitY = screenHeight - caretPoint.y
//   Panel is placed 8pt below the caret (appKitY - panelHeight - 8) unless
//   the caret is in the bottom 20% of the screen, in which case it appears
//   8pt above (appKitY + 8). Panel x is clamped to screen bounds.
//
// [decision P2.2: panel width 280 pt, height 36 pt — single-line partial
//  preview; matches brief spec. benchmark.md §7]

import AppKit
import SpeakCore
import SwiftUI

// MARK: - CaretOverlayModel

@Observable
@MainActor
final class CaretOverlayModel {
    var partialText: String = ""
    var isProcessing: Bool = false
}

// MARK: - CaretOverlayView

struct CaretOverlayView: View {
    let model: CaretOverlayModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        bodyText
            .font(.system(size: 13, design: .monospaced))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(.ultraThinMaterial)
            )
            // Suppress from VoiceOver — the main HUD already exposes
            // partialText with .updatesFrequently; double-speaking is worse.
            .accessibilityHidden(true)
            .transition(reduceMotion ? .identity : .opacity)
    }

    @ViewBuilder
    private var bodyText: some View {
        if model.isProcessing {
            Text("\(Text(displayText))\(Text(" \u{27F3}").font(.system(size: 11)).foregroundStyle(.tertiary))")
        } else {
            Text(displayText)
        }
    }

    private var displayText: String {
        let text = model.partialText
        guard text.count > 60 else { return text.isEmpty ? "\u{2026}" : text }
        return "\u{2026}" + String(text.suffix(60))
    }
}

// MARK: - CaretOverlayController

@MainActor
final class CaretOverlayController {

    // MARK: - Constants

    // [decision P2.2: 280 × 36 pt — single-line; brief spec. benchmark.md §7]
    private static let panelWidth: CGFloat  = 280
    private static let panelHeight: CGFloat = 36
    // [decision P2.2: 8 pt gap from caret to panel edge. benchmark.md §7]
    private static let caretGap: CGFloat    = 8

    /// Terminal emulators report a caret position via AX (the shell cursor),
    /// so `CaretLocator` returns a point even though the feature was designed
    /// to skip them — the mini panel then lands on the prompt and reads as a
    /// stray square (the main capsule already carries the full HUD). Gate on
    /// the frontmost bundle ID instead. [decision: suppress-in-terminal —
    ///  caret preview is designed for text editors, not shells.]
    private static let terminalBundleIDs: Set<String> = [
        "com.apple.Terminal",
        "com.googlecode.iterm2",
        "dev.warp.Warp-Stable",
        "com.mitchellh.ghostty",
        "org.alacritty",
        "net.kovidgoyal.kitty",
        "com.github.wez.wezterm",
    ]

    // MARK: - Internals

    private var panel: NSPanel?
    /// The resolved anchor for this session's panel, computed once at `show()`.
    /// `nil` when the overlay is suppressed for this context (terminal frontmost,
    /// no AX caret, or an implausible point) — `update` then never presents.
    private var pendingCaretPoint: CGPoint?
    // Internal (not private) for @testable access in SpeakTests — tests assert on model state.
    let model = CaretOverlayModel()

    // MARK: - Public API

    /// Show the caret overlay near the cursor in `frontmostPID`.
    ///
    /// The anchor is resolved once here — terminal suppression, AX availability,
    /// and plausibility are all settled in `resolveCaretPoint` — but the panel is
    /// only ordered front once `partialText` is non-empty. An empty state renders
    /// as a ~28pt "…" box that reads as a stray square, not a preview; the first
    /// real partial arrives via `update(partialText:)` and presents the panel at
    /// the resolved anchor. [fix: stray-square]
    ///
    /// Falls back silently when the context can't host a preview (terminal
    /// emulator, no AX caret, degenerate point).
    func show(partialText: String, frontmostPID: pid_t, bundleID: String? = nil) {
        if let bundleID, Self.terminalBundleIDs.contains(bundleID) {
            SpeakLog.input.debug(
                "CaretOverlayController: frontmost is a terminal (\(bundleID, privacy: .public)) — skipping overlay."
            )
            pendingCaretPoint = nil
            return
        }
        model.partialText = partialText
        pendingCaretPoint = Self.resolveCaretPoint(pid: frontmostPID)
        presentIfReady()
    }

    /// Update the displayed partial text. Presents the deferred panel on the
    /// first non-empty partial (see `show`); a no-op for contexts where the
    /// anchor was suppressed. Safe to call when no panel is visible.
    func update(partialText: String) {
        model.partialText = partialText
        presentIfReady()
    }

    /// Switch the panel to the processing state: keep it visible, show rawText
    /// truncated to the same 60-char window as partial, with a ⟳ cleaning suffix.
    /// Does NOT re-query CaretLocator — panel stays at its resolved anchor.
    /// `presentIfReady` covers the deferred case (no partials streamed during
    /// capture but raw text exists at stop, e.g. batch-model engines).
    func showProcessing(rawText: String) {
        model.partialText = rawText
        model.isProcessing = true
        presentIfReady()
        panel?.orderFrontRegardless()
        SpeakLog.input.debug("CaretOverlayController: showProcessing (\(rawText.count, privacy: .public) chars).")
    }

    /// Hide and release the panel.
    func hide() {
        panel?.orderOut(nil)
        panel = nil
        pendingCaretPoint = nil
        model.partialText = ""
        model.isProcessing = false
        SpeakLog.input.debug("CaretOverlayController: hidden.")
    }

    // MARK: - Private

    /// Order the panel front at the resolved anchor, but only once real text
    /// exists and only if it isn't already visible. The empty "…" placeholder
    /// is never presented — see `show`.
    private func presentIfReady() {
        guard !model.partialText.isEmpty,
              let caretPoint = pendingCaretPoint,
              panel?.isVisible != true else { return }
        let panel = ensurePanel()
        let origin = placement(for: caretPoint)
        panel.setFrameOrigin(origin)
        panel.orderFrontRegardless()
        SpeakLog.input.debug(
            "CaretOverlayController: showing at (\(origin.x, privacy: .public), \(origin.y, privacy: .public))"
        )
    }

    /// Resolve the panel anchor once per session. Returns nil when the overlay
    /// should not appear at all: the app exposes no AX caret, or the reported
    /// point is implausible. Terminal suppression happens in `show` (it must
    /// precede the `model.partialText` write).
    private static func resolveCaretPoint(pid: pid_t) -> CGPoint? {
        guard let caretPoint = CaretLocator.caretScreenPosition(pid: pid) else {
            SpeakLog.input.debug("CaretOverlayController: caret unavailable — skipping overlay.")
            return nil
        }

        guard isPlausibleCaret(caretPoint) else {
            SpeakLog.input.debug(
                "CaretOverlayController: implausible caret at (\(caretPoint.x, privacy: .public), \(caretPoint.y, privacy: .public)) — skipping overlay."
            )
            return nil
        }
        return caretPoint
    }

    /// A caret point is plausible only when it lands inside some screen's frame.
    /// AX-rich apps that host embedded terminals (VS Code, Cursor, other Electron
    /// shells) can report a caret for a hidden or off-screen element — an origin
    /// beyond the display bounds — and the panel then clamps into a screen corner
    /// as a stray box. Quartz point → AppKit: flip y against the primary screen.
    /// [fix: stray-square — degenerate AX caret]
    private static func isPlausibleCaret(_ quartzPoint: CGPoint) -> Bool {
        guard let primary = NSScreen.screens.first else { return false }
        let appKitPoint = CGPoint(
            x: quartzPoint.x,
            y: primary.frame.height - quartzPoint.y
        )
        return NSScreen.screens.contains { $0.frame.contains(appKitPoint) }
    }

    private func ensurePanel() -> NSPanel {
        if let existing = panel { return existing }

        let mask: NSWindow.StyleMask = [.borderless, .nonactivatingPanel]
        let p = NSPanel(
            contentRect: CGRect(x: 0, y: 0, width: Self.panelWidth, height: Self.panelHeight),
            styleMask: mask,
            backing: .buffered,
            defer: true
        )
        p.isFloatingPanel   = true
        p.level             = .popUpMenu
        p.backgroundColor   = .clear
        p.isOpaque          = false
        p.hasShadow         = true
        p.hidesOnDeactivate = false
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]

        let hostingView = NSHostingView(
            rootView: CaretOverlayView(model: model)
        )
        hostingView.frame = CGRect(origin: .zero, size: CGSize(width: Self.panelWidth, height: Self.panelHeight))
        hostingView.autoresizingMask = [.width, .height]
        p.contentView = hostingView

        panel = p
        return p
    }

    /// Compute the panel origin (AppKit coords, bottom-left) for a given
    /// Quartz caret point. Y-flip: Quartz origin is top-left, AppKit is bottom-left.
    ///
    /// [unverified — live placement requires human dogfood. P2.2]
    private func placement(for caretPoint: CGPoint) -> CGPoint {
        let screenHeight = NSScreen.main?.frame.height ?? 0
        let screenWidth  = NSScreen.main?.frame.width  ?? 0

        // Y-axis flip: Quartz y=0 is top, AppKit y=0 is bottom.
        let appKitY = screenHeight - caretPoint.y

        let panelY: CGFloat
        if appKitY < screenHeight * 0.2 {
            // Caret is in the bottom 20% — place panel ABOVE the caret.
            panelY = appKitY + Self.caretGap
        } else {
            // Normal case: place panel BELOW the caret.
            panelY = appKitY - Self.panelHeight - Self.caretGap
        }

        // Left-align to the caret; clamp to keep the panel on screen.
        let rawX   = caretPoint.x
        let clampedX = min(rawX, max(0, screenWidth - Self.panelWidth))

        return CGPoint(x: clampedX, y: panelY)
    }
}
