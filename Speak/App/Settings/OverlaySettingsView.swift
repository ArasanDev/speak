// App/Settings/OverlaySettingsView.swift
//
// "Overlay" — the recording HUD's own Settings category. Owns every overlay
// panel control: HUD style, the left-zone voice animation + its color, and
// the animated border. Leads with a live preview capsule that renders the
// REAL `VoiceAnimationView` with a simulated mic level, so picking a style
// or swatch shows the result immediately — no dictation needed.

import SpeakCore
import SwiftUI

// MARK: - OverlaySettingsView

@MainActor
struct OverlaySettingsView: View {
    let context: DashboardContext

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var store: SettingsStore { context.settingsStore }

    var body: some View {
        VStack(alignment: .leading, spacing: SpeakSpacing.lg) {
            previewCard
            layoutCard
            hudCard
            elementsCard
            borderCard
        }
    }

    // MARK: - Live preview

    /// A mock of the 640x76 recording capsule at ~2/3 scale: the real voice
    /// animation on the left, a dotted divider, a frozen timer on the right —
    /// wrapped in the REAL border layer (`AnimatedGradientBorder` /
    /// `EdgeFlowBorder`) so every control on this pane visibly does something.
    /// A TimelineView feeds a synthetic mic level so the chosen style and
    /// color animate exactly as they will in-game.
    /// Preview scale — the real 640-pt panel rendered at ~72% inside the
    /// settings canvas. Everything else derives from it.
    private static let previewScale: CGFloat = 0.72

    private var previewCard: some View {
        SettingsSectionCard(title: "Preview") {
            TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { tl in
                let t = tl.date.timeIntervalSinceReferenceDate
                let level = max(0.0, min(1.0,
                    0.55 + 0.35 * sin(t * 2.1) + 0.18 * sin(t * 5.3)))
                previewCapsule(level: level)
                    .overlay(previewBorder(level: level))
                    // Room for the border's glow to paint outside the capsule.
                    .padding(10)
            }
            .padding(.horizontal, SpeakSpacing.md)
            .padding(.vertical, SpeakSpacing.sm + 4)
        }
    }

    /// The same border-layer switch the HUD runs — state is pinned to
    /// `.listening` (the state users customize most) and the level follows
    /// the preview's synthetic mic signal.
    @ViewBuilder
    private func previewBorder(level: Double) -> some View {
        let tint = store.overlayBorderTint.fixedVoiceColor.map { [$0.color] }
        switch store.borderAnimationStyle {
        case .none:
            EmptyView()

        case .fullGlow:
            AnimatedGradientBorder(
                shape: Capsule(style: .continuous),
                state: .listening,
                level: level,
                reduceMotion: reduceMotion,
                customPalette: tint
            )

        case .edgeFlow:
            EdgeFlowBorder(
                shape: Capsule(style: .continuous),
                state: .listening,
                level: level,
                speed: store.borderFlowSpeed,
                count: store.borderFlowCount,
                reduceMotion: reduceMotion,
                customPalette: tint
            )
        }
    }

    private func previewCapsule(level: Double) -> some View {
        let size = store.overlaySize
        let h = size.height * Self.previewScale
        let w = size.width * Self.previewScale
        let animSide = size.endZoneWidth * Self.previewScale
        return HStack(spacing: 0) {
            // Left zone — the real voice animation, scaled with the preset.
            VoiceAnimationView(
                style: store.voiceAnimationStyle,
                tint: store.voiceAnimationColor.color,
                level: level,
                isActive: true
            )
            .frame(width: animSide, height: animSide)
            .padding(.leading, SpeakSpacing.sm)

            previewDivider

            // Text lane — stand-in transcript + phase header (honors toggles).
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
                    }
                }
                Text("streamed transcript text flows here")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(Color.speakBone.opacity(0.7))
                    .lineLimit(1)
            }
            .padding(.horizontal, SpeakSpacing.sm)
            .frame(maxWidth: .infinity, alignment: .leading)

            if store.overlayShowTimer {
                previewDivider

                // Right zone — frozen timer.
                Text("0:07")
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color.speakBone)
                    .padding(.trailing, SpeakSpacing.sm)
            }
        }
        .frame(height: h)
        .frame(maxWidth: w)
        .background(
            Capsule()
                .fill(Color.speakCardCanvas.opacity(0.85))
        )
        .overlay(
            Capsule()
                .stroke(Color.speakBone.opacity(0.35), lineWidth: 2)
        )
        .frame(maxWidth: .infinity)
        .animation(.easeInOut(duration: 0.2), value: store.overlaySize)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Overlay preview")
    }

    /// The HUD's dotted full-height divider, reproduced at preview scale.
    private var previewDivider: some View {
        DottedVRule()
            .stroke(
                Color.speakBone.opacity(0.45),
                style: StrokeStyle(lineWidth: 1.5, dash: [4, 3])
            )
            .frame(width: 1.5)
            .padding(.vertical, 6)
    }

    // MARK: - Panel layout

    /// Geometry of the floating panel — applies on the next dictation (the
    /// panel reframes itself at show-time), reflected live in the preview.
    private var layoutCard: some View {
        SettingsSectionCard(title: "Panel Layout") {
            SettingsRow(
                "Panel size",
                description: "Capsule width and height — Compact 560×64, Standard 640×76, Wide 760×88."
            ) {
                Picker("", selection: Binding(
                    get: { store.overlaySize },
                    set: { store.overlaySize = $0 }
                )) {
                    Text("Compact").tag(OverlayPanelSize.compact)
                    Text("Standard").tag(OverlayPanelSize.standard)
                    Text("Wide").tag(OverlayPanelSize.wide)
                }
                .pickerStyle(.menu)
                .fixedSize()
            }

            SettingsRowSeparator()

            SettingsRow(
                "Panel position",
                description: "Which screen edge the panel anchors to while dictating."
            ) {
                Picker("", selection: Binding(
                    get: { store.overlayPosition },
                    set: { store.overlayPosition = $0 }
                )) {
                    Text("Bottom").tag(OverlayPanelPosition.bottom)
                    Text("Top").tag(OverlayPanelPosition.top)
                }
                .pickerStyle(.menu)
                .fixedSize()
            }
        }
    }

    // MARK: - Elements

    /// Visibility toggles for the capsule's zones — the preview reflects
    /// each immediately.
    private var elementsCard: some View {
        SettingsSectionCard(title: "Elements") {
            SettingsRow(
                "Show timer",
                description: "The right-side response zone — live seconds, then the ✓ and final time."
            ) {
                Toggle("", isOn: Binding(
                    get: { store.overlayShowTimer },
                    set: { store.overlayShowTimer = $0 }
                ))
                .toggleStyle(.switch)
                .labelsHidden()
            }

            SettingsRowSeparator()

            SettingsRow(
                "Show phase header",
                description: "The LISTENING / POLISHING / DONE word above the transcript."
            ) {
                Toggle("", isOn: Binding(
                    get: { store.overlayShowPhaseHeader },
                    set: { store.overlayShowPhaseHeader = $0 }
                ))
                .toggleStyle(.switch)
                .labelsHidden()
            }

            SettingsRowSeparator()

            SettingsRow(
                "Dim when idle",
                description: "Voice animation rests at reduced strength when the mic isn't capturing."
            ) {
                Toggle("", isOn: Binding(
                    get: { store.overlayIdleDim },
                    set: { store.overlayIdleDim = $0 }
                ))
                .toggleStyle(.switch)
                .labelsHidden()
            }
        }
    }

    // MARK: - Recording HUD

    private var hudCard: some View {
        SettingsSectionCard(title: "Recording HUD") {
            SettingsRow(
                "HUD style",
                description: "Both styles share the capsule frame; Aurora adds an ambient animated border."
            ) {
                Picker("", selection: Binding(
                    get: { store.hudStyle },
                    set: { store.hudStyle = $0 }
                )) {
                    Text("Classic").tag(HUDStyle.classic)
                    Text("Aurora").tag(HUDStyle.aurora)
                }
                .pickerStyle(.menu)
                .fixedSize()
            }

            SettingsRowSeparator()

            SettingsRow(
                "Voice animation",
                description: "The left-side voice visual while dictating — live mic level drives it."
            ) {
                Picker("", selection: Binding(
                    get: { store.voiceAnimationStyle },
                    set: { store.voiceAnimationStyle = $0 }
                )) {
                    Text("Sonar Ping").tag(VoiceAnimationStyle.sonar)
                    Text("Ring Gauge").tag(VoiceAnimationStyle.ringGauge)
                    Text("Spectrum Bars").tag(VoiceAnimationStyle.spectrum)
                }
                .pickerStyle(.menu)
                .fixedSize()
            }

            SettingsRowSeparator()

            SettingsRow(
                "Animation color",
                description: "The hue the voice animation draws with."
            ) {
                HStack(spacing: SpeakSpacing.sm) {
                    ForEach(VoiceAnimationColor.allCases, id: \.self) { choice in
                        Button {
                            store.voiceAnimationColor = choice
                        } label: {
                            Circle()
                                .fill(choice.color)
                                .frame(width: 18, height: 18)
                                .overlay(
                                    Circle()
                                        .strokeBorder(
                                            choice == store.voiceAnimationColor
                                                ? Color.speakBone
                                                : Color.clear,
                                            lineWidth: 2
                                        )
                                        .padding(-3)
                                )
                                .contentShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .help(choice.rawValue.capitalized)
                        .accessibilityLabel("\(choice.rawValue) animation color")
                        .accessibilityAddTraits(
                            choice == store.voiceAnimationColor ? .isSelected : []
                        )
                    }
                }
            }
        }
    }

    // MARK: - Animated border

    private var borderCard: some View {
        SettingsSectionCard(title: "Animated Border") {
            SettingsRow(
                "Border animation",
                description: borderCaption
            ) {
                Picker("", selection: Binding(
                    get: { store.borderAnimationStyle },
                    set: { store.borderAnimationStyle = $0 }
                )) {
                    Text("None").tag(BorderAnimationStyle.none)
                    Text("Full Glow").tag(BorderAnimationStyle.fullGlow)
                    Text("Edge Flow").tag(BorderAnimationStyle.edgeFlow)
                }
                .pickerStyle(.menu)
                .fixedSize()
            }

            if store.borderAnimationStyle != .none {
                SettingsRowSeparator()

                SettingsRow(
                    "Border color",
                    description: "Adaptive follows state colors (listening/polishing/done). A fixed hue pins the border in every state."
                ) {
                    HStack(spacing: SpeakSpacing.sm) {
                        ForEach(OverlayBorderTint.allCases, id: \.self) { choice in
                            Button {
                                store.overlayBorderTint = choice
                            } label: {
                                borderSwatch(choice)
                            }
                            .buttonStyle(.plain)
                            .help(choice == .adaptive ? "Adaptive (state colors)" : choice.rawValue.capitalized)
                            .accessibilityLabel("\(choice.rawValue) border color")
                            .accessibilityAddTraits(
                                choice == store.overlayBorderTint ? .isSelected : []
                            )
                        }
                    }
                }
            }

            if store.borderAnimationStyle == .edgeFlow {
                SettingsRowSeparator()

                SettingsRow("Flow speed") {
                    Picker("", selection: Binding(
                        get: { store.borderFlowSpeed },
                        set: { store.borderFlowSpeed = $0 }
                    )) {
                        Text("Slow (6s)").tag(BorderFlowSpeed.slow)
                        Text("Medium (3s)").tag(BorderFlowSpeed.medium)
                        Text("Fast (1.5s)").tag(BorderFlowSpeed.fast)
                    }
                    .pickerStyle(.menu)
                    .fixedSize()
                }

                SettingsRowSeparator()

                SettingsRow(
                    "Flowing lights",
                    description: "Number of light pulses traveling the border."
                ) {
                    Stepper(
                        "\(store.borderFlowCount)",
                        value: Binding(
                            get: { store.borderFlowCount },
                            set: { store.borderFlowCount = $0 }
                        ),
                        in: 1...6
                    )
                }
            }
        }
    }

    /// One border-tint swatch — `.adaptive` draws a 4-hue state arc (the
    /// stateful default), fixed hues draw a solid dot like the animation
    /// color row.
    private func borderSwatch(_ choice: OverlayBorderTint) -> some View {
        ZStack {
            if let fixed = choice.fixedVoiceColor {
                Circle().fill(fixed.color)
            } else {
                Circle().fill(
                    AngularGradient(
                        colors: [.speakOnAir, .speakAgentViolet, .speakDelivered, .speakOnAir],
                        center: .center
                    )
                )
            }
        }
        .frame(width: 18, height: 18)
        .overlay(
            Circle()
                .strokeBorder(
                    choice == store.overlayBorderTint ? Color.speakBone : Color.clear,
                    lineWidth: 2
                )
                .padding(-3)
        )
        .contentShape(Circle())
    }

    private var borderCaption: String {
        switch store.borderAnimationStyle {
        case .none:
            return "Plain panel edges."

        case .fullGlow:
            return "Rotating conic gradient glow around the HUD."

        case .edgeFlow:
            return "Traveling lights that move around the border perimeter."
        }
    }
}

// MARK: - DottedVRule

/// Full-height vertical hairline drawn with a dashed stroke — the same
/// dotted divider language as the recording capsule's zone rules.
private struct DottedVRule: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.midX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        return p
    }
}
