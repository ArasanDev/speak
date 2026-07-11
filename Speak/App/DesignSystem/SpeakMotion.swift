// App/DesignSystem/SpeakMotion.swift
//
// FE-1 (specs/frontend-identity.md §4): the motion charter, as reusable
// constants + a Reduce-Motion-aware helper. Every animation in Pip (and,
// later, FE-2/FE-3 surfaces) should be built from these, not ad-hoc durations.
//
// CHARTER (spec §4):
//   - Every animation maps to a real signal (audio level, state transition,
//     attention request). If it doesn't read from a signal, cut it.
//   - Durations: 120ms (micro), 320ms (state), springs (response 0.35 /
//     damping 0.8). Nothing slower except Pip's idle breath (~4s cycle).
//   - Reduce Motion: crossfades replace movement; Pip's breath becomes a slow
//     opacity pulse; word-materialize becomes plain fade-in.

import SwiftUI

public enum SpeakMotion {

    // MARK: - Durations (spec §4)

    /// Micro-interaction duration — hover, tap feedback. [decision: spec §4, 120ms]
    public static let microDuration: TimeInterval = 0.120

    /// State-transition duration — e.g. idle → listening. [decision: spec §4, 320ms]
    public static let stateDuration: TimeInterval = 0.320

    /// Pip's idle "breath" cycle — the one exception to "nothing slower."
    /// [decision: spec §4, ~4s cycle]
    public static let idleBreathCycle: TimeInterval = 4.0

    // MARK: - Springs (spec §4)

    /// The one spring the charter specifies: response 0.35 / damping 0.8.
    public static let stateSpring = Animation.spring(response: 0.35, dampingFraction: 0.8)

    // MARK: - Reduce Motion helpers

    /// Micro-interaction animation, or `nil` (a plain crossfade governed by the
    /// caller's `.transition(.opacity)`) when Reduce Motion is on.
    public static func micro(reduceMotion: Bool) -> Animation? {
        reduceMotion ? .easeInOut(duration: microDuration) : .easeOut(duration: microDuration)
    }

    /// State-transition animation, honoring Reduce Motion by crossfading
    /// (same duration, no movement/spring) instead of springing.
    public static func state(reduceMotion: Bool) -> Animation? {
        reduceMotion ? .easeInOut(duration: stateDuration) : stateSpring
    }

    /// Pip's idle breath: a full spring-driven ripple normally, or a slow
    /// opacity pulse (same cycle length) under Reduce Motion — spec §4:
    /// "Pip's breath becomes a slow opacity pulse."
    public static func idleBreath(reduceMotion: Bool) -> Animation {
        reduceMotion
            ? .easeInOut(duration: idleBreathCycle).repeatForever(autoreverses: true)
            : .easeInOut(duration: idleBreathCycle / 2).repeatForever(autoreverses: true)
    }
}
