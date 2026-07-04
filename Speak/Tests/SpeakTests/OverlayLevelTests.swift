// SpeakTests/OverlayLevelTests.swift
//
// Unit tests for `LevelMath` — the pure level-conversion utilities in
// `SpeakCore/Overlay/LevelMath.swift`. All tests are synchronous and
// deterministic; no AppKit, no SwiftUI, no audio hardware required.
//
// Coverage:
//   1.  levelLinear(fromDB:)               — 0 dB → 1.0 (full scale)
//   2.  levelLinear(fromDB:)               — −∞ / −160 dB → ≈ 0.0
//   3.  levelLinear(fromDB:)               — above 0 dB clamped to 1.0
//   4.  levelLinear(fromDB:)               — known mid value (−20 dB → 0.1)
//   5.  levelSmoothed(previous:target:)    — stationary (prev = target) is identity
//   6.  levelSmoothed(previous:target:)    — 0 → 1 converges toward 1 over iterations
//   7.  levelSmoothed(previous:target:)    — explicit math (0.7/0.3 split)
//   8.  levelBarHeights(level:)            — zero level → all bars at minHeight
//   9.  levelBarHeights(level:)            — full level → center bar at maxHeight
//   10. levelBarHeights(level:)            — returns exactly barCount elements
//   11. levelBarHeights(level:)            — barCount=0 returns empty
//   12. levelBarHeights(level:)            — all bars within [minHeight, maxHeight]
//   13. levelBarHeights(level:)            — waveform is symmetric (center-peaked)
//   W2.1:
//   14. AudioCapture.rmsLevel(buffer:)     — silence buffer → 0.0
//   15. AudioCapture.rmsLevel(buffer:)     — full-scale buffer → 1.0
//   W2.2:
//   16. levelBarHeightsPhased(level:phase:) — zero level → all bars at minHeight
//   17. levelBarHeightsPhased(level:phase:) — all bars within [minHeight, maxHeight]
//   18. levelBarHeightsPhased(level:phase:) — returns exactly barCount elements
//   19. levelBarHeightsPhased(level:phase:) — barCount=0 returns empty
//   20. levelBarHeightsPhased(level:phase:) — different phase produces different heights
//   W2.3:
//   21. levelPerceptual(rms:)              — silence (rms=0) → 0.0
//   22. levelPerceptual(rms:)              — full-scale RMS → 1.0 (clamped)
//   23. levelPerceptual(rms:)              — quiet speech (rms=0.01) → visible positive value
//   24. levelPerceptual(rms:)              — loud speech (rms=0.25) → high display value
//   25. levelPerceptual(rms:)              — output always in [0, 1] for all inputs
//   26. levelPerceptual(rms:)              — below noise floor → 0.0 (calm state)
//   27. levelSmoothedAsymmetric(…)        — stationary is identity
//   28. levelSmoothedAsymmetric(…)        — rising uses attackCoeff
//   29. levelSmoothedAsymmetric(…)        — falling uses decayCoeff
//   30. levelSmoothedAsymmetric(…)        — attack is faster than release

import AVFoundation
@testable import SpeakCore
import XCTest

final class OverlayLevelTests: XCTestCase {

    // MARK: - levelLinear(fromDB:)

    // 1. 0 dB → 1.0 (full scale, power → amplitude)
    func testLevelLinearZeroDBIsFullScale() {
        XCTAssertEqual(levelLinear(fromDB: 0.0), 1.0, accuracy: 1e-9)
    }

    // 2. −160 dB → effectively 0 (silence floor clamped)
    func testLevelLinearSilenceFloor() {
        let result = levelLinear(fromDB: -160.0)
        XCTAssertLessThan(result, 1e-7, "−160 dB should be effectively 0")
        XCTAssertGreaterThanOrEqual(result, 0.0, "Must not go negative")
    }

    // 3. Values above 0 dB are clamped to 1.0
    func testLevelLinearAboveZeroDBClampedToOne() {
        XCTAssertEqual(levelLinear(fromDB: 6.0), 1.0, accuracy: 1e-9)
        XCTAssertEqual(levelLinear(fromDB: 100.0), 1.0, accuracy: 1e-9)
    }

    // 4. −20 dB → 0.1 (known reference: pow(10, −20/20) = pow(10, −1) = 0.1)
    func testLevelLinearMinus20DB() {
        let result = levelLinear(fromDB: -20.0)
        XCTAssertEqual(result, 0.1, accuracy: 1e-9)
    }

    // MARK: - levelSmoothed(previous:target:)

    // 5. Stationary: prev == target → output == target (fixed point)
    func testLevelSmoothedStationaryIsIdentity() {
        for value in [0.0, 0.5, 1.0] {
            let result = levelSmoothed(previous: value, target: value)
            XCTAssertEqual(result, value, accuracy: 1e-12,
                "levelSmoothed should be a fixed point when prev == target")
        }
    }

    // 6. Converging: repeated smoothing of 0→1 reaches the target asymptotically
    func testLevelSmoothedConvergesOver10Frames() {
        var prev = 0.0
        for _ in 0 ..< 30 {
            prev = levelSmoothed(previous: prev, target: 1.0)
        }
        XCTAssertGreaterThan(prev, 0.99, "After 30 frames, smoothed value should be close to 1.0")
    }

    // 7. Explicit math: prev=0.8, target=0.2 → 0.8*0.7 + 0.2*0.3 = 0.56 + 0.06 = 0.62
    func testLevelSmoothedExplicitMath() {
        let result = levelSmoothed(previous: 0.8, target: 0.2)
        XCTAssertEqual(result, 0.62, accuracy: 1e-10)
    }

    // MARK: - levelBarHeights(level:barCount:minHeight:maxHeight:)

    // 8. Level=0 → all bars at minHeight
    func testBarHeightsZeroLevelAllMin() {
        let heights = levelBarHeights(level: 0.0, barCount: 5, minHeight: 3.0, maxHeight: 20.0)
        for h in heights {
            XCTAssertEqual(h, 3.0, accuracy: 1e-9,
                "At level=0 every bar should be at minHeight")
        }
    }

    // 9. Level=1 → center bar at maxHeight
    func testBarHeightsFullLevelCenterIsMax() {
        let barCount = 5
        let heights = levelBarHeights(level: 1.0, barCount: barCount, minHeight: 3.0, maxHeight: 20.0)
        let centerIndex = barCount / 2   // index 2 for 5 bars
        XCTAssertEqual(heights[centerIndex], 20.0, accuracy: 1e-9,
            "At level=1 the center bar should be at maxHeight")
    }

    // 10. Returns exactly barCount elements
    func testBarHeightsReturnCountMatchesBarCount() {
        for n in [1, 3, 5, 7] {
            let heights = levelBarHeights(level: 0.5, barCount: n)
            XCTAssertEqual(heights.count, n, "Expected \(n) bars, got \(heights.count)")
        }
    }

    // 11. barCount=0 → empty array
    func testBarHeightsZeroBarCountIsEmpty() {
        let heights = levelBarHeights(level: 0.5, barCount: 0)
        XCTAssertTrue(heights.isEmpty, "barCount=0 must return an empty array")
    }

    // 12. All bar heights are within [minHeight, maxHeight]
    func testBarHeightsAllWithinBounds() {
        for level in [0.0, 0.25, 0.5, 0.75, 1.0] {
            let heights = levelBarHeights(level: level, barCount: 5, minHeight: 3.0, maxHeight: 20.0)
            for h in heights {
                XCTAssertGreaterThanOrEqual(h, 3.0, "Bar below minHeight at level=\(level)")
                XCTAssertLessThanOrEqual(h, 20.0, "Bar above maxHeight at level=\(level)")
            }
        }
    }

    // 13. Waveform is symmetric: bar[i] == bar[n-1-i] for all i (cosine envelope)
    func testBarHeightsSymmetric() {
        let heights = levelBarHeights(level: 0.7, barCount: 5, minHeight: 3.0, maxHeight: 20.0)
        for i in 0 ..< heights.count / 2 {
            let mirror = heights.count - 1 - i
            XCTAssertEqual(heights[i], heights[mirror], accuracy: 1e-9,
                "Bar \(i) and bar \(mirror) should be equal (symmetric envelope)")
        }
    }

    // MARK: - W2.1: AudioCapture.rmsLevel(buffer:)

    // Helper: build a silence or constant-level PCM buffer for testing.
    // Returns nil and records an XCTFail if the buffer cannot be constructed
    // (should never happen with these fixed parameters on any macOS 26 device).
    private func makePCMBuffer(frameCount: AVAudioFrameCount, fillValue: Float) -> AVAudioPCMBuffer? {
        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 16_000,
            channels: 1,
            interleaved: false
        ) else {
            XCTFail("Could not create AVAudioFormat for test buffer")
            return nil
        }
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            XCTFail("Could not create AVAudioPCMBuffer for test")
            return nil
        }
        buffer.frameLength = frameCount
        if let channel = buffer.floatChannelData?[0] {
            for idx in 0 ..< Int(frameCount) {
                channel[idx] = fillValue
            }
        }
        return buffer
    }

    // 14. Silence buffer (all zeros) → rmsLevel = 0.0
    func testRMSLevel_silenceBuffer_isZero() {
        guard let buffer = makePCMBuffer(frameCount: 1024, fillValue: 0.0) else { return }
        let rms = AudioCapture.rmsLevel(buffer: buffer)
        XCTAssertEqual(rms, 0.0, accuracy: 1e-9,
            "RMS of a silence buffer must be 0.0")
    }

    // 15. Full-scale constant buffer (all 1.0) → rmsLevel ≈ 1.0
    func testRMSLevel_fullScaleBuffer_isOne() {
        guard let buffer = makePCMBuffer(frameCount: 1024, fillValue: 1.0) else { return }
        let rms = AudioCapture.rmsLevel(buffer: buffer)
        XCTAssertEqual(rms, 1.0, accuracy: 1e-9,
            "RMS of a full-scale buffer must be 1.0")
    }

    // MARK: - W2.2: levelBarHeightsPhased(level:phase:)

    // 16. Zero level → all bars at minHeight regardless of phase
    func testPhasedBarHeights_zeroLevel_allMinHeight() {
        for phase in [0.0, 0.25, 0.5, 0.75, 1.0] {
            let heights = levelBarHeightsPhased(
                level: 0.0,
                phase: phase,
                barCount: 15,
                minHeight: 3.0,
                maxHeight: 20.0
            )
            for h in heights {
                XCTAssertEqual(h, 3.0, accuracy: 1e-9,
                    "At level=0 every bar must be at minHeight (phase=\(phase))")
            }
        }
    }

    // 17. All bars within [minHeight, maxHeight]
    func testPhasedBarHeights_allWithinBounds() {
        for level in [0.0, 0.3, 0.6, 1.0] {
            for phase in [0.0, 0.5, 1.0] {
                let heights = levelBarHeightsPhased(
                    level: level, phase: phase,
                    barCount: 15, minHeight: 3.0, maxHeight: 20.0
                )
                for h in heights {
                    XCTAssertGreaterThanOrEqual(h, 3.0,
                        "Bar below minHeight (level=\(level), phase=\(phase))")
                    XCTAssertLessThanOrEqual(h, 20.0,
                        "Bar above maxHeight (level=\(level), phase=\(phase))")
                }
            }
        }
    }

    // 18. Returns exactly barCount elements
    func testPhasedBarHeights_returnCountMatchesBarCount() {
        for n in [1, 5, 15] {
            let heights = levelBarHeightsPhased(level: 0.5, phase: 0.3, barCount: n)
            XCTAssertEqual(heights.count, n, "Expected \(n) bars, got \(heights.count)")
        }
    }

    // 19. barCount=0 → empty array
    func testPhasedBarHeights_zeroBarCountIsEmpty() {
        let heights = levelBarHeightsPhased(level: 0.5, phase: 0.3, barCount: 0)
        XCTAssertTrue(heights.isEmpty, "barCount=0 must return an empty array")
    }

    // 20. Different phase values produce different bar heights (phase drives ripple)
    func testPhasedBarHeights_differentPhasesProduceDifferentHeights() {
        let heightsA = levelBarHeightsPhased(
            level: 0.7, phase: 0.0, barCount: 15, minHeight: 3.0, maxHeight: 20.0
        )
        let heightsB = levelBarHeightsPhased(
            level: 0.7, phase: 0.25, barCount: 15, minHeight: 3.0, maxHeight: 20.0
        )
        // At non-zero phase depth the heights should differ for at least some bars.
        let allEqual = zip(heightsA, heightsB).allSatisfy { abs($0.0 - $0.1) < 1e-9 }
        XCTAssertFalse(allEqual,
            "phase=0 and phase=0.25 should produce different bar heights")
    }

    // MARK: - W2.3: levelPerceptual(rms:)

    // 21. Silence (rms=0) → 0.0
    func testLevelPerceptual_zeroRMS_isZero() {
        XCTAssertEqual(levelPerceptual(rms: 0.0), 0.0, accuracy: 1e-9,
            "Silence RMS must map to 0.0")
    }

    // 22. Full-scale RMS (1.0) → 1.0 (0 dBFS is above clipFloor -3 dBFS → clamped to 1.0)
    func testLevelPerceptual_fullScaleRMS_isOne() {
        XCTAssertEqual(levelPerceptual(rms: 1.0), 1.0, accuracy: 1e-9,
            "Full-scale RMS must clamp to 1.0")
    }

    // 23. Typical quiet speech RMS (~0.01, ≈ -40 dBFS) maps to a visible positive value
    //     -40 dBFS with noiseFloor=-55, clipFloor=-3 → (−40 − −55)/(−3 − −55) = 15/52 ≈ 0.288
    func testLevelPerceptual_quietSpeech_isVisible() {
        let rms = 0.01   // ≈ -40 dBFS
        let result = levelPerceptual(rms: rms)
        XCTAssertGreaterThan(result, 0.1,
            "Quiet speech RMS 0.01 should produce a visible bar level (> 0.1)")
        XCTAssertLessThan(result, 0.7,
            "Quiet speech RMS 0.01 should not fill bars to 70% (not loud)")
    }

    // 24. Loud speech RMS (~0.25, ≈ -12 dBFS) maps to a high display value
    //     -12 dBFS → (−12 − −55)/(−3 − −55) = 43/52 ≈ 0.827
    func testLevelPerceptual_loudSpeech_isHigh() {
        let rms = 0.25   // ≈ -12 dBFS
        let result = levelPerceptual(rms: rms)
        XCTAssertGreaterThan(result, 0.6,
            "Loud speech RMS 0.25 should produce a high bar level (> 0.6)")
        XCTAssertLessThanOrEqual(result, 1.0,
            "Result must not exceed 1.0")
    }

    // 25. Output is always in [0, 1] for all RMS inputs
    func testLevelPerceptual_alwaysInUnitRange() {
        let inputs = [0.0, 0.001, 0.01, 0.05, 0.1, 0.5, 0.9, 1.0]
        for rms in inputs {
            let result = levelPerceptual(rms: rms)
            XCTAssertGreaterThanOrEqual(result, 0.0,
                "levelPerceptual must be ≥ 0 for rms=\(rms)")
            XCTAssertLessThanOrEqual(result, 1.0,
                "levelPerceptual must be ≤ 1 for rms=\(rms)")
        }
    }

    // 26. Below noise floor (rms corresponding to < -55 dBFS) → 0.0
    //     -55 dBFS = 10^(-55/20) ≈ 0.00178. So rms=0.001 < 0.00178 → 0.0
    func testLevelPerceptual_belowNoiseFloor_isZero() {
        let rms = 0.001   // ≈ -60 dBFS, below -55 dBFS noise floor
        let result = levelPerceptual(rms: rms)
        XCTAssertEqual(result, 0.0, accuracy: 1e-9,
            "RMS below noise floor must map to 0.0 (calm state)")
    }

    // MARK: - W2.3: levelSmoothedAsymmetric(previous:target:)

    // 27. Stationary (prev == target) → output == target (fixed point for asymmetric too)
    func testLevelSmoothedAsymmetric_stationaryIsIdentity() {
        for value in [0.0, 0.5, 1.0] {
            let result = levelSmoothedAsymmetric(previous: value, target: value)
            XCTAssertEqual(result, value, accuracy: 1e-9,
                "Asymmetric smoothing must be a fixed point when prev == target")
        }
    }

    // 28. Rising signal uses attackCoeff (faster): with attackCoeff=0.5, result = 0.5*prev + 0.5*target
    func testLevelSmoothedAsymmetric_risingUsesAttackCoeff() {
        let result = levelSmoothedAsymmetric(previous: 0.2, target: 0.8,
                                              attackCoeff: 0.5, decayCoeff: 0.9)
        // rising: coeff = attackCoeff = 0.5 → 0.2*0.5 + 0.8*0.5 = 0.5
        XCTAssertEqual(result, 0.5, accuracy: 1e-9,
            "Rising signal must use attackCoeff")
    }

    // 29. Falling signal uses decayCoeff (slower): with decayCoeff=0.9, result = 0.9*prev + 0.1*target
    func testLevelSmoothedAsymmetric_fallingUsesDecayCoeff() {
        let result = levelSmoothedAsymmetric(previous: 0.8, target: 0.2,
                                              attackCoeff: 0.5, decayCoeff: 0.9)
        // falling: coeff = decayCoeff = 0.9 → 0.8*0.9 + 0.2*0.1 = 0.72 + 0.02 = 0.74
        XCTAssertEqual(result, 0.74, accuracy: 1e-9,
            "Falling signal must use decayCoeff")
    }

    // 30. Attack is faster than release: identical signal change, attack reaches target faster
    func testLevelSmoothedAsymmetric_attackFasterThanRelease() {
        // Rising: 0 → 1
        var risingPrev = 0.0
        for _ in 0 ..< 5 {
            risingPrev = levelSmoothedAsymmetric(previous: risingPrev, target: 1.0)
        }
        // Falling: 1 → 0
        var fallingPrev = 1.0
        for _ in 0 ..< 5 {
            fallingPrev = levelSmoothedAsymmetric(previous: fallingPrev, target: 0.0)
        }
        // After 5 frames, rising should be closer to 1.0 than falling is to 0.0
        // i.e. risingPrev > (1 - fallingPrev)
        XCTAssertGreaterThan(risingPrev, 1.0 - fallingPrev,
            "Attack should be faster than release (risingPrev=\(risingPrev), fallingPrev=\(fallingPrev))")
    }
}
