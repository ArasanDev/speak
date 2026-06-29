// App/Dashboard/Panes/AIStudioPaneView.swift
//
// The AI Studio pane — the visible UI face of the Profile Engine (PE). Displays:
//   1. AI cleanup toggle (on/off) — bind to settingsStore.cleanupEnabled
//   2. Default profile picker — selects which profile runs on unmapped apps
//   3. Editable profile list — built-in first, then user profiles
//   4. Per-profile editor — systemPrompt (main field), format/tone/length, targetApps, autoSubmit
//   5. Live-test box — sample text + "Preview" button that calls SpeakEngine.preview()
//   6. Actions — Reset/Delete/New
//
// WHY THE HONESTY GUARDRAIL: a live-test result MUST render every preview case explicitly.
// Never echo unchanged input as a transform — that's a lie and breaks user trust in the
// AI pass. Each case (.unavailable, .raw, .transformed, .failed) has its own UI.

import SpeakCore
import SwiftUI

// MARK: - AIStudioPaneView

@MainActor
struct AIStudioPaneView: View {
    let context: DashboardContext

    @State private var selectedProfileID: UUID?
    @State private var editingProfile: Profile?
    @State private var previewSample: String = ""
    @State private var previewResult: SpeakEngine.ProfilePreviewResult?
    @State private var isPreviewing: Bool = false

    init(context: DashboardContext) {
        self.context = context
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PaneHeader(
                title: "AI Studio",
                subtitle: "Configure the Profile Engine — choose how speak rewrites your words, per app."
            )

            ScrollView {
                VStack(alignment: .leading, spacing: SpeakSpacing.lg) {
                    AICleanupToggle(settingsStore: context.settingsStore)
                    Divider()
                    DefaultProfileSection(context: context)
                    Divider()

                    HStack(alignment: .top, spacing: SpeakSpacing.lg) {
                        ProfileListPanel(
                            context: context,
                            selectedID: $selectedProfileID,
                            editingProfile: $editingProfile
                        )
                        .frame(maxWidth: 240)

                        if editingProfile != nil {
                            ProfileEditorPanel(
                                context: context,
                                profile: $editingProfile,
                                previewSample: $previewSample,
                                previewResult: $previewResult,
                                isPreviewing: $isPreviewing
                            )
                            .frame(maxWidth: .infinity)
                        } else {
                            emptyEditorPlaceholder
                                .frame(maxWidth: .infinity)
                        }
                    }
                }
                .padding(SpeakSpacing.lg)
            }

            Spacer(minLength: 0)
        }
    }

    private var emptyEditorPlaceholder: some View {
        VStack(spacing: SpeakSpacing.md) {
            Image(systemName: "brain.head.profile")
                .font(.system(size: 34))
                .foregroundStyle(.tertiary)
            Text("Select a profile to edit")
                .font(.speakMonoCaption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.speakSurface))
    }
}

// MARK: - AICleanupToggle

private struct AICleanupToggle: View {
    let settingsStore: SettingsStore

    var body: some View {
        VStack(alignment: .leading, spacing: SpeakSpacing.sm) {
            Toggle("AI cleanup", isOn: Binding(
                get: { settingsStore.cleanupEnabled },
                set: { settingsStore.cleanupEnabled = $0 }
            ))
            .font(.speakMonoBody)

            Text("Off = raw transcript passes through untouched.")
                .font(.speakMonoCaption)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - DefaultProfileSection

private struct DefaultProfileSection: View {
    let context: DashboardContext

    var body: some View {
        VStack(alignment: .leading, spacing: SpeakSpacing.sm) {
            Text("Default profile")
                .font(.speakMonoBody)

            Picker("Default profile", selection: Binding(
                get: { context.profileStore.defaultProfileID },
                set: { context.profileStore.defaultProfileID = $0 }
            )) {
                ForEach(context.profileStore.profiles, id: \.id) { profile in
                    Label(profile.name, systemImage: profile.icon).tag(profile.id)
                }
            }
            .pickerStyle(.menu)

            Text("Sets which profile governs the default path. Today the everyday writing "
                 + "style is still set in the Style pane — full default-profile wiring is the "
                 + "next step. App-specific profiles (below) are active now.")
                .font(.speakMonoCaption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - ProfileListPanel

private struct ProfileListPanel: View {
    let context: DashboardContext
    @Binding var selectedID: UUID?
    @Binding var editingProfile: Profile?

    var body: some View {
        VStack(alignment: .leading, spacing: SpeakSpacing.sm) {
            Text("Profiles")
                .font(.speakMonoBody)

            VStack(alignment: .leading, spacing: SpeakSpacing.xs) {
                ForEach(context.profileStore.profiles, id: \.id) { profile in
                    profileRow(profile)
                }

                Button(action: createNew) {
                    Label("New profile", systemImage: "plus")
                        .font(.speakMonoCaption)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, SpeakSpacing.sm)
            }
            .padding(SpeakSpacing.sm)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.speakSurface))
        }
    }

    private func profileRow(_ profile: Profile) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: { selectProfile(profile) }) {
                HStack(spacing: SpeakSpacing.sm) {
                    Image(systemName: profile.icon).font(.system(size: 12))
                    Text(profile.name).font(.speakMonoCaption)
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(SpeakSpacing.xs)
                .foregroundStyle(selectedID == profile.id ? Color.speakAccent : .primary)
                .background(selectedID == profile.id ? Color.speakSurface : Color.clear)
                .cornerRadius(4)
            }

            if !profile.targetApps.isEmpty {
                Text("Active in: " + profile.targetApps.joined(separator: ", "))
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .padding(.leading, SpeakSpacing.xs)
                    .padding(.top, SpeakSpacing.xs)
            } else if profile.isBuiltIn {
                Text("Foundational")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                    .padding(.leading, SpeakSpacing.xs)
                    .padding(.top, SpeakSpacing.xs)
            }
        }
    }

    private func selectProfile(_ profile: Profile) {
        selectedID = profile.id
        editingProfile = profile
    }

    private func createNew() {
        let newProfile = Profile(
            id: UUID(),
            name: "New Profile",
            icon: "sparkles",
            isBuiltIn: false,
            systemPrompt: "",
            examples: [],
            format: .asIs,
            tone: .neutral,
            length: .preserve,
            contextInputs: [],
            targetApps: [],
            autoSubmit: false,
            model: .foundationModels
        )
        context.profileStore.save(newProfile)
        selectedID = newProfile.id
        editingProfile = newProfile
    }
}

// MARK: - ProfileEditorPanel

private struct ProfileEditorPanel: View {
    let context: DashboardContext
    @Binding var profile: Profile?
    @Binding var previewSample: String
    @Binding var previewResult: SpeakEngine.ProfilePreviewResult?
    @Binding var isPreviewing: Bool

    var body: some View {
        guard let p = profile else { return AnyView(EmptyView()) }

        return AnyView(
            VStack(alignment: .leading, spacing: SpeakSpacing.md) {
                profileNameField(p)
                profileIconField(p)
                profilePromptField(p)
                profileFormatOptions(p)
                profileToneOptions(p)
                profileLengthOptions(p)
                profileTargetApps(p)
                profileAutoSubmit(p)

                Divider()

                previewBox(p)
                actionButtons(p)
            }
            .padding(SpeakSpacing.md)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.speakSurface))
        )
    }

    private func profileNameField(_ p: Profile) -> some View {
        VStack(alignment: .leading, spacing: SpeakSpacing.xs) {
            Text("Name").font(.speakMonoCaption).foregroundStyle(.secondary)
            TextField("Profile name", text: Binding(
                get: { p.name },
                set: { newValue in updateProfile { $0.name = newValue } }
            ))
            .font(.speakMonoBody)
            .textFieldStyle(.roundedBorder)
        }
    }

    private func profileIconField(_ p: Profile) -> some View {
        VStack(alignment: .leading, spacing: SpeakSpacing.xs) {
            Text("Icon (SF Symbol)").font(.speakMonoCaption).foregroundStyle(.secondary)
            TextField("SF Symbol name", text: Binding(
                get: { p.icon },
                set: { newValue in updateProfile { $0.icon = newValue } }
            ))
            .font(.speakMonoBody)
            .textFieldStyle(.roundedBorder)
        }
    }

    private func profilePromptField(_ p: Profile) -> some View {
        VStack(alignment: .leading, spacing: SpeakSpacing.xs) {
            Text("System prompt").font(.speakMonoCaption).foregroundStyle(.secondary)
            TextEditor(text: Binding(
                get: { p.systemPrompt },
                set: { newValue in updateProfile { $0.systemPrompt = newValue } }
            ))
            .font(.speakMonoBody)
            .frame(minHeight: 100)
            .border(Color.gray.opacity(0.3), width: 1)
            .cornerRadius(4)
        }
    }

    private func profileFormatOptions(_ p: Profile) -> some View {
        VStack(alignment: .leading, spacing: SpeakSpacing.xs) {
            Text("Output format").font(.speakMonoCaption).foregroundStyle(.secondary)
            Picker("Format", selection: Binding(
                get: { p.format },
                set: { newValue in updateProfile { $0.format = newValue } }
            )) {
                ForEach(OutputFormat.allCases, id: \.self) { fmt in
                    Text(fmt.rawValue).tag(fmt)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    private func profileToneOptions(_ p: Profile) -> some View {
        VStack(alignment: .leading, spacing: SpeakSpacing.xs) {
            Text("Tone").font(.speakMonoCaption).foregroundStyle(.secondary)
            Picker("Tone", selection: Binding(
                get: { p.tone },
                set: { newValue in updateProfile { $0.tone = newValue } }
            )) {
                ForEach(Tone.allCases, id: \.self) { tone in
                    Text(tone.rawValue).tag(tone)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    private func profileLengthOptions(_ p: Profile) -> some View {
        VStack(alignment: .leading, spacing: SpeakSpacing.xs) {
            Text("Length bias").font(.speakMonoCaption).foregroundStyle(.secondary)
            Picker("Length", selection: Binding(
                get: { p.length },
                set: { newValue in updateProfile { $0.length = newValue } }
            )) {
                ForEach(LengthBias.allCases, id: \.self) { len in
                    Text(len.rawValue).tag(len)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    private func profileTargetApps(_ p: Profile) -> some View {
        VStack(alignment: .leading, spacing: SpeakSpacing.xs) {
            Text("Target apps (bundle IDs or names)").font(.speakMonoCaption).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: SpeakSpacing.xs) {
                ForEach(Array(p.targetApps.enumerated()), id: \.offset) { idx, app in
                    HStack(spacing: SpeakSpacing.xs) {
                        TextField("App", text: Binding(
                            get: { app },
                            set: { newValue in updateProfile { $0.targetApps[idx] = newValue } }
                        ))
                        .font(.speakMonoCaption)
                        .textFieldStyle(.roundedBorder)

                        Button(action: { removeTargetApp(idx) }) {
                            Image(systemName: "xmark").foregroundStyle(.secondary)
                        }
                        .buttonStyle(.borderless)
                    }
                }

                Button(action: { addTargetApp() }) {
                    Label("Add app", systemImage: "plus").font(.speakMonoCaption)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(SpeakSpacing.sm)
            .background(RoundedRectangle(cornerRadius: 4).fill(Color.speakSurface))
        }
    }

    private func profileAutoSubmit(_ p: Profile) -> some View {
        Toggle("Auto-submit (paste immediately after cleanup)", isOn: Binding(
            get: { p.autoSubmit },
            set: { newValue in updateProfile { $0.autoSubmit = newValue } }
        ))
        .font(.speakMonoCaption)
    }

    private func previewBox(_ p: Profile) -> some View {
        VStack(alignment: .leading, spacing: SpeakSpacing.sm) {
            Text("Live preview").font(.speakMonoCaption).foregroundStyle(.secondary)
            TextField("Enter sample text", text: $previewSample)
                .font(.speakMonoBody)
                .textFieldStyle(.roundedBorder)

            Button(action: { runPreview(p) }) {
                Label("Preview", systemImage: "play.fill").font(.speakMonoCaption)
            }
            .disabled(previewSample.isEmpty || isPreviewing)

            if let result = previewResult {
                previewResultBox(result)
            }
        }
    }

    private func previewResultBox(_ result: SpeakEngine.ProfilePreviewResult) -> some View {
        VStack(alignment: .leading, spacing: SpeakSpacing.xs) {
            switch result {
            case .unavailable:
                Text("Foundation Models unavailable — enable Apple Intelligence.")
                    .font(.speakMonoCaption)
                    .foregroundStyle(.secondary)
            case .raw:
                Text("Raw profile: output equals input (passthrough).")
                    .font(.speakMonoCaption)
                    .foregroundStyle(.secondary)
            case .transformed(let output):
                VStack(alignment: .leading, spacing: SpeakSpacing.xs) {
                    Text("Transformed output:").font(.speakMonoCaption).foregroundStyle(.secondary)
                    Text(output)
                        .font(.speakMonoBody)
                        .textSelection(.enabled)
                        .padding(SpeakSpacing.sm)
                        .background(Color.black.opacity(0.05))
                        .cornerRadius(4)
                    Text("[unverified on this Mac]").font(.system(size: 9)).foregroundStyle(.tertiary)
                }
            case .failed:
                Text("Preview failed. Check the system log for details.")
                    .font(.speakMonoCaption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(SpeakSpacing.sm)
        .background(Color.speakSurface)
        .cornerRadius(4)
    }

    private func actionButtons(_ p: Profile) -> some View {
        HStack(spacing: SpeakSpacing.md) {
            if p.isBuiltIn && context.profileStore.isCustomized(id: p.id) {
                Button("Reset to default") {
                    context.profileStore.resetToDefault(id: p.id)
                    if let reset = context.profileStore.profile(id: p.id) {
                        profile = reset
                    }
                }
                .font(.speakMonoCaption)
            }

            if !p.isBuiltIn {
                Button(role: .destructive, action: {
                    context.profileStore.delete(id: p.id)
                    profile = nil
                }) {
                    Label("Delete", systemImage: "trash")
                }
                .font(.speakMonoCaption)
            }

            Spacer(minLength: 0)
        }
    }

    private func updateProfile(_ mutation: (inout Profile) -> Void) {
        guard var p = profile else { return }
        mutation(&p)
        profile = p
        context.profileStore.save(p)
    }

    private func removeTargetApp(_ idx: Int) {
        updateProfile { $0.targetApps.remove(at: idx) }
    }

    private func addTargetApp() {
        updateProfile { $0.targetApps.append("") }
    }

    private func runPreview(_ p: Profile) {
        guard let engine = context.speakEngine else { return }
        isPreviewing = true
        Task {
            let result = await engine.preview(profile: p, sample: previewSample)
            previewResult = result
            isPreviewing = false
        }
    }
}

// MARK: - Preview

#if DEBUG
#Preview("AI Studio") {
    AIStudioPaneView(context: DashboardContext(
        settingsStore: SettingsStore(),
        historyStore: PreviewNullHistoryStore(),
        hotkeyCombo: ["Fn", "Fn"],
        profileStore: ProfileStore()
    ))
    .frame(width: 900, height: 600)
}
#endif
