// App/Overlay/CodingCustomizationPanel.swift
//
// A second, independent floating NSPanel — the real-time PROMPT-CUSTOMIZATION surface
// (P-Code v2), opened from the base HUD's single button (formerly: the "Code" Agent
// category button, before the destination/category picker was removed from the base
// HUD — see TranscriptOverlayView.swift's P-Code v2 doc comment). Additive: never
// replaces `TranscriptOverlayPanel`, which keeps its exact fixed 340×136 pt frame, size,
// position, and options unchanged.
//
// OWNERSHIP / LIFECYCLE:
//   Owned by `OverlayController` (alongside `panel: TranscriptOverlayPanel?`), created
//   lazily on first open — following `CaretOverlayController`'s pattern (a second panel
//   is only paid for when actually used), NOT `TranscriptOverlayPanel`'s create-once-at-
//   `startMonitoring()` pattern, since this panel opens only when the user taps "Code".
//
// SIZING (dynamically sizable — the core requirement of this panel):
//   `NSHostingController.sizingOptions` [verified: swiftc -typecheck against macOS 26 SDK,
//   `SwiftUI.NSHostingSizingOptions`] keeps the window's content size synced to the SwiftUI
//   content's ideal size as it changes, unlike `TranscriptOverlayPanel`'s hardcoded
//   340×136 pt frame. Because AppKit's automatic resize does not know our anchor point
//   (bottom-center, directly above the base HUD), we observe `NSWindow.didResizeNotification`
//   and re-anchor the origin on every resize so growth always happens upward, symmetrically
//   around the anchor's x-center, with the bottom edge pinned just above the base HUD.
//
// STACKING (z-order contract across the app's floating panels — no panel picks an
// arbitrary level; this is the single source of truth for relative ordering):
//   - `TranscriptOverlayPanel`   → `.floating`            (rawValue   3) — base always-present HUD.
//   - `CaretOverlayController`   → `.popUpMenu`            (rawValue 101) — small transient
//     caret-tracking preview; already above the base HUD.
//   - `CodingCustomizationPanel` → `.popUpMenu.rawValue + 1`             — the largest,
//     most deliberately-invoked overlay surface; must never be occluded by either of the
//     other two panels, so it sits one level above the highest existing panel level.
//
// POSITIONING (no overlap with the base HUD's in-place `profileSelectorCard`):
//   The base HUD's card (destinations / Agent categories) renders INSIDE
//   `TranscriptOverlayPanel`'s fixed 340×136 pt frame regardless of
//   `isProfilePanelOpen` / `isShowingAgentCategories` — that frame's size never changes.
//   Anchoring this panel directly ABOVE that frame (with a fixed gap) therefore never
//   competes for the same screen region with the base HUD in ANY of its sub-states.
//
// FOCUS-STEAL PREVENTION: `.nonactivatingPanel` + `isFloatingPanel` + `hidesOnDeactivate = false`
// (as `TranscriptOverlayPanel`) so ordering this panel front never activates the app or steals
// focus from whatever app the user is dictating into. UNLIKE the base HUD, this panel DOES
// allow `canBecomeKey` — it hosts an editable `TextEditor` for the custom-prompt field, and a
// panel that can never become key can never receive typed keystrokes. `.nonactivatingPanel`
// already guarantees becoming key does not activate the app or reorder other windows, so this
// stays safe. `canBecomeMain` stays false (this is an auxiliary panel, never a main window).

import AppKit
import SpeakCore
import SwiftUI

/// A floating, non-activating, dynamically-sized window hosting the prompt-customization
/// (P-Code) surface opened from the base HUD's single button.
@MainActor
final class CodingCustomizationPanel: NSPanel {

    // MARK: - Constants

    /// One rawValue above `CaretOverlayController`'s `.popUpMenu` — the highest existing
    /// overlay panel level — so this panel always wins z-order ties. See §STACKING above.
    private static let panelLevel = NSWindow.Level(rawValue: NSWindow.Level.popUpMenu.rawValue + 1)

    /// Gap between the base HUD panel's top edge and this panel's bottom edge.
    /// [decision: matches `CaretOverlayController.caretGap` (8 pt) convention for
    ///  panel-to-anchor spacing, plus a few points of extra breathing room since this
    ///  panel is visually much larger than the caret preview.]
    private static let anchorGap: CGFloat = 12

    /// Initial/minimum content size before SwiftUI has laid out real content, so the
    /// panel never collapses to a zero-size window on first construction.
    private static let minWidth: CGFloat = 360
    private static let minHeight: CGFloat = 120

    // MARK: - Internals

    /// Token for the resize observer; removed in `deinit`.
    nonisolated(unsafe) private var resizeObserver: (any NSObjectProtocol)?

    /// The base HUD panel's frame this panel is anchored above. Recorded at
    /// `show(anchoredAbove:)` and reused by `reanchor()` on every resize.
    private var anchorBaseFrame: CGRect = .zero

    // MARK: - Init

    init(overlayModel: OverlayViewModel) {
        let mask: NSWindow.StyleMask = [.nonactivatingPanel, .borderless]
        let initialFrame = CGRect(x: 0, y: 0, width: Self.minWidth, height: Self.minHeight)

        super.init(
            contentRect: initialFrame,
            styleMask: mask,
            backing: .buffered,
            defer: true
        )

        self.isFloatingPanel = true
        self.hidesOnDeactivate = false
        self.level = Self.panelLevel
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = true
        self.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .stationary,
            .ignoresCycle
        ]

        let hostingController = NSHostingController(
            rootView: CodingCustomizationView(model: overlayModel)
        )
        // [verified: swiftc -typecheck macOS 26 SDK] Keeps the window's content size
        // synced to the SwiftUI content's ideal size as it changes — the "dynamically
        // sizable, not a hardcoded frame" requirement for this panel.
        hostingController.sizingOptions = [.intrinsicContentSize, .minSize]
        self.contentViewController = hostingController

        resizeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResizeNotification,
            object: self,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.reanchor()
            }
        }
    }

    deinit {
        if let observer = resizeObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    // MARK: - Focus-steal guards

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    // MARK: - Show / Hide

    /// Show the panel anchored directly above `baseFrame` (the base HUD panel's current
    /// frame), horizontally centered on it. Safe to call repeatedly — re-anchors each time,
    /// so it tracks the base HUD if it has moved (e.g. multi-monitor reposition) since the
    /// panel was last shown.
    func show(anchoredAbove baseFrame: CGRect) {
        anchorBaseFrame = baseFrame
        reanchor()
        orderFrontRegardless()
        // `.nonactivatingPanel` means this is safe: taking key focus here does not activate
        // the app or reorder the app the user is dictating into. Without this, the user would
        // have to click the text field first before any keystroke registers.
        makeKey()
    }

    /// Hide the panel.
    func hide() {
        orderOut(nil)
    }

    // MARK: - Private

    /// Pure function: the origin that keeps a panel of `contentSize` anchored
    /// horizontally centered on `baseFrame` and `gap` points above its top edge.
    /// Factored out (mirroring `TranscriptOverlayPanel.indexOfScreen`) so the anchoring
    /// math is unit-testable without a real window/screen.
    static func anchoredOrigin(baseFrame: CGRect, contentSize: CGSize, gap: CGFloat) -> CGPoint {
        let x = baseFrame.midX - contentSize.width / 2
        let y = baseFrame.maxY + gap
        return CGPoint(x: x, y: y)
    }

    /// Recompute origin from the current frame size so the panel stays horizontally
    /// centered on `anchorBaseFrame` and its bottom edge stays fixed just above it,
    /// growing upward as content grows. `setFrameOrigin` does not itself post
    /// `didResizeNotification` (only `didMoveNotification`), so this cannot recurse.
    private func reanchor() {
        let origin = Self.anchoredOrigin(baseFrame: anchorBaseFrame, contentSize: frame.size, gap: Self.anchorGap)
        setFrameOrigin(origin)
    }
}
