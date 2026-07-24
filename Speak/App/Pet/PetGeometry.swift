// App/Pet/PetGeometry.swift
//
// Pure geometry for Voice Desktop Pet's panel: edge-snap on drag-release (spec §5 —
// "Draggable anywhere; on release, snaps to the nearest screen edge with an
// 8pt inset"). Factored out of `PetPanelController` so the snap math is
// unit-testable without a live `NSPanel`/`NSScreen`.

import CoreGraphics
import Foundation

public enum PetGeometry {

    /// Inset from the screen edge after a snap. [decision: spec §5, 8pt]
    public static let edgeInset: CGFloat = 8

    /// Compute the snapped origin for a panel of `panelSize` released at
    /// `origin` inside `screenFrame` (typically `NSScreen.visibleFrame`).
    ///
    /// Snaps to whichever of the four edges the panel's CENTER is nearest to
    /// (measured as the shortest perpendicular distance from the panel's
    /// bounding edges to the screen's bounding edges), then insets by
    /// `edgeInset` from that edge. The perpendicular (non-snapped) axis is
    /// clamped to keep the panel fully on-screen.
    ///
    /// - Parameters:
    ///   - origin: The panel's released bottom-left origin (AppKit coords).
    ///   - panelSize: The panel's size.
    ///   - screenFrame: The screen's visible frame to snap within.
    /// - Returns: The new bottom-left origin, snapped + inset + clamped.
    public static func snappedOrigin(
        releasedAt origin: CGPoint,
        panelSize: CGSize,
        screenFrame: CGRect
    ) -> CGPoint {
        // Distance from each of the panel's four edges to the corresponding
        // screen edge — the smallest wins.
        let distLeft = origin.x - screenFrame.minX
        let distRight = screenFrame.maxX - (origin.x + panelSize.width)
        let distBottom = origin.y - screenFrame.minY
        let distTop = screenFrame.maxY - (origin.y + panelSize.height)

        let distances: [(edge: Edge, distance: CGFloat)] = [
            (.left, distLeft), (.right, distRight), (.bottom, distBottom), (.top, distTop)
        ]
        let nearest = distances.min { $0.distance < $1.distance }?.edge ?? .left

        var x = origin.x
        var y = origin.y

        switch nearest {
        case .left:
            x = screenFrame.minX + edgeInset
        case .right:
            x = screenFrame.maxX - panelSize.width - edgeInset
        case .bottom:
            y = screenFrame.minY + edgeInset
        case .top:
            y = screenFrame.maxY - panelSize.height - edgeInset
        }

        // Clamp the perpendicular axis so the panel never lands off-screen.
        x = min(max(x, screenFrame.minX), screenFrame.maxX - panelSize.width)
        y = min(max(y, screenFrame.minY), screenFrame.maxY - panelSize.height)

        return CGPoint(x: x, y: y)
    }

    private enum Edge {
        case left, right, top, bottom
    }

    /// Index of the screen frame that maximally intersects `panelFrame`, or
    /// `nil` when the panel intersects no screen at all.
    ///
    /// Pure function over `[CGRect]` (same pattern as
    /// `TranscriptOverlayPanel.indexOfScreen(containing:frames:)`) so
    /// multi-display resolution is unit-testable with synthetic geometries.
    ///
    /// Used by `PetPanelController` (review fix, 2026-07-11): `NSScreen.main`
    /// always resolves to the PRIMARY display for a non-key
    /// `.nonactivatingPanel`, so snap math and per-display persistence must
    /// resolve the screen Voice Desktop Pet is actually on — `panel.screen` first, then
    /// this max-intersection fallback, then `NSScreen.main` as last resort.
    public static func indexOfScreenMaximallyIntersecting(
        panelFrame: CGRect,
        screenFrames: [CGRect]
    ) -> Int? {
        var bestIndex: Int?
        var bestArea: CGFloat = 0
        for (index, frame) in screenFrames.enumerated() {
            let intersection = frame.intersection(panelFrame)
            guard !intersection.isNull else { continue }
            let area = intersection.width * intersection.height
            if area > bestArea {
                bestArea = area
                bestIndex = index
            }
        }
        return bestIndex
    }
}
