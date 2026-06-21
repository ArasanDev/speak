// SpeakCore/Overlay/LevelMath.swift
//
// Pure math for converting microphone level values to waveform bar heights.
// No AppKit/SwiftUI dependency — fully unit-testable without a display or
// audio hardware.
//
// These functions are the computation layer beneath the overlay level meter.
// They are in SpeakCore (not the App target) so SpeakTests can import and
// verify them directly without depending on the App executable target.
//
// Perceptual pipeline (introduced W2.3):
//   raw RMS (0…1) → levelPerceptual(rms:) → levelSmoothedAsymmetric → bar heights
//
// Raw RMS for typical speech clusters at 0.01–0.08 linear, so without perceptual
// mapping the bars would move less than 8% of their range — imperceptible.
// dB normalization maps the usable dynamic range of speech to the full bar range:
//   − noiseFloor dB (-55 dB) anchors the calm-silence state
//   − clipping floor dB (-3 dB) defines "loud speech / full bars"
//   − values below noiseFloor → 0 (calm, minimal bar movement)
//   − values above clipFloor → 1 (full bars, never clips)
// [decision W2.3: dB normalization chosen over plain gain because it amplifies
//  the speech dynamic range without also amplifying room noise. Speech sits in
//  -55 … -3 dBFS on a typical Mac mic; mapping that band to 0…1 makes bars
//  "fill healthily" for normal voice and "drop clearly" at silence/pauses.
//  benchmark.md §7]

import Foundation

// MARK: - dB → linear

/// Convert a dB power level to a linear amplitude (0…1).
///
/// `pow(10, dB/20)` is the standard power→amplitude conversion for audio.
/// [decision: Hex uses this formula for its waveform display bars. benchmark.md §7.]
///
/// - Parameter dB: Value in decibels. `-160` (typical silence floor) → ≈ 0.0.
///   `0 dB` → `1.0` (full scale). Values above 0 dB are clamped to 1.0.
/// - Returns: Linear amplitude clamped to `[0, 1]`.
public func levelLinear(fromDB dB: Double) -> Double {
    let linear = pow(10.0, dB / 20.0)
    return min(max(linear, 0.0), 1.0)
}

// MARK: - Perceptual RMS mapping (W2.3)

/// Convert a raw linear RMS amplitude to a perceptually-scaled display value.
///
/// Raw RMS from AVAudioEngine for typical speech is 0.01–0.08 (linear),
/// which maps to only 1–8% of bar height — visually imperceptible. This
/// function applies dB normalization: it converts the RMS to dBFS, then
/// remaps the speech-relevant dynamic range [noiseFloor…clipFloor] to [0…1].
///
/// Constants (all [decision W2.3], traced to benchmark.md §7):
///   - `noiseFloor = -55 dBFS`:  Typical Mac mic noise floor during quiet pauses.
///     Values at or below this → 0 (calm idle state). Measured from real mic RMS
///     on Apple Silicon MacBook during near-silence: ≈ -60 to -50 dBFS.
///   - `clipFloor  = -3 dBFS`:   "Loud but not clipping" speech level → 1 (full bars).
///     Sets the top of the display range just below 0 dBFS to avoid saturation.
///
/// - Parameter rms: Raw linear RMS amplitude in [0, 1] from AudioCapture.rmsLevel.
///   0 → silence (0.0 returned). Values outside [0,1] are clamped before mapping.
/// - Returns: Perceptually scaled value in [0, 1]. 0 at silence; 1 at loud speech.
public func levelPerceptual(rms: Double) -> Double {
    // [decision W2.3] dB floor for silence anchor: -55 dBFS. benchmark.md §7.
    let noiseFloorDB: Double = -55.0
    // [decision W2.3] dB ceiling for full-bar speech: -3 dBFS. benchmark.md §7.
    let clipFloorDB:  Double = -3.0

    let clamped = min(max(rms, 0.0), 1.0)
    guard clamped > 0.0 else { return 0.0 }

    // Convert to dBFS (power-to-amplitude: dB = 20 * log10(amplitude))
    let dB = 20.0 * log10(clamped)

    // Map [noiseFloor, clipFloor] → [0, 1] linearly.
    let normalized = (dB - noiseFloorDB) / (clipFloorDB - noiseFloorDB)
    return min(max(normalized, 0.0), 1.0)
}

// MARK: - Smoothing

/// Apply one-pole low-pass smoothing to a level measurement.
///
/// Formula: `prev * 0.7 + target * 0.3`
///
/// [decision: 0.7 decay / 0.3 attack constants are from Handy's `AudioLevelMeter`
///  (MIT-licensed reference implementation). At 60 Hz render cadence this gives
///  a ~3-frame attack/release — smooth enough to read, fast enough to feel live.
///  benchmark.md §7 cites Handy as source.]
///
/// - Parameters:
///   - previous: The smoothed value from the prior frame.
///   - target:   The raw measurement this frame (0…1).
/// - Returns: The smoothed value (0…1).
public func levelSmoothed(previous: Double, target: Double) -> Double {
    // [decision] Handy SMOOTHING_DECAY = 0.7, SMOOTHING_ATTACK = 0.3 (= 1 - decay)
    let decay: Double  = 0.7
    let attack: Double = 0.3
    return previous * decay + target * attack
}

/// Apply asymmetric one-pole smoothing: fast attack, slower release.
///
/// A real VU meter responds faster on transients (attack) than on decay (release),
/// which makes the waveform feel responsive to voice without jittering on
/// high-frequency noise. Attack and release operate on different timescales:
///   - Attack (rising signal): small attack coefficient → fast rise
///   - Release (falling signal): large decay coefficient → slow fall
///
/// [decision W2.3: attackCoeff=0.5, decayCoeff=0.85 — attack ~2 frames at 4 Hz
///  tap cadence; release ~7 frames. Gives snappy voice onset + natural tail.
///  Referenced from Faust GRAME "rms smoothing" reference. benchmark.md §7]
///
/// - Parameters:
///   - previous:     The smoothed value from the prior frame (0…1).
///   - target:       The perceptual level this frame (0…1).
///   - attackCoeff:  Decay weight when signal is rising (higher = slower attack).
///   - decayCoeff:   Decay weight when signal is falling (higher = slower release).
/// - Returns: The asymmetrically smoothed value (0…1).
public func levelSmoothedAsymmetric(
    previous: Double,
    target: Double,
    attackCoeff: Double = 0.5,   // [decision W2.3: 0.5 → fast attack. benchmark.md §7]
    decayCoeff: Double  = 0.85   // [decision W2.3: 0.85 → ~7-frame natural release. benchmark.md §7]
) -> Double {
    let coeff = target > previous ? attackCoeff : decayCoeff
    return previous * coeff + target * (1.0 - coeff)
}

// MARK: - Level → bar heights

/// Map a level (0…1) to bar heights for an N-bar waveform display.
///
/// The center bar is tallest at maximum level. Adjacent bars fall off with a
/// cosine envelope so the waveform shape looks natural and symmetrical.
/// Each bar is clamped to `[minHeight, maxHeight]`.
///
/// Default parameters are tuned for the HUD panel:
/// - `barCount = 5`      [decision: Handy waveform reference. benchmark.md §7]
/// - `minHeight = 3.0`   [decision: always visible even at silence]
/// - `maxHeight = 20.0`  [decision: fits the 80 pt panel height with padding]
///
/// - Parameters:
///   - level:     Smoothed linear amplitude (0…1). 0 → all bars at `minHeight`.
///   - barCount:  Number of bars. Must be > 0; returns empty array otherwise.
///   - minHeight: Minimum bar height in points.
///   - maxHeight: Maximum bar height in points.
/// - Returns: Array of `barCount` heights, each in `[minHeight, maxHeight]`.
public func levelBarHeights(
    level: Double,
    barCount: Int = 5,
    minHeight: Double = 3.0,
    maxHeight: Double = 20.0
) -> [Double] {
    guard barCount > 0 else { return [] }
    return (0 ..< barCount).map { i in
        // Map bar index to a position on [-1, 1] so the center bar is at 0.
        let center = Double(barCount - 1) / 2.0
        let t = (Double(i) - center) / max(center, 1.0)   // -1…1
        // Cosine envelope: center bar (t=0) → cos(0)=1.0 (fully driven by level);
        // edge bars (|t|=1) → cos(π/2)=0.0 (at minHeight regardless of level).
        let envelope = cos(t * .pi / 2.0)
        let height = minHeight + (maxHeight - minHeight) * level * envelope
        return min(max(height, minHeight), maxHeight)
    }
}

// MARK: - Level → bar heights with per-bar phase offset (W2.2)

/// Map a level (0…1) to bar heights with a per-bar sinusoidal phase offset.
///
/// This produces the VoiceInk-style "ripple" effect: each bar is driven by a
/// slightly different phase of the animation cycle, making the waveform look
/// organic and alive rather than uniform. The `phase` parameter (0…1) is
/// advanced by the caller's animation state and wraps cyclically.
///
/// Formula per bar i:
///   phaseOffset = sin(2π × (i / barCount) + 2π × phase) × phaseDepth × level
///   height = baseHeight + phaseOffset
///
/// [decision W2.2: VoiceInk uses averagePower + per-bar phase; this is our
///  analogous pure-math implementation. phase is caller-controlled so the
///  function stays deterministic and unit-testable. benchmark.md §7]
///
/// - Parameters:
///   - level:      Smoothed linear amplitude (0…1). Higher level → taller bars + more ripple.
///   - phase:      Animation phase (0…1); advances monotonically, wraps every cycle.
///   - barCount:   Number of bars. Must be > 0; returns empty array otherwise.
///   - minHeight:  Minimum bar height in points.
///   - maxHeight:  Maximum bar height in points.
///   - phaseDepth: Fraction of the range that the phase modulation occupies (0…1).
///                 [decision: 0.4 — 40% ripple depth feels natural without jarring. benchmark.md §7]
/// - Returns: Array of `barCount` heights, each in `[minHeight, maxHeight]`.
public func levelBarHeightsPhased(
    level: Double,
    phase: Double,
    barCount: Int = 15,
    minHeight: Double = 3.0,
    maxHeight: Double = 20.0,
    phaseDepth: Double = 0.4  // [decision W2.2: 40% ripple depth, benchmark.md §7]
) -> [Double] {
    guard barCount > 0 else { return [] }
    let range = maxHeight - minHeight
    return (0 ..< barCount).map { i in
        // Cosine envelope — same as `levelBarHeights`: center bar is tallest.
        let center = Double(barCount - 1) / 2.0
        let t = (Double(i) - center) / max(center, 1.0)   // -1…1
        let envelope = cos(t * .pi / 2.0)
        // Base height from the level × cosine envelope.
        let baseHeight = minHeight + range * level * envelope
        // Per-bar sinusoidal ripple: adds organic variation across bars.
        // Only active at non-zero level (silent = flat bars).
        let barPhase = 2.0 * .pi * (Double(i) / Double(barCount)) + 2.0 * .pi * phase
        let ripple = range * level * phaseDepth * sin(barPhase) * 0.5
        let height = baseHeight + ripple
        return min(max(height, minHeight), maxHeight)
    }
}
