// App/Settings/AppearanceHUDSettingsView.swift
//
// "Appearance & HUD" — the sixth Settings category. App theme, recording-HUD
// style (Classic vs Aurora), and the HUD border animation. Same SettingsStore
// bindings as the legacy General tab's HUDStyleSection/BorderStyleSection,
// restyled into SettingsChrome cards.

import SpeakCore
import SwiftUI

// MARK: - AppearanceHUDSettingsView

@MainActor
struct AppearanceHUDSettingsView: View {
    let context: DashboardContext

    private var store: SettingsStore { context.settingsStore }

    var body: some View {
        VStack(alignment: .leading, spacing: SpeakSpacing.lg) {
            themeCard
            hudCard
            borderCard
        }
    }

    // MARK: - Theme

    private var themeCard: some View {
        SettingsSectionCard(title: "Theme", systemImage: "circle.lefthalf.filled") {
            VStack(alignment: .leading, spacing: SpeakSpacing.sm) {
                Picker("", selection: Binding(
                    get: { store.appTheme },
                    set: { store.appTheme = $0 }
                )) {
                    Text("System").tag(AppTheme.system)
                    Text("Light").tag(AppTheme.light)
                    Text("Dark").tag(AppTheme.dark)
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                Text("Applies to the dashboard, settings, and HUD.")
                    .font(.speakBody(.caption))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, SpeakSpacing.md)
            .padding(.vertical, SpeakSpacing.sm + 4)
        }
    }

    // MARK: - Recording HUD

    private var hudCard: some View {
        SettingsSectionCard(title: "Recording HUD", systemImage: "waveform") {
            SettingsRow(
                "HUD style",
                description: "Aurora is an ambient orb with live materializing transcript words; Classic is the 15-bar waveform."
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
        }
    }

    // MARK: - Border animation

    private var borderCard: some View {
        SettingsSectionCard(title: "Animated Border", systemImage: "rectangle.on.rectangle") {
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
                        in: 1...3
                    )
                }
            }
        }
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
