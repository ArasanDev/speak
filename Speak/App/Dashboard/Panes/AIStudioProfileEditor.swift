// App/Dashboard/Panes/AIStudioProfileEditor.swift
//
// The AI Studio profile editor panel — name/icon/prompt/examples, output
// options, target apps, live preview, and save/delete/reset actions.
// Split from AIStudioPaneView to stay under the file_length lint cap.

import SpeakCore
import SwiftUI

struct ProfileEditorPanel: View {
    let context: DashboardContext
    @Binding var profile: Profile?
    @Binding var previewSample: String
    @Binding var previewResult: SpeakEngine.ProfilePreviewResult?
    @Binding var isPreviewing: Bool

    var body: some View {
        guard let p = profile else { return AnyView(EmptyView()) }

        return AnyView(
            VStack(alignment: .leading, spacing: SpeakSpacing.sm) {
                Text(p.name)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.speakBone)

                VStack(alignment: .leading, spacing: SpeakSpacing.md) {
                    profileNameField(p)
                    profileIconField(p)
                    profilePromptField(p)
                    profileExamplesField(p)
                    profileFormatOptions(p)
                    profileToneOptions(p)
                    profileLengthOptions(p)
                    profileTargetApps(p)
                    profileAutoSubmit(p)

                    StudioHairline()

                    previewBox(p)
                    actionButtons(p)
                }
                .padding(SpeakSpacing.md)
                .speakCard()
            }
        )
    }

    private func profileNameField(_ p: Profile) -> some View {
        VStack(alignment: .leading, spacing: SpeakSpacing.xs) {
            Text("Name").font(.speakBody(.caption)).foregroundStyle(.speakMica)
            TextField("Profile name", text: Binding(
                get: { p.name },
                set: { newValue in updateProfile { $0.name = newValue } }
            ))
            .font(.speakMonoFace(.base))
            .textFieldStyle(.roundedBorder)
            .foregroundStyle(.speakBone)
        }
    }

    private func profileIconField(_ p: Profile) -> some View {
        VStack(alignment: .leading, spacing: SpeakSpacing.xs) {
            Text("Icon (SF Symbol)").font(.speakBody(.caption)).foregroundStyle(.speakMica)
            TextField("SF Symbol name", text: Binding(
                get: { p.icon },
                set: { newValue in updateProfile { $0.icon = newValue } }
            ))
            .font(.speakMonoFace(.base))
            .textFieldStyle(.roundedBorder)
            .foregroundStyle(.speakBone)
        }
    }

    private func profilePromptField(_ p: Profile) -> some View {
        VStack(alignment: .leading, spacing: SpeakSpacing.xs) {
            Text("System prompt").font(.speakBody(.caption)).foregroundStyle(.speakMica)
            TextEditor(text: Binding(
                get: { p.systemPrompt },
                set: { newValue in updateProfile { $0.systemPrompt = newValue } }
            ))
            .font(.speakMonoFace(.caption))
            .foregroundStyle(.speakBone)
            .scrollContentBackground(.hidden)
            .frame(minHeight: 100)
            .padding(SpeakSpacing.sm)
            .speakInset(cornerRadius: 8)
        }
    }

    private func profileExamplesField(_ p: Profile) -> some View {
        VStack(alignment: .leading, spacing: SpeakSpacing.xs) {
            Text("Few-shot examples").font(.speakBody(.caption)).foregroundStyle(.speakMica)
            Text("Spoken → written pairs that steer the model. Strongest lever for small on-device models.")
                .font(.speakBody(.caption))
                .foregroundStyle(.speakMica)

            if !p.examples.isEmpty {
                VStack(alignment: .leading, spacing: SpeakSpacing.sm) {
                    ForEach(Array(p.examples.enumerated()), id: \.offset) { idx, example in
                        exampleRow(idx, example)
                    }
                }
            }

            Button(action: { addExample() }) {
                Label("Add example", systemImage: "plus")
                    .font(.speakBody(.caption))
                    .foregroundStyle(.speakBone)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, SpeakSpacing.xs)
        }
    }

    private func exampleRow(_ idx: Int, _ example: Example) -> some View {
        VStack(alignment: .leading, spacing: SpeakSpacing.xs) {
            HStack {
                Text("Example \(idx + 1)")
                    .font(.speakBody(.caption, semibold: true))
                    .foregroundStyle(.speakMica)
                Spacer(minLength: 0)
                Button(action: { removeExample(idx) }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10))
                        .foregroundStyle(.speakMica)
                }
                .buttonStyle(.borderless)
                .help("Remove example \(idx + 1)")
            }
            HStack(spacing: SpeakSpacing.sm) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Spoken").font(.speakBody(.caption)).foregroundStyle(.speakMica)
                    TextField("Spoken input", text: Binding(
                        get: { example.spoken },
                        set: { v in updateProfile { $0.examples[idx].spoken = v } }
                    ))
                    .font(.speakMonoFace(.caption))
                    .textFieldStyle(.roundedBorder)
                    .foregroundStyle(.speakBone)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Written").font(.speakBody(.caption)).foregroundStyle(.speakMica)
                    TextField("Written output", text: Binding(
                        get: { example.written },
                        set: { v in updateProfile { $0.examples[idx].written = v } }
                    ))
                    .font(.speakMonoFace(.caption))
                    .textFieldStyle(.roundedBorder)
                    .foregroundStyle(.speakBone)
                }
            }
        }
        .padding(SpeakSpacing.xs)
        .speakInset(cornerRadius: 8)
    }

    private func addExample() {
        updateProfile { $0.examples.append(Example(spoken: "", written: "")) }
    }

    private func removeExample(_ idx: Int) {
        updateProfile { $0.examples.remove(at: idx) }
    }

    private func profileFormatOptions(_ p: Profile) -> some View {
        VStack(alignment: .leading, spacing: SpeakSpacing.xs) {
            Text("Output format").font(.speakBody(.caption)).foregroundStyle(.speakMica)
            Picker("Format", selection: Binding(
                get: { p.format },
                set: { newValue in updateProfile { $0.format = newValue } }
            )) {
                ForEach(OutputFormat.allCases, id: \.self) { fmt in
                    Text(fmt.rawValue)
                        .foregroundStyle(.speakBone)
                        .tag(fmt)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    private func profileToneOptions(_ p: Profile) -> some View {
        VStack(alignment: .leading, spacing: SpeakSpacing.xs) {
            Text("Tone").font(.speakBody(.caption)).foregroundStyle(.speakMica)
            Picker("Tone", selection: Binding(
                get: { p.tone },
                set: { newValue in updateProfile { $0.tone = newValue } }
            )) {
                ForEach(Tone.allCases, id: \.self) { tone in
                    Text(tone.rawValue)
                        .foregroundStyle(.speakBone)
                        .tag(tone)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    private func profileLengthOptions(_ p: Profile) -> some View {
        VStack(alignment: .leading, spacing: SpeakSpacing.xs) {
            Text("Length bias").font(.speakBody(.caption)).foregroundStyle(.speakMica)
            Picker("Length", selection: Binding(
                get: { p.length },
                set: { newValue in updateProfile { $0.length = newValue } }
            )) {
                ForEach(LengthBias.allCases, id: \.self) { len in
                    Text(len.rawValue)
                        .foregroundStyle(.speakBone)
                        .tag(len)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    private func profileTargetApps(_ p: Profile) -> some View {
        VStack(alignment: .leading, spacing: SpeakSpacing.xs) {
            Text("Target apps (bundle IDs or names)").font(.speakBody(.caption)).foregroundStyle(.speakMica)
            VStack(alignment: .leading, spacing: SpeakSpacing.xs) {
                ForEach(Array(p.targetApps.enumerated()), id: \.offset) { idx, app in
                    HStack(spacing: SpeakSpacing.xs) {
                        TextField("App", text: Binding(
                            get: { app },
                            set: { newValue in updateProfile { $0.targetApps[idx] = newValue } }
                        ))
                        .font(.speakMonoFace(.caption))
                        .textFieldStyle(.roundedBorder)
                        .foregroundStyle(.speakBone)

                        Button(action: { removeTargetApp(idx) }) {
                            Image(systemName: "xmark").foregroundStyle(.speakMica)
                        }
                        .buttonStyle(.borderless)
                    }
                }

                Button(action: { addTargetApp() }) {
                    Label("Add app", systemImage: "plus")
                        .font(.speakBody(.caption))
                        .foregroundStyle(.speakBone)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(SpeakSpacing.sm)
            .speakInset(cornerRadius: 8)
        }
    }

    private func profileAutoSubmit(_ p: Profile) -> some View {
        Toggle(isOn: Binding(
            get: { p.autoSubmit },
            set: { newValue in updateProfile { $0.autoSubmit = newValue } }
        )) {
            Text("Auto-submit (paste immediately after cleanup)")
                .font(.speakBody(.caption))
                .foregroundStyle(.speakBone)
        }
    }

    private func previewBox(_ p: Profile) -> some View {
        VStack(alignment: .leading, spacing: SpeakSpacing.sm) {
            Text("Live preview").font(.speakBody(.caption)).foregroundStyle(.speakMica)
            TextField("Enter sample text", text: $previewSample)
                .font(.speakMonoFace(.base))
                .textFieldStyle(.roundedBorder)
                .foregroundStyle(.speakBone)

            Button(action: { runPreview(p) }) {
                Label("Preview", systemImage: "play.fill")
                    .font(.speakBody(.caption))
                    .foregroundStyle(.speakBone)
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
                StudioNoticeStrip(
                    systemImage: "exclamationmark.triangle",
                    tint: .speakWarning,
                    message: "No cleanup model is available — enable Apple Intelligence or choose a provider in Settings › Intelligence."
                )
            case .raw:
                Text("Raw profile: output equals input (passthrough).")
                    .font(.speakBody(.caption))
                    .foregroundStyle(.speakMica)
            case .transformed(let output):
                VStack(alignment: .leading, spacing: SpeakSpacing.xs) {
                    Text("Transformed output:").font(.speakBody(.caption)).foregroundStyle(.speakMica)
                    Text(output)
                        .font(.speakMonoFace(.caption))
                        .foregroundStyle(.speakBone)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(SpeakSpacing.sm)
                        .speakInset(cornerRadius: 8)
                }
            case .failed(let detail):
                StudioNoticeStrip(
                    systemImage: "xmark.octagon",
                    tint: .speakError,
                    message: "Preview failed — \(detail)"
                )
            }
        }
        .padding(SpeakSpacing.sm)
        .speakInset(cornerRadius: 8)
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
                .font(.speakBody(.caption))
            }

            if !p.isBuiltIn {
                Button(role: .destructive, action: {
                    context.profileStore.delete(id: p.id)
                    profile = nil
                }) {
                    Label("Delete", systemImage: "trash")
                }
                .font(.speakBody(.caption))
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
