// App/Overlay/EdgeFlowBorder.swift
//
// Animated traveling color-chaser border for the recording HUD panels (Style 3).
//
// CONCEPT:
//   A band of color (a short segment of the perimeter) travels continuously around
//   the border edges like neon chaser lights. Unlike AnimatedGradientBorder (Style 2),
//   which rotates a full-panel conic gradient, EdgeFlowBorder paints light ONLY along
//   the border stroke area, traveling from point to point around the perimeter.
//
// CONFIGURABLE PARAMETERS:
//   - speed: BorderFlowSpeed (.slow = 6s, .medium = 3s, .fast = 1.5s per loop)
//   - count: Int (1, 2, or 3 simultaneous blobs, evenly spaced around perimeter)
//
// STATE-AWARE COLOR PALETTES — converged on the themed `speakFlow*` spectra
// (SpeakColors.swift), so the chaser repaints with the active theme:
//   .listening  → speakFlowOnAir (recording tally).
//   .processing → speakFlowProcessing (warm "thinking" amber spectrum).
//   .done       → speakFlowSuccess (delivered celebration).
//   .error      → speakFlowError (urgent).
//
// REDUCE MOTION:
//   Suppresses rotation animation; shows static light segments at fixed positions.
//
// GENERIC SHAPE (S: InsettableShape & Shape):
//   Uses shape.trim(from:to:).stroke(...) to draw traveling segments around perimeter.
//   Call site for Classic HUD: RoundedRectangle(cornerRadius: 14, style: .continuous)
//   Call site for Aurora HUD:  Capsule(style: .continuous)
//
// [decision: traveling edge-chaser pattern uses SwiftUI shape.trim + TimelineView.
//  Colors matched to AnimatedGradientBorder state palettes for visual coherence.]

import SpeakCore
import SwiftUI

// MARK: - EdgeFlowBorderConstants

/// File-level private enum for generic type constant storage.
/// Swift forbids static stored properties in generic types.
private enum EdgeFlowBorderC {
    /// Width of the crisp flowing border line. [decision: 2.0 pt — crisp chaser line]
    static let crispWidth: CGFloat = 2.0
    /// Width of the blurred glow stroke. [decision: 8.0 pt — tight halo behind chaser]
    static let glowWidth: CGFloat = 8.0
    /// Blur radius for the halo. [decision: 4.0 pt — soft edge glow]
    static let blurRadius: CGFloat = 4.0
    /// Fraction of perimeter length per blob. [decision: 0.20 = 20% of perimeter]
    static let blobLength: Double = 0.20
    /// Timeline refresh rate. [decision: 60fps frame interval]
    static let frameInterval: Double = 1.0 / 60.0
}

// MARK: - EdgeFlowBorder

/// Traveling color-chaser border for recording HUD panels.
/// Drop into an OUTER `ZStack` outside the panel content.
struct EdgeFlowBorder<S: InsettableShape & Shape>: View {

    // MARK: - Parameters

    let shape: S
    let state: OverlayState
    let level: Double
    let speed: BorderFlowSpeed
    let count: Int
    let reduceMotion: Bool
    var customPalette: [Color]? = nil

    // MARK: - Body

    var body: some View {
        // `paused: reduceMotion` — under reduce-motion every blob renders a
        // static phase, so ticking 60fps would redraw identical frames for
        // the panel's entire life. Level changes still re-render via the
        // `.animation(value: level)` below.
        TimelineView(.animation(minimumInterval: EdgeFlowBorderC.frameInterval, paused: reduceMotion)) { timeline in
            let t = reduceMotion ? 0.0 : timeline.date.timeIntervalSinceReferenceDate
            let blobCount = min(max(count, 1), 3)
            let cycleDuration = speed.cycleDuration

            ZStack {
                ForEach(0..<blobCount, id: \.self) { i in
                    let offset = Double(i) / Double(blobCount)
                    let phase = reduceMotion
                        ? offset
                        : cyclicPhase(time: t, cycleDuration: cycleDuration, offset: offset)

                    blobView(phase: phase)
                }
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: level)
    }

    // MARK: - Blob rendering

    @ViewBuilder
    private func blobView(phase: Double) -> some View {
        let halfLength = EdgeFlowBorderC.blobLength / 2.0
        let rawStart = phase - halfLength
        let rawEnd = phase + halfLength
        let color = blobColor(phase: phase)

        ZStack {
            // Render segment(s) handling perimeter wrap-around (0.0 ... 1.0)
            if rawStart < 0 {
                segmentStroke(from: 1.0 + rawStart, to: 1.0, color: color)
                segmentStroke(from: 0.0, to: rawEnd, color: color)
            } else if rawEnd > 1.0 {
                segmentStroke(from: rawStart, to: 1.0, color: color)
                segmentStroke(from: 0.0, to: rawEnd - 1.0, color: color)
            } else {
                segmentStroke(from: rawStart, to: rawEnd, color: color)
            }
        }
    }

    @ViewBuilder
    private func segmentStroke(from start: Double, to end: Double, color: Color) -> some View {
        let clampedStart = max(0.0, min(start, 1.0))
        let clampedEnd = max(0.0, min(end, 1.0))

        if clampedStart < clampedEnd {
            // Layer 1: ambient blurred glow behind crisp line
            shape
                .trim(from: clampedStart, to: clampedEnd)
                .stroke(color.opacity(glowOpacity), style: StrokeStyle(lineWidth: EdgeFlowBorderC.glowWidth, lineCap: .round))
                .blur(radius: EdgeFlowBorderC.blurRadius)

            // Layer 2: crisp traveling light line
            shape
                .trim(from: clampedStart, to: clampedEnd)
                .stroke(color.opacity(crispOpacity), style: StrokeStyle(lineWidth: EdgeFlowBorderC.crispWidth, lineCap: .round))
        }
    }

    // MARK: - Phase & Color Math

    private func cyclicPhase(time: Double, cycleDuration: Double, offset: Double) -> Double {
        guard cycleDuration > 0 else { return 0 }
        let raw = time.truncatingRemainder(dividingBy: cycleDuration) / cycleDuration
        return (raw + offset).truncatingRemainder(dividingBy: 1.0)
    }

    /// Dynamically pick color along the state palette based on phase position around perimeter.
    private func blobColor(phase: Double) -> Color {
        let colors = palette
        guard !colors.isEmpty else { return .speakUIAccent }
        let scaled = phase * Double(colors.count)
        let index = Int(scaled) % colors.count
        let nextIndex = (index + 1) % colors.count
        let fraction = scaled - floor(scaled)

        return interpolateColor(from: colors[index], to: colors[nextIndex], fraction: fraction)
    }

    /// HSB components of a SwiftUI `Color`, converted through sRGB first.
    ///
    /// Theme-resolved tokens (`speakOnAir`, `speakAgentViolet`, …) arrive as
    /// dynamic/catalog `NSColor`s (`Color(nsColor: NSColor(name:nil){…})`) —
    /// calling `getHue` on one throws `NSInvalidArgumentException`, an
    /// uncatchable ObjC exception that took the whole app down at launch
    /// inside `NSHostingView.layout` (Speak-2026-09-14-*.ips). `usingColorSpace`
    /// resolves dynamics against the current appearance; a nil result
    /// (pattern/image colors) lets the caller fall back instead of crashing.
    /// Internal (not private) so SpeakTests can pin the conversion.
    func hsbComponents(of color: Color) -> HSBComponents? {
        guard let srgb = NSColor(color).usingColorSpace(.sRGB) else { return nil }
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        srgb.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        return HSBComponents(h: h, s: s, b: b, a: a)
    }

    /// Resolved HSB+alpha of one palette endpoint (named type — a 4-member
    /// tuple would trip SwiftLint's `large_tuple` rule).
    struct HSBComponents {
        let h: CGFloat, s: CGFloat, b: CGFloat, a: CGFloat
    }

    private func interpolateColor(from c1: Color, to c2: Color, fraction: Double) -> Color {
        // Use SwiftUI Color interpolation via HSB / opacity
        let f = CGFloat(max(0.0, min(fraction, 1.0)))
        guard
            let c1hsb = hsbComponents(of: c1),
            let c2hsb = hsbComponents(of: c2)
        else {
            // Unconvertible endpoint (pattern/image NSColor, or a dynamic
            // color the conversion can't resolve) — hold the "from" color
            // rather than crash the overlay's layout pass.
            return c1
        }

        // Handle shortest hue path around circle
        var dh = c2hsb.h - c1hsb.h
        if dh > 0.5 { dh -= 1.0 } else if dh < -0.5 { dh += 1.0 }
        let h = (c1hsb.h + dh * f).truncatingRemainder(dividingBy: 1.0)
        let finalH = h < 0 ? h + 1.0 : h

        return Color(
            hue: Double(finalH),
            saturation: Double(c1hsb.s + (c2hsb.s - c1hsb.s) * f),
            brightness: Double(c1hsb.b + (c2hsb.b - c1hsb.b) * f),
            opacity: Double(c1hsb.a + (c2hsb.a - c1hsb.a) * f)
        )
    }

    // MARK: - State Palettes & Opacities

    private var palette: [Color] {
        if let customPalette, !customPalette.isEmpty {
            return customPalette
        }
        switch state {
        case .listening:  return Color.speakFlowOnAir
        case .processing: return Color.speakFlowProcessing
        case .done:       return Color.speakFlowSuccess
        case .error:      return Color.speakFlowError
        }
    }

    /// Test seam — lets SpeakTests verify every state palette's colors
    /// survive the sRGB conversion (the 2026-09-14 dynamic-color crash).
    var paletteForTesting: [Color] { palette }

    private var glowOpacity: Double {
        switch state {
        case .listening: return 0.30 + level * 0.50
        case .processing: return 0.40
        case .done: return 0.50
        case .error: return 0.45
        }
    }

    private var crispOpacity: Double {
        switch state {
        case .listening: return 0.60 + level * 0.35
        case .processing: return 0.75
        case .done: return 0.90
        case .error: return 0.85
        }
    }
}
