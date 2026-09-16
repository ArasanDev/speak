// App/Settings/AppearanceHUDSettingsView.swift
//
// "Appearance" — appearance mode (light/dark/system) and runtime color
// themes. The recording-HUD and border-animation controls moved to their own
// dedicated "Overlay" category (OverlaySettingsView) — the overlay panel is
// a product surface in its own right, not a subsection of theme settings.

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
    let engine: ThemeEngine
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
