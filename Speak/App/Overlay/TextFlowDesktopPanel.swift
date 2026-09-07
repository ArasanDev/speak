// App/Overlay/TextFlowDesktopPanel.swift
//
// The second panel in the FIFO-out text flow: renders the text that has flowed
// OUT of the overlay's 3-line window, streaming directly on the DESKTOP — bare
// words, no card, no background, black or white matching the system appearance,
// fading as they rise (locked 2026-08-04, upward flow + fade-and-disappear).
//
// Unlike `TranscriptOverlayPanel` (fixed 520×88 HUD) this panel is TRANSPARENT
// chrome: it hosts a SwiftUI view that draws only the flowing text, letting the
// desktop show through. It must NEVER steal focus, never activate, never be
// interactive — it is pure display.
//
// FOCUS-STEAL PREVENTION: identical layered guarantees as `TranscriptOverlayPanel`
// (nonactivatingPanel, isFloatingPanel, hidesOnDeactivate=false, canBecomeKey=false,
// orderFrontRegardless) — see TranscriptOverlayPanel.swift §FOCUS-STEAL PREVENTION.
//
// STACKING (z-order contract — see CodingCustomizationPanel.swift §STACKING):
//   This panel sits at `.floating` (same level as the base HUD) and is shown only
//   while dictation is active. It renders text ABOVE the HUD's position, so the
//   flow reads as words rising from the panel.

import AppKit
import SpeakCore
import SwiftUI

// MARK: - Desktop flow content

/// The bare, background-less flowing text. Black or white by appearance, fading
/// as it rises. No card, no chrome — the desktop is the canvas.
private struct DesktopFlowContentView: View {
    let chunks: [FlowedChunk]
    /// True while the flow is active (dictating). Drives the fade animation.
    let isActive: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Oldest at top, newest near the panel (bottom) — fade as they rise.
            ForEach(Array(chunks.enumerated()), id: \.element.id) { index, chunk in
                Text(chunk.text)
                    .font(.system(size: 15, weight: .medium, design: .monospaced))
                    .foregroundStyle(.primary)   // black in light, white in dark — appearance-driven
                    .lineLimit(1)
                    .lineSpacing(0)
                    .opacity(opacityFor(index: index))
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .id(chunk.id)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.6), value: chunks)  // [decision: 0.6s rise/fade]
    }

    /// Older chunks are fainter — the flow fades as it rises.
    /// [decision: newest chunk at full opacity, each older chunk 40% fainter]
    private func opacityFor(index: Int) -> Double {
        let distanceFromBottom = chunks.count - 1 - index
        return max(0.15, 1.0 - Double(distanceFromBottom) * 0.4)
    }
}

// MARK: - Panel subclass

/// A transparent, non-activating floating window that streams departed text
/// on the desktop. Pure display — never key, never interactive.
@MainActor
final class TextFlowDesktopPanel: NSPanel {

    /// Width of the desktop stream lane. [decision: generous — the flowing text
    ///  reads across the desktop without wrapping; capped so it stays a lane, not
    ///  a wall of text.]
    private static let laneWidth: CGFloat = 640

    /// Maximum lines the desktop stream shows before the oldest fully fades.
    /// [decision: matches the bounded-stack taste — the desktop never fills up.]
    private static let maxVisibleChunks = 5

    // MARK: - State

    /// The chunks currently flowing on the desktop.
    private var chunks: [FlowedChunk] = []

    // MARK: - Init

    init() {
        let mask: NSWindow.StyleMask = [.nonactivatingPanel, .borderless]
        // Positioned above the base HUD at dictation start; re-anchored per dictation.
        let initialFrame = CGRect(x: 0, y: 0, width: Self.laneWidth, height: 240)  // [decision: ~10×24pt lines]

        super.init(
            contentRect: initialFrame,
            styleMask: mask,
            backing: .buffered,
            defer: true
        )

        // Focus-steal prevention + floating (mirrors TranscriptOverlayPanel).
        self.isFloatingPanel = true
        self.hidesOnDeactivate = false
        self.level = .floating
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = false          // bare text — no shadow, no card

        // Collection: visible everywhere, stationary, never in window cycling.
        self.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .stationary,
            .ignoresCycle
        ]

        // Host the bare flowing text. FirstMouseHostingView is NOT needed — this
        // panel is never interactive; plain NSHostingView suffices.
        let hostingView = NSHostingView(
            rootView: DesktopFlowContentView(chunks: [], isActive: false)
        )
        hostingView.frame = CGRect(origin: .zero, size: initialFrame.size)
        hostingView.autoresizingMask = [.width, .height]
        self.contentView = hostingView
    }

    // MARK: - Focus-steal guards

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    // MARK: - Flow control

    /// Show the panel above the base HUD's frame, horizontally centered on it.
    func show(anchoredAbove baseFrame: CGRect) {
        reposition(above: baseFrame)
        orderFrontRegardless()
    }

    /// Feed a chunk that flowed out of the window — append it to the stream.
    /// Older chunks beyond `maxVisibleChunks` fade away (the desktop never fills).
    func appendChunk(_ chunk: FlowedChunk) {
        chunks.append(chunk)
        if chunks.count > Self.maxVisibleChunks {
            chunks.removeFirst(chunks.count - Self.maxVisibleChunks)
        }
        updateRoot()
    }

    /// Hide the panel and reset the stream.
    func hideAndReset() {
        chunks = []
        updateRoot()
        orderOut(nil)
    }

    // MARK: - Private

    /// Position the lane directly above the base HUD, horizontally centered.
    private func reposition(above baseFrame: CGRect) {
        let x = baseFrame.midX - Self.laneWidth / 2
        let y = baseFrame.maxY + 8   // 8pt gap — reads as words rising from the panel
        setFrame(CGRect(x: x, y: y, width: Self.laneWidth, height: CGFloat(Self.maxVisibleChunks) * 24), display: true)  // 24pt/line
    }

    /// Push the current chunks into the hosted SwiftUI view.
    private func updateRoot() {
        let view = DesktopFlowContentView(chunks: chunks, isActive: !chunks.isEmpty)
        (contentView as? NSHostingView<DesktopFlowContentView>)?.rootView = view
    }
}
