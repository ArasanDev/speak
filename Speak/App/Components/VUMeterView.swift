// App/Components/VUMeterView.swift
//
// Segmented horizontal VU meter — the Settings mic-check + "Test My Voice"
// sandbox level indicator. 20 LED-style segments, uniform height, threshold
// coloring (green body → amber → red near full scale), like pro-audio channel
// meters. The caller feeds a perceptual, smoothed level
// (`levelPerceptual` + `levelSmoothedAsymmetric`); this view is pure display.
//
// Tokens: lit segments use speakOK/speakAccent/speakStateError; unlit use a
// hairline fill — no glow, no gradient, no pulse. [decision: restrained chrome]

import SpeakCore
import SwiftUI

struct VUMeterView: View {

    /// Perceptual display level (0…1), post `levelPerceptual` + smoothing.
    var level: Double
    /// Number of segments. [decision: 20 — fine enough to feel live on speech
    /// transients without turning into a blur at 85 ms update cadence]
    var segmentCount: Int = 20

    var body: some View {
        let lit = levelSegmentFill(level: level, segmentCount: segmentCount)
        HStack(spacing: 2) {
            ForEach(0 ..< segmentCount, id: \.self) { index in
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(index < lit ? segmentColor(at: index) : Color.speakSurface)
                    .frame(width: 3, height: 14)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Input level")
        .accessibilityValue("\(lit) of \(segmentCount)")
        // 150 ms spring per the settings-sensory spec — snappy, not sluggish.
        .animation(.spring(duration: 0.15), value: lit)
    }

    /// Threshold coloring: OK body, amber shoulder, red peak — the standard
    /// pro-audio VU ramp, expressed with existing SpeakTheme tokens.
    private func segmentColor(at index: Int) -> Color {
        let t = Double(index) / Double(max(segmentCount - 1, 1))
        if t >= 0.9 { return .speakStateError }
        if t >= 0.7 { return .speakAccent }
        return .speakOK
    }
}
