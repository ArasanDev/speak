// App/Settings/AppearanceHUDSettingsView.swift
//
// "Appearance & HUD" — the sixth Settings category. App theme, recording-HUD
// style (Classic vs Aurora), and the HUD border animation. The legacy General
// tab's HUDStyleSection/BorderStyleSection were superseded by these
// SettingsChrome cards and removed.

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
                .tint(.speakUIAccent)

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
/// Custom themes get Edit (live draft editor) and Delete (confirmed — a
/// deleted theme can't be recovered). The trailing row creates a new custom
/// theme seeded from the active one — the same seed-from-active gesture as
/// t3code's theme editor.
@MainActor
private struct ThemeRows: View {
    @ObservedObject var engine: ThemeEngine
    let onEdit: () -> Void

    /// The custom theme awaiting a confirmed deletion — nil clears the dialog.
    @State private var pendingDelete: SpeakTheme?

    var body: some View {
        VStack(spacing: 0) {
            ForEach(engine.themes) { theme in
                if theme.id != engine.themes.first?.id {
                    SettingsRowSeparator()
                }
                themeRow(theme)
            }
            SettingsRowSeparator()
            newThemeRow
        }
        .confirmationDialog(
            "Delete “\(pendingDelete?.name ?? "")”?",
            isPresented: Binding(
                get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete Theme", role: .destructive) {
                if let theme = pendingDelete {
                    engine.deleteCustomTheme(id: theme.id)
                }
                pendingDelete = nil
            }
            Button("Cancel", role: .cancel) { pendingDelete = nil }
        } message: {
            Text("Custom themes can't be recovered once deleted.")
        }
    }

    private func themeRow(_ theme: SpeakTheme) -> some View {
        let isActive = theme.id == engine.activeTheme.id
        return HStack(spacing: 0) {
            // Selection occupies the row's leading stretch; Edit/Delete sit
            // beside it as siblings — nested Buttons inside a Button label
            // have unreliable hit-testing on macOS.
            Button {
                engine.select(theme.id)
            } label: {
                HStack(spacing: SpeakSpacing.md) {
                    previewDots(for: theme)
                    Text(theme.name)
                        .font(.speakBody(.base, semibold: isActive))
                        .foregroundStyle(Color.speakBone)
                    if theme.isBuiltIn {
                        SettingsStatusPill(text: "Built-in")
                    }
                    Spacer(minLength: 0)
                }
                .padding(.leading, SpeakSpacing.md)
                .padding(.trailing, SpeakSpacing.sm)
                .padding(.vertical, SpeakSpacing.sm + 4)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(isActive ? .isSelected : [])
            .accessibilityHint("Activate to use this theme")

            if !theme.isBuiltIn {
                customActions(for: theme)
            }

            // The active check always lands at the row's trailing edge —
            // same slot whether or not the row carries Edit/Delete buttons.
            if isActive {
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color.speakUIAccent)
            }
        }
        .padding(.trailing, SpeakSpacing.md)
        .background(isActive ? Color.speakSidebarSelection : Color.clear)
    }

    /// Edit + Delete for a custom theme — 22pt hit targets, quiet glyphs.
    private func customActions(for theme: SpeakTheme) -> some View {
        HStack(spacing: SpeakSpacing.xs) {
            Button {
                engine.editTheme(theme)
                onEdit()
            } label: {
                Image(systemName: "pencil")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.speakMica)
            .help("Edit theme")

            Button(role: .destructive) {
                pendingDelete = theme
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.speakMica)
            .help("Delete theme")
        }
    }

    /// Full-row creation affordance — the row itself is the button, so the
    /// gesture isn't confined to a small glyph.
    private var newThemeRow: some View {
        Button {
            engine.beginDraft()
            onEdit()
        } label: {
            HStack(spacing: SpeakSpacing.md) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 15))
                    .foregroundStyle(Color.speakUIAccent)
                VStack(alignment: .leading, spacing: SpeakSpacing.xs) {
                    Text("New Theme")
                        .font(.speakBody(.base))
                        .foregroundStyle(Color.speakBone)
                    Text("Seeded from the active theme — edit it live.")
                        .font(.speakBody(.caption))
                        .foregroundStyle(Color.speakMica)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, SpeakSpacing.md)
            .padding(.vertical, SpeakSpacing.sm + 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Three dots: window canvas · accent · agent channel — the fastest
    /// possible read of a palette's character (t3code's ThemePreviewCircles).
    /// These read the THEME's own hex pairs — palette data, not chrome.
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
