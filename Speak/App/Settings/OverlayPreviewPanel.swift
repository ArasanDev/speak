// App/Settings/OverlayPreviewPanel.swift
//
// Live preview of the recording HUD panel used by `OverlaySettingsView`.
// Renders the REAL `VoiceAnimationView` (or the bare `WaveformView` for
// Spectrum Bars, matching `HUDLeadingSlot`) driven by a synthetic mic level,
// plus the REAL border layer (`AnimatedGradientBorder` / `EdgeFlowBorder`),
// so every control on the pane visibly does something — no dictation needed.

import SpeakCore
import SwiftUI

// MARK: - OverlayPreviewPanel

@MainActor
struct OverlayPreviewPanel: View {
    let store: SettingsStore

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Preview scale — the real 640-pt panel rendered at ~72% inside the
    /// settings canvas. Everything else derives from it.
    private static let previewScale: CGFloat = 0.72

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { tl in
            let t = tl.date.timeIntervalSinceReferenceDate
            let level = max(0.0, min(1.0,
                0.55 + 0.35 * sin(t * 2.1) + 0.18 * sin(t * 5.3)))
            panel(level: level)
                .overlay(border(level: level))
                // Room for the border's glow to paint outside the panel.
                .padding(10)
        }
        .padding(.horizontal, SpeakSpacing.md)
        .padding(.vertical, SpeakSpacing.sm + 4)
    }

    /// The same border-layer switch the HUD runs — state is pinned to
    /// `.listening` (the state users customize most) and the level follows
    /// the preview's synthetic mic signal.
    @ViewBuilder
    private func border(level: Double) -> some View {
        let tint = store.overlayBorderTint.fixedVoiceColor.map { [$0.color] }
        switch store.borderAnimationStyle {
        case .none:
            EmptyView()

        case .fullGlow:
            AnimatedGradientBorder(
                shape: HUDLane.panelShape,
                state: .listening,
                level: level,
                reduceMotion: reduceMotion,
                customPalette: tint
            )

        case .edgeFlow:
            EdgeFlowBorder(
                shape: HUDLane.panelShape,
                state: .listening,
                level: level,
                speed: store.borderFlowSpeed,
                count: store.borderFlowCount,
                reduceMotion: reduceMotion,
                customPalette: tint
            )
        }
    }

    private func panel(level: Double) -> some View {
        let size = store.overlaySize
        let h = size.height * Self.previewScale
        let w = size.width * Self.previewScale
        let slotSide = HUDLane.leadingSlotWidth * Self.previewScale
        return HStack(alignment: .center, spacing: SpeakSpacing.sm * Self.previewScale) {
            leadingSlot(level: level, side: slotSide)
            textLane
        }
        .padding(.leading, (SpeakSpacing.sm + 2) * Self.previewScale)
        .padding(.trailing, SpeakSpacing.sm * Self.previewScale)
        .frame(height: h)
        .frame(maxWidth: w)
        .background(
            HUDLane.panelShape
                .fill(Color.speakCardCanvas.opacity(0.85))
        )
        .overlay(
            // v2: the same subtle tint shift the real panel wears while listening.
            HUDLane.panelShape
                .fill(Color.speakVoiceBlue.opacity(HUDLane.stateWashOpacity(for: .listening)))
        )
        .overlay(
            HUDLane.panelShape
                .strokeBorder(Color.speakCardBorder, lineWidth: 1)
        )
        .frame(maxWidth: .infinity)
        .animation(.easeInOut(duration: 0.2), value: store.overlaySize)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Overlay preview")
    }

    /// Leading slot — mirrors `HUDLeadingSlot`: Spectrum Bars renders the
    /// bare analyser, the ring styles render the real chamber scaled down.
    @ViewBuilder
    private func leadingSlot(level: Double, side: CGFloat) -> some View {
        switch store.voiceAnimationStyle {
        case .spectrum:
            WaveformView(
                level: level,
                isActive: true,
                tint: store.voiceAnimationColor.color
            )
            .frame(width: side, height: side)

        case .sonar, .ringGauge:
            VoiceAnimationView(
                style: store.voiceAnimationStyle,
                tint: store.voiceAnimationColor.color,
                level: level,
                isActive: true
            )
            .scaleEffect(HUDLane.animationScale)
            .frame(width: side, height: side)
        }
    }

    /// Text lane — stand-in transcript + phase header (honors toggles).
    private var textLane: some View {
        VStack(alignment: .leading, spacing: 2) {
            if store.overlayShowPhaseHeader {
                HStack(spacing: 4) {
                    Circle()
                        .fill(Color.speakOnAir)
                        .frame(width: 5, height: 5)
                    Text("LISTENING")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .tracking(1.5)
                        .foregroundStyle(store.voiceAnimationColor.color)
                    if store.overlayShowTimer {
                        Text("· 0:07")
                            .font(.system(size: 8, design: .monospaced))
                            .foregroundStyle(Color.speakMica)
                    }
                }
            }
            Text("streamed transcript text flows here")
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(Color.speakBone.opacity(0.7))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
