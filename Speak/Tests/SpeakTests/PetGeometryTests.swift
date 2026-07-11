// SpeakTests/PetGeometryTests.swift
//
// FE-1: `PetGeometry.snappedOrigin` — pure edge-snap math for Pip's
// drag-release behavior (spec §5: "snaps to the nearest screen edge with an
// 8pt inset"). No NSPanel/NSScreen — a synthetic screen frame + panel size.

import Foundation
@testable import Speak
import Testing

@Suite("PetGeometry — edge snap")
struct PetGeometryTests {

    // A 1440×900 screen with origin at (0, 0) — matches the fallback used
    // elsewhere in the codebase (`TranscriptOverlayPanel`'s default frame).
    private let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
    private let panelSize = CGSize(width: 56, height: 36)

    @Test("released near the left edge snaps to the left, inset by 8pt")
    func snapsLeft() {
        let origin = CGPoint(x: 20, y: 400)
        let snapped = PetGeometry.snappedOrigin(releasedAt: origin, panelSize: panelSize, screenFrame: screen)
        #expect(snapped.x == screen.minX + PetGeometry.edgeInset)
    }

    @Test("released near the right edge snaps to the right, inset by 8pt")
    func snapsRight() {
        let origin = CGPoint(x: 1440 - 56 - 10, y: 400)
        let snapped = PetGeometry.snappedOrigin(releasedAt: origin, panelSize: panelSize, screenFrame: screen)
        #expect(snapped.x == screen.maxX - panelSize.width - PetGeometry.edgeInset)
    }

    @Test("released near the bottom edge snaps to the bottom, inset by 8pt")
    func snapsBottom() {
        let origin = CGPoint(x: 700, y: 5)
        let snapped = PetGeometry.snappedOrigin(releasedAt: origin, panelSize: panelSize, screenFrame: screen)
        #expect(snapped.y == screen.minY + PetGeometry.edgeInset)
    }

    @Test("released near the top edge snaps to the top, inset by 8pt")
    func snapsTop() {
        let origin = CGPoint(x: 700, y: 900 - 36 - 5)
        let snapped = PetGeometry.snappedOrigin(releasedAt: origin, panelSize: panelSize, screenFrame: screen)
        #expect(snapped.y == screen.maxY - panelSize.height - PetGeometry.edgeInset)
    }

    @Test("released in the bottom-left corner snaps into that corner")
    func snapsBottomLeftCorner() {
        let origin = CGPoint(x: 3, y: 3)
        let snapped = PetGeometry.snappedOrigin(releasedAt: origin, panelSize: panelSize, screenFrame: screen)
        // Whichever edge wins (left or bottom — both equally close here), the
        // panel must land fully inside the screen with the 8pt inset honored
        // on the winning axis.
        #expect(snapped.x >= screen.minX)
        #expect(snapped.y >= screen.minY)
        #expect(snapped.x == screen.minX + PetGeometry.edgeInset || snapped.y == screen.minY + PetGeometry.edgeInset)
    }

    @Test("released in the top-right corner snaps into that corner")
    func snapsTopRightCorner() {
        let origin = CGPoint(x: 1440 - 56 - 3, y: 900 - 36 - 3)
        let snapped = PetGeometry.snappedOrigin(releasedAt: origin, panelSize: panelSize, screenFrame: screen)
        #expect(snapped.x <= screen.maxX - panelSize.width)
        #expect(snapped.y <= screen.maxY - panelSize.height)
    }

    @Test("the perpendicular axis is clamped to stay fully on-screen")
    func perpendicularAxisClamped() {
        // Released far left, but with a y that would put the panel off the
        // TOP of the screen if left unclamped.
        let origin = CGPoint(x: 20, y: 895)
        let snapped = PetGeometry.snappedOrigin(releasedAt: origin, panelSize: panelSize, screenFrame: screen)
        #expect(snapped.y <= screen.maxY - panelSize.height)
        #expect(snapped.y >= screen.minY)
    }

    @Test("result is always fully within the screen frame for arbitrary release points",
          arguments: [
            CGPoint(x: 0, y: 0), CGPoint(x: 1440, y: 900), CGPoint(x: 700, y: 450),
            CGPoint(x: -50, y: -50), CGPoint(x: 2000, y: 2000)
          ])
    func alwaysWithinScreen(origin: CGPoint) {
        let snapped = PetGeometry.snappedOrigin(releasedAt: origin, panelSize: panelSize, screenFrame: screen)
        #expect(snapped.x >= screen.minX)
        #expect(snapped.x <= screen.maxX - panelSize.width)
        #expect(snapped.y >= screen.minY)
        #expect(snapped.y <= screen.maxY - panelSize.height)
    }
}

// MARK: - Multi-display screen resolution (review fix, 2026-07-11)

@Suite("PetGeometry — max-intersection screen resolution")
struct PetGeometryScreenResolutionTests {

    // Two side-by-side displays: primary 1440×900 at origin, secondary
    // 1920×1080 to its right — the layout where the NSScreen.main bug bit.
    private let primary = CGRect(x: 0, y: 0, width: 1440, height: 900)
    private let secondary = CGRect(x: 1440, y: 0, width: 1920, height: 1080)
    private let panelSize = CGSize(width: 56, height: 36)

    @Test("a panel fully on the secondary display resolves to the secondary display")
    func fullyOnSecondary() {
        let panelFrame = CGRect(origin: CGPoint(x: 2000, y: 400), size: panelSize)
        let idx = PetGeometry.indexOfScreenMaximallyIntersecting(
            panelFrame: panelFrame, screenFrames: [primary, secondary]
        )
        #expect(idx == 1)
    }

    @Test("a panel fully on the primary display resolves to the primary display")
    func fullyOnPrimary() {
        let panelFrame = CGRect(origin: CGPoint(x: 700, y: 400), size: panelSize)
        let idx = PetGeometry.indexOfScreenMaximallyIntersecting(
            panelFrame: panelFrame, screenFrames: [primary, secondary]
        )
        #expect(idx == 0)
    }

    @Test("a panel straddling the boundary resolves to the screen holding the larger share")
    func straddlingBoundary() {
        // 40pt of the 56pt width on the secondary screen, 16pt on the primary.
        let panelFrame = CGRect(origin: CGPoint(x: 1440 - 16, y: 400), size: panelSize)
        let idx = PetGeometry.indexOfScreenMaximallyIntersecting(
            panelFrame: panelFrame, screenFrames: [primary, secondary]
        )
        #expect(idx == 1)
    }

    @Test("a panel intersecting no screen resolves to nil (caller falls back to NSScreen.main)")
    func offAllScreens() {
        let panelFrame = CGRect(origin: CGPoint(x: -500, y: -500), size: panelSize)
        let idx = PetGeometry.indexOfScreenMaximallyIntersecting(
            panelFrame: panelFrame, screenFrames: [primary, secondary]
        )
        #expect(idx == nil)
    }

    @Test("empty screen list resolves to nil")
    func emptyScreenList() {
        let panelFrame = CGRect(origin: .zero, size: panelSize)
        #expect(PetGeometry.indexOfScreenMaximallyIntersecting(panelFrame: panelFrame, screenFrames: []) == nil)
    }
}
