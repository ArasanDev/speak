// App/Settings/ThemeEditorSheet.swift
//
// The runtime theme editor — the analogue of t3code's `ThemeEditorPanel`:
// a draft `SpeakTheme` painted on the LIVE app while it is edited (every
// `engine.updateDraft` repaints immediately, so the window behind the sheet
// is the preview). Segmented Light/Dark control picks which half of each
// `ThemeHexPair` a `ColorPicker` writes; "Default" removes an override so the
// role falls back to the `speak` palette.
//
// Save → `commitDraft()` persists to `SettingsStore.customThemesJSON` and
// selects the theme. Cancel → `discardDraft()` restores the committed theme.

import SwiftUI

// MARK: - ThemeEditorSheet

@MainActor
struct ThemeEditorSheet: View {
    @ObservedObject var engine: ThemeEngine
    @Environment(\.dismiss) private var dismiss

    /// Which half of each role pair the pickers edit. [decision: explicit
    /// segment over "follow system" — editing the dark half while running
    /// light must be possible.]
    @State private var editingDark = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(Color.speakCardBorder.opacity(0.6))
            ScrollView {
                VStack(alignment: .leading, spacing: SpeakSpacing.lg) {
                    ForEach(editorGroups, id: \.self) { group in
                        roleGroup(group)
                    }
                }
                .padding(SpeakSpacing.md)
            }
            Divider().overlay(Color.speakCardBorder.opacity(0.6))
            footer
        }
        .frame(width: 480, height: 560)
        .background(Color.speakWindowCanvas)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: SpeakSpacing.md) {
            Text("Edit Theme")
                .font(.speakDisplay(.title))
                .foregroundStyle(Color.speakBone)

            TextField(
                "Theme name",
                text: Binding(
                    get: { engine.draft?.name ?? "" },
                    set: { engine.renameDraft($0) }
                )
            )
            .textFieldStyle(.roundedBorder)
            .frame(maxWidth: 200)

            Spacer()

            Picker("", selection: $editingDark) {
                Text("Light").tag(false)
                Text("Dark").tag(true)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 140)
        }
        .padding(SpeakSpacing.md)
    }

    // MARK: - Role groups

    private var editorGroups: [String] {
        var seen: [String] = []
        for role in ThemeColorRole.allCases where !seen.contains(role.editorGroup) {
            seen.append(role.editorGroup)
        }
        return seen
    }

    private func roleGroup(_ group: String) -> some View {
        SettingsSectionCard(title: group) {
            VStack(spacing: 0) {
                ForEach(roles(in: group), id: \.rawValue) { role in
                    if role != roles(in: group).first {
                        SettingsRowSeparator()
                    }
                    roleRow(role)
                }
            }
        }
    }

    private func roles(in group: String) -> [ThemeColorRole] {
        ThemeColorRole.allCases.filter { $0.editorGroup == group }
    }

    private func roleRow(_ role: ThemeColorRole) -> some View {
        SettingsRow(role.displayName) {
            HStack(spacing: SpeakSpacing.sm) {
                Circle()
                    .fill(pickerColor(for: role))
                    .frame(width: 14, height: 14)
                    .overlay(Circle().stroke(Color.speakCardBorder, lineWidth: 1))

                if isOverridden(role) {
                    Button {
                        engine.clearDraftRole(role)
                    } label: {
                        Image(systemName: "arrow.uturn.backward.circle")
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.speakMica)
                    .help("Reset to the Speak default")
                }
                ColorPicker(
                    "",
                    selection: Binding(
                        get: { pickerColor(for: role) },
                        set: { setPickerColor($0, for: role) }
                    ),
                    supportsOpacity: false
                )
                .labelsHidden()
            }
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Text("Changes paint the app live as you edit.")
                .font(.speakBody(.caption))
                .foregroundStyle(Color.speakMica)
            Spacer()
            Button("Cancel") {
                engine.discardDraft()
                dismiss()
            }
            .keyboardShortcut(.cancelAction)
            Button("Save Theme") {
                engine.commitDraft()
                dismiss()
            }
            .keyboardShortcut(.defaultAction)
            .disabled(engine.draft?.name.trimmingCharacters(in: .whitespaces).isEmpty ?? true)
        }
        .padding(SpeakSpacing.md)
    }

    // MARK: - Draft access

    private func isOverridden(_ role: ThemeColorRole) -> Bool {
        engine.draft?.colors[role.rawValue] != nil
    }

    /// Current stored value for the edited half — falls back to the draft's
    /// merged pair (speak default) so the well always shows a real color.
    private func pickerColor(for role: ThemeColorRole) -> Color {
        let pair = engine.draft?.colors[role.rawValue]
            ?? SpeakTheme.speak.colors[role.rawValue]
        let hex = editingDark ? pair?.dark : pair?.light
        guard let hex, let ns = NSColor(speakHex: hex) else { return .accentColor }
        return Color(nsColor: ns)
    }

    private func setPickerColor(_ color: Color, for role: ThemeColorRole) {
        guard let hex = color.speakHexString() else { return }
        guard let existing = engine.draft?.colors[role.rawValue]
            ?? SpeakTheme.speak.colors[role.rawValue] else {
            // Role with no default anywhere (accent): seed BOTH halves with
            // the picked color so the unedited half isn't a junk fallback.
            engine.updateDraft(role, light: hex, dark: hex)
            return
        }
        if editingDark {
            engine.updateDraft(role, light: existing.light, dark: hex)
        } else {
            engine.updateDraft(role, light: hex, dark: existing.dark)
        }
    }
}
