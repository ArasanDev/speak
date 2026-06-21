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
// Future wire point: when the real AVAudioEngine RMS feed is plumbed from
// AudioCapture → CaptureSession → DictationController → OverlayViewModel
// (builder-audio-stt + builder-engine cross-seam work, deferred from Phase C),
// the raw dB value is converted to linear here and fed as `level` on the model.

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
