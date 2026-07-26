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
// STATE-AWARE COLOR PALETTES:
//   .listening  → violet–indigo–cyan–teal (aurora palette).
//   .processing → amber–orange–gold (warm "thinking" palette).
//   .done       → green–mint (celebration).
//   .error      → red–crimson (urgent).
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
        TimelineView(.animation(minimumInterval: EdgeFlowBorderC.frameInterval, paused: reduceMotion && level < 0.001)) { timeline in
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
        guard !colors.isEmpty else { return .accentColor }
        let scaled = phase * Double(colors.count)
        let index = Int(scaled) % colors.count
        let nextIndex = (index + 1) % colors.count
        let fraction = scaled - floor(scaled)

        return interpolateColor(from: colors[index], to: colors[nextIndex], fraction: fraction)
    }

    private func interpolateColor(from c1: Color, to c2: Color, fraction: Double) -> Color {
        // Use SwiftUI Color interpolation via HSB / opacity
        let f = CGFloat(max(0.0, min(fraction, 1.0)))
        var h1: CGFloat = 0, s1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
        var h2: CGFloat = 0, s2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0

        NSColor(c1).getHue(&h1, saturation: &s1, brightness: &b1, alpha: &a1)
        NSColor(c2).getHue(&h2, saturation: &s2, brightness: &b2, alpha: &a2)

        // Handle shortest hue path around circle
        var dh = h2 - h1
        if dh > 0.5 { dh -= 1.0 } else if dh < -0.5 { dh += 1.0 }
        let h = (h1 + dh * f).truncatingRemainder(dividingBy: 1.0)
        let finalH = h < 0 ? h + 1.0 : h

        return Color(
            hue: Double(finalH),
            saturation: Double(s1 + (s2 - s1) * f),
            brightness: Double(b1 + (b2 - b1) * f),
            opacity: Double(a1 + (a2 - a1) * f)
        )
    }

    // MARK: - State Palettes & Opacities

    private var palette: [Color] {
        if let customPalette, !customPalette.isEmpty {
            return customPalette
        }
        switch state {
        case .listening:
            return [
                Color(hue: 0.760, saturation: 0.85, brightness: 1.00),  // violet
                Color(hue: 0.650, saturation: 0.90, brightness: 1.00),  // indigo
                Color(hue: 0.540, saturation: 0.85, brightness: 0.95),  // cyan
                Color(hue: 0.480, saturation: 0.78, brightness: 0.90),  // teal
            ]
        case .processing:
            return [
                Color(hue: 0.085, saturation: 0.90, brightness: 1.00),  // amber
                Color(hue: 0.110, saturation: 0.85, brightness: 1.00),  // orange-gold
                Color(hue: 0.065, saturation: 0.95, brightness: 0.95),  // deep amber
            ]
        case .done:
            return [
                Color(hue: 0.360, saturation: 0.80, brightness: 0.95),  // green
                Color(hue: 0.410, saturation: 0.70, brightness: 0.90),  // mint
            ]
        case .error:
            return [
                Color(hue: 0.000, saturation: 0.92, brightness: 1.00),  // red
                Color(hue: 0.975, saturation: 0.88, brightness: 0.95),  // crimson
            ]
        }
    }

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
