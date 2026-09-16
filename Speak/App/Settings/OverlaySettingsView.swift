// App/Settings/OverlaySettingsView.swift
//
// "Overlay" — the recording HUD's own Settings category. Owns every overlay
// panel control: panel layout, the leading-slot voice animation + its color,
// element visibility, and the optional animated border. Leads with a live
// preview (`OverlayPreviewPanel`) that renders the REAL voice
// animation with a simulated mic level, so picking a style or swatch shows
// the result immediately — no dictation needed.

import SpeakCore
import SwiftUI

// MARK: - OverlaySettingsView

@MainActor
struct OverlaySettingsView: View {
    let context: DashboardContext

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

    private var previewCard: some View {
        SettingsSectionCard(title: "Preview") {
            OverlayPreviewPanel(store: store)
        }
    }

    // MARK: - Panel layout

    /// Geometry of the floating panel — applies on the next dictation (the
    /// panel reframes itself at show-time), reflected live in the preview.
    private var layoutCard: some View {
        SettingsSectionCard(title: "Panel Layout") {
            SettingsRow(
                "Panel size",
                description: "Panel width and height — Compact 560×64, Standard 640×76, Wide 760×88."
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

    /// Visibility toggles for the panel's zones — the preview reflects
    /// each immediately.
    private var elementsCard: some View {
        SettingsSectionCard(title: "Elements") {
            SettingsRow(
                "Show timer",
                description: "The elapsed time riding inline in the header — live while listening, frozen on done."
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
        }
    }

    // MARK: - Recording HUD

    private var hudCard: some View {
        SettingsSectionCard(title: "Recording HUD") {
            // v2 (2026-09-17): no "HUD style" picker — the classic/Aurora
            // styles unified on the minimal pill; `hudStyle` stays persisted
            // for schema compat but no longer forks the view tree.
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
