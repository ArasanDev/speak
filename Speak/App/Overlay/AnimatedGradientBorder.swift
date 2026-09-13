// App/Overlay/AnimatedGradientBorder.swift
//
// Animated flowing conic-gradient border for the recording HUD panels.
//
// DESIGN — TWO LAYERS:
//   1. A wide, blurred "glow" stroke — creates an ambient halo effect.
//   2. A crisp, thin stroke — the visible flowing border line.
//   Both share a rotating AngularGradient whose startAngle is advanced with
//   withAnimation(.linear.repeatForever), making colors "flow" continuously
//   around the panel edge like sequential neon lighting.
//
// STATE-AWARE COLOR PALETTES — converged on the themed `speakFlow*` spectra
// (SpeakColors.swift), so the border repaints with the active theme:
//   .listening  → speakFlowOnAir (recording tally; humanAmber → onAir).
//                 Glow intensity and blur radius scale with the live microphone level
//                 so the border "breathes" with the user's voice.
//   .processing → speakFlowProcessing (warm "thinking" amber spectrum).
//   .done       → speakFlowSuccess (delivered celebration, then auto-hidden
//                 by DictationController).
//   .error      → speakFlowError (urgent, persistent until dismissed).
//
// REDUCE MOTION:
//   Rotation is fully suppressed; the border remains as a static tinted outline
//   so the state color is still communicated without decorative animation.
//
// GENERIC SHAPE (S: InsettableShape):
//   Uses `strokeBorder` (not `stroke`) so the line stays within view bounds,
//   exactly aligning with the host panel's clip shape.
//   Call site for Classic HUD: RoundedRectangle(cornerRadius: 14, style: .continuous)
//   Call site for Aurora HUD:  Capsule(style: .continuous)
//
// [decision: two-layer glow+crisp = standard macOS "neon outline" pattern.
//  Colors matched to AuroraOverlayView aurora palette for visual coherence.
//  All numeric constants are tagged [decision] below; benchmark.md §7.]

import SpeakCore
import SwiftUI

// MARK: - AnimatedGradientBorderConstants

// Swift forbids static stored properties in generic types — even inside nested
// private enums. File-level private enum is the minimal workaround.
// [verified: swiftc -typecheck macOS 26 SDK]
private enum AnimatedGradientBorderC {
    /// Width of the crisp border line. [decision: 1.5 pt — present but not heavy]
    static let crispWidth: CGFloat = 1.5
    /// Width of the blurred glow stroke before blurring. [decision: 10 pt]
    static let glowWidth: CGFloat = 10
    /// Base glow blur radius. [decision: 5 pt — soft halo without obscuring adjacent UI]
    static let baseBlur: CGFloat = 5
    /// Extra blur headroom at full microphone level. [decision: +10 pt at level = 1.0]
    static let levelBlurBoost: CGFloat = 10
    /// One full gradient rotation in seconds.
    /// [decision: 3 s — slow ambient cadence; feels organic, not frantic]
    static let rotationDuration: Double = 3.0
}

// MARK: - AnimatedGradientBorder

/// Animated flowing conic-gradient border for the recording HUD panels.
/// Drop into an OUTER `ZStack` (outside the content's `clipShape`) so the
/// glow blur bleeds naturally beyond the card edge.
struct AnimatedGradientBorder<S: InsettableShape>: View {

    // MARK: - Parameters

    /// The panel's clip shape — RoundedRectangle for Classic, Capsule for Aurora.
    let shape: S
    let state: OverlayState
    /// Live RMS level (0…1). Only used in `.listening` to modulate glow intensity.
    let level: Double
    let reduceMotion: Bool
    var customPalette: [Color]? = nil

    // MARK: - Animation state

    @State private var angle: Double = 0

    // MARK: - Body

    var body: some View {
        ZStack {
            // Layer 1: wide blurred ambient glow
            shape
                .strokeBorder(
                    AngularGradient(
                        colors: glowColors,
                        center: .center,
                        startAngle: .degrees(angle),
                        endAngle: .degrees(angle + 360)
                    ),
                    lineWidth: AnimatedGradientBorderC.glowWidth
                )
                .blur(radius: currentBlur)
                .opacity(glowOpacity)

            // Layer 2: crisp flowing border line (45° phase offset from glow layer)
            shape
                .strokeBorder(
                    AngularGradient(
                        colors: borderColors,
                        center: .center,
                        startAngle: .degrees(angle + 45),
                        endAngle: .degrees(angle + 405)
                    ),
                    lineWidth: AnimatedGradientBorderC.crispWidth
                )
                .opacity(borderOpacity)
        }
        // Smooth level-reactive transitions without restarting rotation.
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: level)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(
                .linear(duration: AnimatedGradientBorderC.rotationDuration).repeatForever(autoreverses: false)
            ) {
                angle = 360
            }
        }
    }

    // MARK: - Color palette

    /// Colors for the crisp border stroke — wraps first → last so the
    /// gradient tiles seamlessly across the 360° rotation.
    private var borderColors: [Color] { palette + [palette[0]] }

    /// Colors for the glow layer — same hues, slightly reduced opacity
    /// so the glow does not drown out the crisp line above it.
    private var glowColors: [Color] { (palette + [palette[0]]).map { $0.opacity(0.75) } }

    /// State-specific base palette — the themed `speakFlow*` spectra, so the
    /// border animations repaint with the active theme (seamless wrap handled
    /// by `borderColors`/`glowColors`).
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

    // MARK: - Level-reactive computed values

    /// Glow layer opacity. Scales from subtle-idle to vivid-active in `.listening`.
    private var glowOpacity: Double {
        switch state {
        case .listening: return 0.20 + level * 0.55   // 0.20 idle → 0.75 at level = 1
        case .processing: return 0.30
        case .done:       return 0.45
        case .error:      return 0.40
        }
    }

    /// Crisp border opacity. Also level-boosted during `.listening`.
    private var borderOpacity: Double {
        switch state {
        case .listening: return 0.45 + level * 0.35   // 0.45 idle → 0.80 at level = 1
        case .processing: return 0.60
        case .done:       return 0.75
        case .error:      return 0.70
        }
    }

    /// Blur radius for the glow layer. Expands with voice level in `.listening`
    /// so the border "breathes" visibly with the microphone signal.
    private var currentBlur: CGFloat {
        switch state {
        case .listening:
            return AnimatedGradientBorderC.baseBlur + CGFloat(level) * AnimatedGradientBorderC.levelBlurBoost
        default:
            return AnimatedGradientBorderC.baseBlur
        }
    }
}
