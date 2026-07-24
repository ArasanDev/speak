// App/DesignSystem/AnimatedFlowBorderModifier.swift
//
// A continuously rotating AngularGradient border rendered along the stroke of a
// RoundedRectangle. The single source of truth for the "living border" visual
// identity — every component that needs a flow border uses `.flowBorder(...)`.
//
// DESIGN PRINCIPLE: restraint. The border communicates state through flowing
// color — recording (On-Air amber/red), agent work (violet/blue), inference
// (cyan/violet), brand shimmer (glass white). It is NOT decoration for every
// surface. Apply only where state communication is the intent.
//
// ACCESSIBILITY: when `accessibilityReduceMotion` is true, the gradient is
// rendered statically (no rotation animation). The border is still visible —
// it simply does not move.
//
// TIMING: rotation period = SpeakMotion.idleBreathCycle / speed. No magic
// numbers — every constant traces to SpeakMotion or a named design token.
//
// ZERO DUPLICATION: this is the ONLY place the rotating-gradient border is
// implemented. All call sites go through the `.flowBorder(...)` View extension.

import SwiftUI

// MARK: - AnimatedFlowBorderModifier

/// A ViewModifier that overlays a continuously rotating AngularGradient along
/// the stroke of a RoundedRectangle. When `isActive` is false, no border is
/// rendered at all — the wrapped view looks completely normal.
struct AnimatedFlowBorderModifier: ViewModifier {

    // MARK: - Parameters

    /// The gradient color stops. First and last element should match for
    /// seamless tiling (see SpeakColors flow arrays).
    let colors: [Color]

    /// Stroke width of the border. [decision: 2pt default — visible but not heavy]
    let lineWidth: CGFloat

    /// Corner radius of the rounded rectangle. [decision: 12pt default — matches
    /// the super-ellipse aesthetic used across dashboard cards]
    let cornerRadius: CGFloat

    /// Speed multiplier. 1.0 = one full rotation per `SpeakMotion.idleBreathCycle`.
    /// 2.0 = twice as fast. Must be > 0.
    let speed: Double

    /// When false, no border is rendered. The wrapped view is untouched.
    let isActive: Bool

    // MARK: - Animation state

    /// The rotation angle in degrees. Animated from 0 to 360 in a linear loop.
    @State private var rotationAngle: Double = 0

    /// Reduce-motion environment value. When true, the gradient is static.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // MARK: - Body

    func body(content: Content) -> some View {
        content.overlay {
            if isActive {
                let shape = RoundedRectangle(
                    cornerRadius: cornerRadius,
                    style: .continuous
                )

                shape
                    .stroke(
                        AngularGradient(
                            gradient: Gradient(colors: colors),
                            center: .center,
                            angle: .degrees(rotationAngle)
                        ),
                        lineWidth: lineWidth
                    )
                    .onAppear {
                        startAnimationIfNeeded()
                    }
                    .onChange(of: reduceMotion) { _, newValue in
                        handleReduceMotionChange(newValue)
                    }
            }
        }
    }

    // MARK: - Animation control

    /// Starts the rotation animation unless reduce-motion is active.
    private func startAnimationIfNeeded() {
        guard !reduceMotion else { return }

        let period = SpeakMotion.idleBreathCycle / max(speed, 0.01)

        withAnimation(
            .linear(duration: period)
            .repeatForever(autoreverses: false)
        ) {
            rotationAngle = 360
        }
    }

    /// When reduce-motion toggles on, freeze the gradient. When it toggles off,
    /// restart the animation.
    private func handleReduceMotionChange(_ isReduced: Bool) {
        if isReduced {
            // Freeze: reset to a static angle with no animation.
            withAnimation(nil) {
                rotationAngle = 0
            }
        } else {
            // Restart the rotation.
            rotationAngle = 0
            startAnimationIfNeeded()
        }
    }
}

// MARK: - View extension

public extension View {

    /// Applies a continuously rotating AngularGradient border along a
    /// RoundedRectangle stroke.
    ///
    /// - Parameters:
    ///   - colors: Gradient color stops. Use a `SpeakColors.speakFlow*` array.
    ///     First and last element should match for seamless tiling.
    ///   - lineWidth: Stroke width. Default 2pt.
    ///   - cornerRadius: Corner radius matching the wrapped view's shape.
    ///     Default 12pt (super-ellipse aesthetic).
    ///   - speed: Rotation speed multiplier. 1.0 = one rotation per
    ///     `SpeakMotion.idleBreathCycle` (4s). Default 1.0.
    ///   - isActive: When false, no border is rendered. Default true.
    ///
    /// Accessibility: respects `accessibilityReduceMotion` — renders a static
    /// gradient when the user has enabled Reduce Motion.
    func flowBorder(
        colors: [Color],
        lineWidth: CGFloat = 2,
        cornerRadius: CGFloat = 12,
        speed: Double = 1.0,
        isActive: Bool = true
    ) -> some View {
        modifier(AnimatedFlowBorderModifier(
            colors: colors,
            lineWidth: lineWidth,
            cornerRadius: cornerRadius,
            speed: speed,
            isActive: isActive
        ))
    }
}
