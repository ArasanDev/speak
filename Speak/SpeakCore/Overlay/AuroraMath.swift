// SpeakCore/Overlay/AuroraMath.swift
//
// Pure math for the Aurora HUD style (H-UI): the ambient orb's radius/phase
// and the materializing-word ticker window. No AppKit/SwiftUI Canvas
// dependency — fully unit-testable without a display, matching the pattern
// already established by `LevelMath.swift` for the classic waveform HUD.
//
// Design intent: `AuroraOverlayView` (App target) drives a `Canvas` purely
// from these functions so the *visual* behavior (orb breathing/ripple/hue,
// word-window contents) can be asserted in `SpeakTests` without touching
// pixels — matching the "no pixel tests" constraint on this task.

import Foundation

// MARK: - Cyclic phase

/// Map a wall-clock time to a repeating `[0, 1)` phase within a cycle.
///
/// Used for all of the orb's time-driven motion (breathing, ripple expansion,
/// processing hue drift) — one function, different `cycleDuration` per caller
/// so the cadence of each effect is documented at its call site, not duplicated
/// here as three near-identical helpers.
///
/// - Parameters:
///   - time: A monotonically increasing time value (seconds).
///   - cycleDuration: Length of one full cycle (seconds). Must be > 0.
/// - Returns: `0` when `cycleDuration <= 0` (defensive — avoids division by zero
///   from a caller-supplied constant); otherwise the phase within `[0, 1)`.
public func cyclicPhase(time: TimeInterval, cycleDuration: TimeInterval) -> Double {
    guard cycleDuration > 0 else { return 0 }
    let t = time.truncatingRemainder(dividingBy: cycleDuration)
    return t / cycleDuration
}

// MARK: - Orb radius

/// The tunable geometry constants for `orbRadius(...)`, grouped into one type
/// so the function itself stays under the project's parameter-count limit.
/// All fields are [decision H-UI] — new decorative element, no measured source.
public struct OrbGeometry: Sendable, Equatable {
    /// Resting radius in points.
    public let baseRadius: Double
    /// Max breathing excursion in points.
    public let breatheAmplitude: Double
    /// Max radius added at `level == 1.0`.
    public let levelBoost: Double

    public init(baseRadius: Double, breatheAmplitude: Double, levelBoost: Double) {
        self.baseRadius = baseRadius
        self.breatheAmplitude = breatheAmplitude
        self.levelBoost = levelBoost
    }
}

/// Compute the Aurora orb's radius for one animation frame.
///
/// Three additive components:
///   - `geometry.baseRadius`: the resting size.
///   - breathing: a slow `sin` oscillation (ambient "alive" feel), suppressed
///     when `reduceMotion` is true — Reduce Motion honors "no decorative motion",
///     but the orb must still reflect live audio level (information, not decor).
///   - level boost: proportional to the smoothed microphone level (0…1),
///     always active (even under Reduce Motion) because it conveys information.
///
/// - Parameters:
///   - geometry: Resting radius + breathing amplitude + level boost (all in points).
///   - level: Smoothed linear level (0…1). Clamped defensively.
///   - breathePhase: Phase in `[0, 1)` from `cyclicPhase(time:cycleDuration:)`.
///   - reduceMotion: Suppresses the breathing term when true.
/// - Returns: The frame's orb radius in points (always ≥ 0 for a sane `baseRadius`).
public func orbRadius(
    geometry: OrbGeometry,
    level: Double,
    breathePhase: Double,
    reduceMotion: Bool
) -> Double {
    let clampedLevel = min(max(level, 0.0), 1.0)
    let breathe = reduceMotion ? 0.0 : sin(breathePhase * 2.0 * .pi) * geometry.breatheAmplitude
    return geometry.baseRadius + breathe + clampedLevel * geometry.levelBoost
}

// MARK: - Word ticker window

/// One word in the materializing-word ticker, with a stable identity.
///
/// `id` is the word's absolute index within the *entire* transcript so far —
/// not its index within the visible window. This is load-bearing: as new
/// words push old ones out of the window, SwiftUI's `ForEach(id:)` diffing
/// sees only "one new id appended, one old id removed" (a clean insert/remove
/// transition) rather than every visible word's id shifting by one (which
/// would make every word "re-appear" and animate on each new word).
public struct WordToken: Equatable, Sendable {
    public let id: Int
    public let word: String

    public init(id: Int, word: String) {
        self.id = id
        self.word = word
    }
}

/// Split `fullText` into whitespace-separated words and return the trailing
/// window of at most `maxWords`, each tagged with its absolute position in
/// the full transcript (see `WordToken` doc for why that matters).
///
/// - Parameters:
///   - fullText: The full partial/final transcript accumulated so far.
///   - maxWords: Maximum number of words to show. Must be > 0; returns `[]` otherwise.
/// - Returns: The trailing `maxWords` (or fewer) words, oldest first.
public func wordWindow(fullText: String, maxWords: Int) -> [WordToken] {
    guard maxWords > 0 else { return [] }
    let words = fullText.split(whereSeparator: { $0.isWhitespace }).map(String.init)
    guard !words.isEmpty else { return [] }
    let startIndex = max(0, words.count - maxWords)
    return words[startIndex...].enumerated().map { offset, word in
        WordToken(id: startIndex + offset, word: word)
    }
}
