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

    @State private var editingTheme = false

    private var store: SettingsStore { context.settingsStore }

    var body: some View {
        VStack(alignment: .leading, spacing: SpeakSpacing.lg) {
            appearanceCard
            colorThemeCard
            hudCard
            borderCard
        }
        .sheet(isPresented: $editingTheme) {
            if let engine = context.themeEngine {
                ThemeEditorSheet(engine: engine)
                    .speakThemed(with: engine)
            }
        }
    }

    // MARK: - Appearance mode (light / dark / system)

    private var appearanceCard: some View {
        SettingsSectionCard(title: "Appearance") {
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
                    .foregroundStyle(Color.speakMica)
            }
            .padding(.horizontal, SpeakSpacing.md)
            .padding(.vertical, SpeakSpacing.sm + 4)
        }
    }

    // MARK: - Color theme (runtime palette)

    /// The theme picker — rows of named palettes with preview dots (t3code's
    /// ThemeSettings pattern). Built-ins select directly; customs can be
    /// edited (the editor paints the app live) or deleted.
    private var colorThemeCard: some View {
        SettingsSectionCard(title: "Color Theme") {
            if let engine = context.themeEngine {
                ThemeRows(engine: engine, onEdit: { editingTheme = true })
            } else {
                SettingsRow("Color Theme", description: "Theme engine unavailable.")
            }
        }
    }

    // MARK: - Recording HUD

    private var hudCard: some View {
        SettingsSectionCard(title: "Recording HUD") {
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

// MARK: - ThemeRows

/// The theme list inside the "Color Theme" card: one row per theme —
/// preview dots (canvas · accent · agent channel), name, active check.
/// Custom themes get Edit (live draft editor) and Delete. Trailing "+"
/// creates a new custom theme seeded from the active one — the same
/// seed-from-active gesture as t3code's theme editor.
@MainActor
private struct ThemeRows: View {
    @ObservedObject var engine: ThemeEngine
    let onEdit: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ForEach(engine.themes) { theme in
                if theme.id != engine.themes.first?.id {
                    SettingsRowSeparator()
                }
                themeRow(theme)
            }
            SettingsRowSeparator()
            SettingsRow("New Theme", description: "Seeded from the active theme — edit it live.") {
                Button {
                    engine.beginDraft()
                    onEdit()
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.speakMica)
            }
        }
    }

    private func themeRow(_ theme: SpeakTheme) -> some View {
        let isActive = theme.id == engine.activeTheme.id
        return Button {
            engine.select(theme.id)
        } label: {
            HStack(spacing: SpeakSpacing.md) {
                previewDots(for: theme)
                Text(theme.name)
                    .font(.speakBody(.base, semibold: isActive))
                    .foregroundStyle(Color.speakBone)
                if theme.isBuiltIn {
                    Text("BUILT-IN")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Color.speakMica)
                }
                Spacer(minLength: 0)
                if !theme.isBuiltIn {
                    Button {
                        engine.editTheme(theme)
                        onEdit()
                    } label: {
                        Image(systemName: "pencil")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.speakMica)
                    .help("Edit theme")

                    Button(role: .destructive) {
                        engine.deleteCustomTheme(id: theme.id)
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.speakMica)
                    .help("Delete theme")
                }
                if isActive {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color.speakUIAccent)
                }
            }
            .padding(.horizontal, SpeakSpacing.md)
            .padding(.vertical, SpeakSpacing.sm + 4)
            .background(isActive ? Color.speakSidebarSelection : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Three dots: window canvas · accent · agent channel — the fastest
    /// possible read of a palette's character (t3code's ThemePreviewCircles).
    private func previewDots(for theme: SpeakTheme) -> some View {
        HStack(spacing: -4) {
            dot(theme.color(.windowCanvas))
            dot(theme.color(.accent))
            dot(theme.color(.agentViolet))
        }
    }

    private func dot(_ color: Color) -> some View {
        Circle()
            .fill(color)
            .frame(width: 14, height: 14)
            .overlay(Circle().stroke(Color.speakCardBorder, lineWidth: 1))
    }
}
