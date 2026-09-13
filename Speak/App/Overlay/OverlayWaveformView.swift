// App/Overlay/OverlayWaveformView.swift
//
// Live reactive waveform visualizer and frosted glass backdrop for the overlay HUD.
// Extracted from TranscriptOverlayView.swift to respect strict line limits (<800 lines).

import AppKit
import SpeakCore
import SwiftUI

// MARK: - VisualEffectView

/// Thin AppKit-backed SwiftUI wrapper that applies NSVisualEffectView material.
/// Internal (not `private`) so `AuroraOverlayView` (H-UI) and other overlay panels can reuse it.
struct VisualEffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = material
        v.blendingMode = blendingMode
        v.state = .active
        return v
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}

// MARK: - VRule

/// A vertical rule shape — the capsule-bar HUD's lane divider. Stroked with
/// a dash pattern by callers ("a dotted line, a little thicker" per the
/// owner's sketch). Shared by `TranscriptOverlayView` and `AuroraOverlayView`.
struct VRule: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.midX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        return p
    }
}

// MARK: - WaveformView

/// A 15-bar waveform driven by `level` (0…1) with per-bar phase offset.
///
/// Bar heights are computed by `levelBarHeightsPhased(level:phase:barCount:…)` in
/// `LevelMath.swift` — a pure function that makes the waveform look organic while
/// remaining fully unit-testable. When `reduceMotion` is true (Accessibility setting),
/// the phase animation and idle-breathing are suppressed; bars still reflect the live
/// level value (information, not decoration).
///
/// Bar geometry decisions — all [decision] in benchmark.md §7:
///   - 15 bars: VoiceInk blueprint (competitor research W0, §0 finding #1).
///   - 2 pt width: thin "audio analyser" look, distinct from the 5-bar v0 design.
///   - 2 pt gap: breathing room; 15 × (2 + 2) = 60 pt total, fits the panel.
///   - 3 pt min height: always visible at silence — never disappears.
///   - 20 pt max height: fits the 80 pt panel with 12 pt vertical padding each side.
struct WaveformView: View {

    let level: Double
    let isActive: Bool          // true = listening; false = silent/idle

    // [decision: 15 bars — VoiceInk blueprint, benchmark.md §7]
    private static let barCount: Int = 15
    // [decision: 2 pt bar width — thin analyser look, benchmark.md §7]
    private static let barWidth: CGFloat = 2.0
    // [decision: 2 pt gap — breathing room, 15 × 4 pt = 60 pt total, benchmark.md §7]
    private static let barGap: CGFloat  = 2.0
    // [decision: 3 pt min — always visible at silence, benchmark.md §7]
    private static let minHeight: Double = 3.0
    // [decision: 20 pt max — fits 80 pt panel, benchmark.md §7]
    private static let maxHeight: Double = 20.0

    /// Computed width of the waveform block (used by callers for `.frame(width:)`).
    static var totalWidth: CGFloat {
        CGFloat(barCount) * barWidth + CGFloat(barCount - 1) * barGap  // = 30 + 28 = 58 pt
    }

    /// Animated phase for the per-bar offset (0…1). Drives the organic waveform
    /// movement when listening. Suppressed when reduce-motion is on.
    @State private var animPhase: Double = 0.0
    /// Idle-breathing amplitude (0…1). Only used when `isActive == false` and
    /// reduce-motion is off. Suppressed when reduce-motion is on.
    @State private var breathPhase: Double = 0.0

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: Self.barGap) {
            ForEach(Array(barHeights.enumerated()), id: \.offset) { _, height in
                RoundedRectangle(cornerRadius: Self.barWidth / 2, style: .continuous)
                    .fill(barColor)
                    .frame(width: Self.barWidth, height: CGFloat(height))
            }
        }
        // [decision: 0.08 s animation — snappier than v0's 0.12 s for 15-bar feel]
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.08), value: level)
        .onAppear {
            guard !reduceMotion else { return }
            startPhaseAnimation()
            if !isActive { startBreathing() }
        }
        .onChange(of: isActive) { _, newValue in
            guard !reduceMotion else { return }
            if !newValue { startBreathing() } else { breathPhase = 0.0 }
        }
    }

    private var barColor: Color {
        // Active = `speakVoiceBlue`: the fixed voice-capture blue — owner
        // direction: blue, not orange/red, and it must not follow the system
        // accent. The `speakOnAir` tally lamp lives in the header row
        // instead. Idle = resting bone bars, dark enough to read on the
        // light glass (mica washed out).
        isActive ? Color.speakVoiceBlue : Color.speakBone.opacity(0.3)
    }

    private var barHeights: [Double] {
        if isActive {
            return levelBarHeightsPhased(
                level: level,
                phase: animPhase,
                barCount: Self.barCount,
                minHeight: Self.minHeight,
                maxHeight: Self.maxHeight
            )
        } else {
            // Idle breathing when not active.
            let breathLevel = 0.12 + 0.12 * breathPhase   // [decision: 0.12…0.24 idle range]
            return levelBarHeightsPhased(
                level: breathLevel,
                phase: animPhase,
                barCount: Self.barCount,
                minHeight: Self.minHeight,
                maxHeight: Self.maxHeight
            )
        }
    }

    /// Advance the phase over time so adjacent bars appear to ripple.
    private func startPhaseAnimation() {
        withAnimation(
            // [decision: 1.8 s cycle — organic wave rhythm, VoiceInk-inspired feel]
            Animation.linear(duration: 1.8).repeatForever(autoreverses: false)
        ) {
            animPhase = 1.0
        }
    }

    /// Gentle idle breathing when not actively listening.
    private func startBreathing() {
        withAnimation(
            // [decision: 1.4 s breath cycle — slightly slower than active phase]
            Animation.easeInOut(duration: 1.4).repeatForever(autoreverses: true)
        ) {
            breathPhase = 1.0
        }
    }
}
