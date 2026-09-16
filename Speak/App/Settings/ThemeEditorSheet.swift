// App/Settings/ThemeEditorSheet.swift
//
// The runtime theme editor — the analogue of t3code's `ThemeEditorPanel`:
// a draft `SpeakTheme` painted on the LIVE app while it is edited (every
// `engine.updateDraft` repaints immediately, so the window behind the sheet
// is the preview).
//
// Each role row edits BOTH halves of its `ThemeHexPair` at once — a light
// well + hex field and a dark well + hex field — so the whole palette is
// scannable without flipping a mode switch (t3code shows both columns too).
// A role with no override renders ghosted and reads "Inheriting the Speak
// default"; clearing it (`clearDraftRole`) returns it to that state.
//
// Hex fields validate on every keystroke: a parseable value (#RGB, #RRGGBB,
// #RRGGBBAA) is normalized and written to the draft immediately; an invalid
// value never reaches the draft and is flagged in place — never silently
// dropped.
//
// Save → `commitDraft()` persists to `SettingsStore.customThemesJSON` and
// selects the theme. Cancel → `discardDraft()` restores the committed theme.
// Delete (existing customs only) → `deleteCustomTheme(id:)` after confirm.

import SwiftUI

// MARK: - ThemeEditorSheet

@MainActor
struct ThemeEditorSheet: View {
    let engine: ThemeEngine
    @Environment(\.dismiss) private var dismiss

    @State private var confirmDelete = false

    /// True when the draft edits an existing custom theme (`editTheme`);
    /// false for a freshly seeded draft (`beginDraft` mints a new id that
    /// isn't in `themes` yet). Drives the title and the Delete affordance.
    private var editingExisting: Bool {
        guard let id = engine.draft?.id else { return false }
        return engine.themes.contains { $0.id == id }
    }

    private var nameIsBlank: Bool {
        engine.draft?.name.trimmingCharacters(in: .whitespaces).isEmpty ?? true
    }

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
        .frame(width: 500, height: 560)
        .background(Color.speakWindowCanvas)
        .onAppear {
            // The sheet is always presented after beginDraft/editTheme; this
            // fallback keeps a stray presentation usable instead of empty.
            if engine.draft == nil { engine.beginDraft() }
        }
        .confirmationDialog(
            "Delete this theme?",
            isPresented: $confirmDelete,
            titleVisibility: .visible
        ) {
            Button("Delete Theme", role: .destructive) {
                if let id = engine.draft?.id { engine.deleteCustomTheme(id: id) }
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("“\(engine.draft?.name ?? "")” will be removed permanently.")
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: SpeakSpacing.md) {
            Text(editingExisting ? "Edit Theme" : "New Theme")
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
                    RoleEditorRow(role: role, engine: engine)
                }
            }
        }
    }

    private func roles(in group: String) -> [ThemeColorRole] {
        ThemeColorRole.allCases.filter { $0.editorGroup == group }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: SpeakSpacing.md) {
            if editingExisting {
                Button("Delete…", role: .destructive) {
                    confirmDelete = true
                }
            }
            Text("Changes paint the app live as you edit.")
                .font(.speakBody(.caption))
                .foregroundStyle(Color.speakMica)
            Spacer()
            Button("Cancel") {
                engine.discardDraft()
                dismiss()
            }
            .keyboardShortcut(.cancelAction)
            Button(editingExisting ? "Save" : "Create Theme") {
                engine.commitDraft()
                dismiss()
            }
            .keyboardShortcut(.defaultAction)
            .disabled(nameIsBlank)
        }
        .padding(SpeakSpacing.md)
    }
}

// MARK: - RoleEditorRow

/// One `ThemeColorRole`: name on the left; on the right a light pair and a
/// dark pair — system color well + hex text field each. Unset roles show
/// the inherited `speak` value ghosted; picking or typing creates an
/// override, and the reset affordance returns to inheritance.
@MainActor
private struct RoleEditorRow: View {
    let role: ThemeColorRole
    let engine: ThemeEngine

    /// Field contents are local until they parse — the draft only ever sees
    /// canonical "#RRGGBB" values, so an invalid keystroke can't corrupt it.
    @State private var lightText = ""
    @State private var darkText = ""
    @State private var lightInvalid = false
    @State private var darkInvalid = false

    /// The draft's explicit value, if this role is overridden.
    private var overridePair: ThemeHexPair? {
        engine.draft?.colors[role.rawValue]
    }

    /// Override else the `speak` merge base — what the role resolves to now.
    /// Nil only for `accent` left unset (system accent color).
    private var effectivePair: ThemeHexPair? {
        overridePair ?? SpeakTheme.speak.colors[role.rawValue]
    }

    private var isOverridden: Bool { overridePair != nil }

    var body: some View {
        SettingsRow(
            role.displayName,
            description: isOverridden ? nil : "Inheriting the Speak default"
        ) {
            HStack(spacing: SpeakSpacing.sm) {
                VStack(alignment: .leading, spacing: SpeakSpacing.xs) {
                    pairEditor(dark: false)
                    pairEditor(dark: true)
                    if lightInvalid || darkInvalid {
                        Text("Invalid hex — use #RGB, #RRGGBB or #RRGGBBAA.")
                            .font(.speakBody(.caption))
                            .foregroundStyle(Color.speakError)
                    }
                }
                if isOverridden {
                    Button {
                        engine.clearDraftRole(role)
                    } label: {
                        Image(systemName: "arrow.uturn.backward")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.speakMica)
                    .help("Reset \(role.displayName) to the Speak default")
                }
            }
        }
        .onAppear {
            lightText = effectivePair?.light ?? ""
            darkText = effectivePair?.dark ?? ""
        }
        // External writes (color well, Reset, another row's draft mutation)
        // resync the fields — except when the field already holds the same
        // canonical value, so the user's mid-edit text is never clobbered.
        .onChange(of: effectivePair?.light) { _, new in
            if Self.canonicalHex(lightText) != new.flatMap(Self.canonicalHex) {
                lightText = new ?? ""
                lightInvalid = false
            }
        }
        .onChange(of: effectivePair?.dark) { _, new in
            if Self.canonicalHex(darkText) != new.flatMap(Self.canonicalHex) {
                darkText = new ?? ""
                darkInvalid = false
            }
        }
    }

    // MARK: - One half of the pair

    private func pairEditor(dark: Bool) -> some View {
        let invalid = dark ? darkInvalid : lightInvalid
        return HStack(spacing: SpeakSpacing.xs) {
            Image(systemName: dark ? "moon.fill" : "sun.max.fill")
                .font(.system(size: 9))
                .foregroundStyle(Color.speakMica)
                .frame(width: 12)

            ColorPicker(
                "",
                selection: Binding(
                    get: { swatchColor(dark: dark) },
                    set: { applyPickedColor($0, dark: dark) }
                ),
                supportsOpacity: false
            )
            .labelsHidden()
            .fixedSize()
            .opacity(isOverridden ? 1 : 0.55)
            .help("\(role.displayName) — \(dark ? "dark" : "light") appearance")

            TextField(
                effectiveHex(dark: dark) ?? "System",
                text: dark ? $darkText : $lightText
            )
            .font(.speakMonoFace(.caption))
            .foregroundStyle(invalid ? Color.speakError : (isOverridden ? Color.speakBone : Color.speakMica))
            .textFieldStyle(.plain)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .frame(width: 76)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(Color.speakWindowCanvas)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .stroke(invalid ? Color.speakError : Color.clear, lineWidth: 1)
            )
            .help("Hex color — #RGB, #RRGGBB or #RRGGBBAA")
            .onChange(of: dark ? darkText : lightText) { _, new in
                applyText(new, dark: dark)
            }
        }
    }

    // MARK: - Values

    private func effectiveHex(dark: Bool) -> String? {
        dark ? effectivePair?.dark : effectivePair?.light
    }

    /// Well color for the edited half — falls back to the merged pair so the
    /// swatch always shows the real resolved color, even when unset.
    private func swatchColor(dark: Bool) -> Color {
        guard let hex = effectiveHex(dark: dark),
              let ns = NSColor(speakHex: hex) else { return .accentColor }
        return Color(nsColor: ns)
    }

    /// Any parseable input normalizes to "#RRGGBB" (theme tokens are opaque —
    /// alpha is dropped, matching `Color.speakHexString`).
    static func canonicalHex(_ raw: String) -> String? {
        guard let ns = NSColor(speakHex: raw) else { return nil }
        return Color(nsColor: ns).speakHexString()
    }

    // MARK: - Writes

    private func applyPickedColor(_ color: Color, dark: Bool) {
        guard let hex = color.speakHexString() else { return }
        writePair(light: dark ? nil : hex, dark: dark ? hex : nil)
    }

    private func applyText(_ raw: String, dark: Bool) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            setInvalid(false, dark: dark)
            return
        }
        guard let canonical = Self.canonicalHex(trimmed) else {
            setInvalid(true, dark: dark)
            return
        }
        setInvalid(false, dark: dark)
        writePair(light: dark ? nil : canonical, dark: dark ? canonical : nil)
    }

    /// Write one half, preserving the other — seeding BOTH halves with the
    /// new value when the role has no default anywhere (unset `accent`), so
    /// the unedited half isn't a junk fallback. The guard makes an empty
    /// write unreachable rather than silently storing "".
    private func writePair(light: String?, dark: String?) {
        let existing = effectivePair
        guard let newLight = light ?? existing?.light ?? dark,
              let newDark = dark ?? existing?.dark ?? light else { return }
        engine.updateDraft(role, light: newLight, dark: newDark)
    }

    private func setInvalid(_ invalid: Bool, dark: Bool) {
        if dark { darkInvalid = invalid } else { lightInvalid = invalid }
    }
}
