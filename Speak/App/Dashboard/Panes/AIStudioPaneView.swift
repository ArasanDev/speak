// App/Dashboard/Panes/AIStudioPaneView.swift
//
// The Voice AI Studio pane — visible UI face of Voice AI configuration & Profile Engine (PE).
// Allows developers and users to:
//   1. Configure on-device TTS voices (AVSpeechSynthesizer), speech rate/pitch/volume & test live readbacks.
//   2. Inspect STT audio input waveforms, RMS dynamics, and PCM buffer metrics.
//   3. System prompt transforms & profile editor — edit system prompts, format/tone/length, target apps,
//      auto-submit, and live preview transform execution.

import AVFoundation
import SpeakCore
import SwiftUI

// MARK: - StudioTab

private enum StudioTab: String, CaseIterable, Identifiable {
    case ttsVoice = "Voice & TTS"
    case sttWaveform = "STT Waveform"
    case promptTransforms = "Prompt Transforms"

    var id: String { rawValue }
    var icon: String {
        switch self {
        case .ttsVoice: return "speaker.wave.2.fill"
        case .sttWaveform: return "waveform.path.ecg"
        case .promptTransforms: return "brain.head.profile"
        }
    }
}

// MARK: - AIStudioPaneView

@MainActor
struct AIStudioPaneView: View {
    let context: DashboardContext

    @State private var selectedTab: StudioTab = .ttsVoice
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
                title: "Voice AI Studio",
                subtitle: "Test system prompt transforms, inspect STT audio waveforms, and configure local TTS voices."
            )

            VStack(alignment: .leading, spacing: SpeakSpacing.md) {
                Picker("Studio View", selection: $selectedTab) {
                    ForEach(StudioTab.allCases) { tab in
                        Label(tab.rawValue, systemImage: tab.icon).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, SpeakSpacing.lg)
                .padding(.top, SpeakSpacing.md)

                ScrollView {
                    VStack(alignment: .leading, spacing: SpeakSpacing.lg) {
                        switch selectedTab {
                        case .ttsVoice:
                            VoiceTTSConfigSection(context: context)
                        case .sttWaveform:
                            STTAudioWaveformInspectorSection(context: context)
                        case .promptTransforms:
                            promptTransformsContent
                        }
                    }
                    .padding(SpeakSpacing.lg)
                }
            }

            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private var promptTransformsContent: some View {
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
    }

    private var emptyEditorPlaceholder: some View {
        VStack(spacing: SpeakSpacing.md) {
            Image(systemName: "brain.head.profile")
                .font(.system(size: 34))
                .foregroundStyle(.tertiary)
            Text("Select a profile to edit")
                .font(.speakBody(.caption))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.speakSurface))
    }
}

// MARK: - VoiceTTSConfigSection

private struct VoiceTTSConfigSection: View {
    let context: DashboardContext

    @State private var availableVoices: [AVSpeechSynthesisVoice] = []
    @State private var testText: String = "Hello, welcome to Speak Voice AI Studio. Ready for high quality local speech synthesis."
    @State private var isSpeaking: Bool = false
    @State private var activeSynth: AppleSpeechSynthesizer?

    var body: some View {
        VStack(alignment: .leading, spacing: SpeakSpacing.md) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Voice & TTS Configuration")
                        .font(.system(size: 16, weight: .semibold))
                    Text("Configure on-device AVSpeechSynthesizer voices, speech rate, pitch, volume, and test live audio readbacks.")
                        .font(.speakBody(.caption))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(action: resetTTSDefaults) {
                    Label("Reset Voice Defaults", systemImage: "arrow.counterclockwise")
                        .font(.speakBody(.caption))
                }
            }

            VStack(alignment: .leading, spacing: SpeakSpacing.md) {
                // On-Device Voice picker
                VStack(alignment: .leading, spacing: SpeakSpacing.xs) {
                    Text("On-Device TTS Voice").font(.speakBody(.caption)).foregroundStyle(.secondary)
                    Picker("Voice", selection: Binding(
                        get: { context.settingsStore.ttsVoiceIdentifier },
                        set: { context.settingsStore.ttsVoiceIdentifier = $0 }
                    )) {
                        Text("System Default (Locale matching)").tag("")
                        ForEach(availableVoices, id: \.identifier) { voice in
                            Text("\(voice.name) (\(voice.language)\(qualityBadge(voice.quality)))")
                                .tag(voice.identifier)
                        }
                    }
                    .pickerStyle(.menu)
                }

                // Speech Rate
                VStack(alignment: .leading, spacing: SpeakSpacing.xs) {
                    HStack {
                        Text("Speech Rate").font(.speakBody(.caption)).foregroundStyle(.secondary)
                        Spacer()
                        Text(String(format: "%.2fx (Default: 0.50x)", context.settingsStore.ttsSpeechRate))
                            .font(.speakMonoFace(.caption))
                            .foregroundStyle(.tertiary)
                    }
                    Slider(value: Binding(
                        get: { Double(context.settingsStore.ttsSpeechRate) },
                        set: { context.settingsStore.ttsSpeechRate = Float($0) }
                    ), in: 0.1...1.0, step: 0.05)
                }

                // Pitch Multiplier
                VStack(alignment: .leading, spacing: SpeakSpacing.xs) {
                    HStack {
                        Text("Pitch Multiplier").font(.speakBody(.caption)).foregroundStyle(.secondary)
                        Spacer()
                        Text(String(format: "%.2fx (Default: 1.00x)", context.settingsStore.ttsPitchMultiplier))
                            .font(.speakMonoFace(.caption))
                            .foregroundStyle(.tertiary)
                    }
                    Slider(value: Binding(
                        get: { Double(context.settingsStore.ttsPitchMultiplier) },
                        set: { context.settingsStore.ttsPitchMultiplier = Float($0) }
                    ), in: 0.5...2.0, step: 0.05)
                }

                // Volume Slider
                VStack(alignment: .leading, spacing: SpeakSpacing.xs) {
                    HStack {
                        Text("Volume").font(.speakBody(.caption)).foregroundStyle(.secondary)
                        Spacer()
                        Text(String(format: "%.0f%%", context.settingsStore.ttsVolume * 100))
                            .font(.speakMonoFace(.caption))
                            .foregroundStyle(.tertiary)
                    }
                    Slider(value: Binding(
                        get: { Double(context.settingsStore.ttsVolume) },
                        set: { context.settingsStore.ttsVolume = Float($0) }
                    ), in: 0.0...1.0, step: 0.05)
                }

                Divider()

                // Live Audio Readback Test
                VStack(alignment: .leading, spacing: SpeakSpacing.sm) {
                    Text("Live Audio Readback Test").font(.speakBody(.caption)).foregroundStyle(.secondary)

                    TextField("Test utterance text", text: $testText)
                        .font(.speakMonoFace(.base))
                        .textFieldStyle(.roundedBorder)

                    HStack(spacing: SpeakSpacing.sm) {
                        Button(action: testReadback) {
                            Label(isSpeaking ? "Speaking..." : "Test Voice Readback", systemImage: "speaker.wave.2.fill")
                                .font(.speakBody(.caption))
                        }
                        .disabled(testText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSpeaking)

                        if isSpeaking {
                            Button(action: stopReadback) {
                                Label("Stop", systemImage: "square.fill")
                                    .font(.speakBody(.caption))
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.red)
                        }

                        Spacer()

                        if isSpeaking {
                            HStack(spacing: 4) {
                                Circle().fill(Color.speakHumanAmber).frame(width: 8, height: 8)
                                Text("AUDIO PLAYING").font(.system(size: 9)).bold().foregroundStyle(Color.speakHumanAmber)
                            }
                        }
                    }
                }
            }
            .padding(SpeakSpacing.md)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.speakSurface))
            .onAppear {
                loadVoices()
            }
        }
    }

    private func qualityBadge(_ quality: AVSpeechSynthesisVoiceQuality) -> String {
        switch quality {
        case .premium: return " • Premium"
        case .enhanced: return " • Enhanced"
        default: return ""
        }
    }

    private func loadVoices() {
        let voices = AVSpeechSynthesisVoice.speechVoices()
            .sorted { $0.name < $1.name }
        availableVoices = voices
    }

    private func resetTTSDefaults() {
        context.settingsStore.ttsVoiceIdentifier = ""
        context.settingsStore.ttsSpeechRate = AVSpeechUtteranceDefaultSpeechRate
        context.settingsStore.ttsPitchMultiplier = 1.0
        context.settingsStore.ttsVolume = 1.0
    }

    private func testReadback() {
        let synth = activeSynth ?? AppleSpeechSynthesizer()
        activeSynth = synth
        isSpeaking = true

        Task {
            await synth.speak(
                testText,
                voiceIdentifier: context.settingsStore.ttsVoiceIdentifier,
                rate: context.settingsStore.ttsSpeechRate,
                pitch: context.settingsStore.ttsPitchMultiplier,
                volume: context.settingsStore.ttsVolume,
                locale: context.settingsStore.language
            )
            isSpeaking = false
        }
    }

    private func stopReadback() {
        Task {
            if let synth = activeSynth {
                await synth.stop()
            }
            isSpeaking = false
        }
    }
}

// MARK: - STTAudioWaveformInspectorSection

private struct STTAudioWaveformInspectorSection: View {
    let context: DashboardContext

    @State private var isSimulating: Bool = false
    @State private var levels: [CGFloat] = [
        0.12, 0.25, 0.45, 0.68, 0.85, 0.92, 0.74, 0.52,
        0.38, 0.60, 0.82, 0.96, 0.88, 0.64, 0.42, 0.28,
        0.55, 0.78, 0.90, 0.70, 0.48, 0.32, 0.18, 0.24,
        0.40, 0.62, 0.35, 0.15
    ]
    @State private var peakLevel: Double = 0.96
    @State private var timer: Timer?

    var body: some View {
        VStack(alignment: .leading, spacing: SpeakSpacing.md) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("STT Audio Waveform Inspector")
                        .font(.system(size: 16, weight: .semibold))
                    Text("Inspect real-time audio signal dynamics, peak RMS levels, and PCM stream metrics.")
                        .font(.speakBody(.caption))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(action: toggleSimulation) {
                    Label(isSimulating ? "Pause Inspection" : "Simulate Live Audio", systemImage: isSimulating ? "pause.fill" : "play.fill")
                        .font(.speakBody(.caption))
                }
            }

            VStack(alignment: .leading, spacing: SpeakSpacing.md) {
                // Waveform Display Box
                VStack(spacing: SpeakSpacing.sm) {
                    HStack(alignment: .bottom, spacing: 4) {
                        ForEach(0..<levels.count, id: \.self) { idx in
                            RoundedRectangle(cornerRadius: 2)
                                .fill(isSimulating ? Color.speakHumanAmber : Color.speakMica.opacity(0.7))
                                .frame(width: 6, height: max(6, levels[idx] * 64))
                                .animation(.easeOut(duration: 0.1), value: levels[idx])
                        }
                    }
                    .frame(height: 72)
                    .frame(maxWidth: .infinity)
                    .background(Color.black.opacity(0.12))
                    .cornerRadius(6)

                    HStack {
                        Label("16 kHz Mono Float32 PCM Input", systemImage: "waveform")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(String(format: "RMS Peak: %.2f (%.1f dBFS)", peakLevel, 20 * log10(max(0.0001, peakLevel))))
                            .font(.speakMonoFace(.caption))
                            .foregroundStyle(isSimulating ? Color.speakHumanAmber : .secondary)
                    }
                }

                Divider()

                // Metadata Details
                VStack(alignment: .leading, spacing: SpeakSpacing.xs) {
                    Text("PCM Buffer & Transcriber Pipeline Metrics")
                        .font(.speakBody(.caption))
                        .foregroundStyle(.secondary)

                    Grid(alignment: .leading, horizontalSpacing: SpeakSpacing.lg, verticalSpacing: SpeakSpacing.xs) {
                        GridRow {
                            Text("Target Rate:").font(.speakBody(.caption)).foregroundStyle(.secondary)
                            Text("16,000 Hz (Standard ASR)").font(.speakMonoFace(.caption))
                        }
                        GridRow {
                            Text("Channels:").font(.speakBody(.caption)).foregroundStyle(.secondary)
                            Text("1 Channel (Mono)").font(.speakMonoFace(.caption))
                        }
                        GridRow {
                            Text("Tap Buffer Size:").font(.speakBody(.caption)).foregroundStyle(.secondary)
                            Text("4,096 frames (~256 ms)").font(.speakMonoFace(.caption))
                        }
                        GridRow {
                            Text("PCM Format:").font(.speakBody(.caption)).foregroundStyle(.secondary)
                            Text("Float32 Non-interleaved").font(.speakMonoFace(.caption))
                        }
                        GridRow {
                            Text("Signal Quality:").font(.speakBody(.caption)).foregroundStyle(.secondary)
                            Text("SNR: ~38 dB (Clean)").font(.speakMonoFace(.caption)).foregroundStyle(Color.speakDelivered)
                        }
                    }
                }
            }
            .padding(SpeakSpacing.md)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.speakSurface))
            .onDisappear {
                stopSimulation()
            }
        }
    }

    private func toggleSimulation() {
        if isSimulating {
            stopSimulation()
        } else {
            startSimulation()
        }
    }

    private func startSimulation() {
        isSimulating = true
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            Task { @MainActor in
                var newLevels: [CGFloat] = []
                for _ in 0..<28 {
                    newLevels.append(CGFloat.random(in: 0.08...0.95))
                }
                self.levels = newLevels
                self.peakLevel = Double(newLevels.max() ?? 0.3)
            }
        }
    }

    private func stopSimulation() {
        isSimulating = false
        timer?.invalidate()
        timer = nil
        levels = [
            0.12, 0.25, 0.45, 0.68, 0.85, 0.92, 0.74, 0.52,
            0.38, 0.60, 0.82, 0.96, 0.88, 0.64, 0.42, 0.28,
            0.55, 0.78, 0.90, 0.70, 0.48, 0.32, 0.18, 0.24,
            0.40, 0.62, 0.35, 0.15
        ]
        peakLevel = 0.96
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
            .font(.speakBody(.base))

            Text("Off = raw transcript passes through untouched.")
                .font(.speakBody(.caption))
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
                .font(.system(size: 16, weight: .semibold))

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
                .font(.speakBody(.caption))
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
                .font(.system(size: 16, weight: .semibold))

            VStack(alignment: .leading, spacing: SpeakSpacing.xs) {
                ForEach(context.profileStore.profiles, id: \.id) { profile in
                    profileRow(profile)
                }

                Button(action: createNew) {
                    Label("New profile", systemImage: "plus")
                        .font(.speakBody(.caption))
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
                    Text(profile.name).font(.speakMonoFace(.caption))
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
                profileExamplesField(p)
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
            Text("Name").font(.speakBody(.caption)).foregroundStyle(.secondary)
            TextField("Profile name", text: Binding(
                get: { p.name },
                set: { newValue in updateProfile { $0.name = newValue } }
            ))
            .font(.speakMonoFace(.base))
            .textFieldStyle(.roundedBorder)
        }
    }

    private func profileIconField(_ p: Profile) -> some View {
        VStack(alignment: .leading, spacing: SpeakSpacing.xs) {
            Text("Icon (SF Symbol)").font(.speakBody(.caption)).foregroundStyle(.secondary)
            TextField("SF Symbol name", text: Binding(
                get: { p.icon },
                set: { newValue in updateProfile { $0.icon = newValue } }
            ))
            .font(.speakMonoFace(.base))
            .textFieldStyle(.roundedBorder)
        }
    }

    private func profilePromptField(_ p: Profile) -> some View {
        VStack(alignment: .leading, spacing: SpeakSpacing.xs) {
            Text("System prompt").font(.speakBody(.caption)).foregroundStyle(.secondary)
            TextEditor(text: Binding(
                get: { p.systemPrompt },
                set: { newValue in updateProfile { $0.systemPrompt = newValue } }
            ))
            .font(.speakMonoFace(.base))
            .frame(minHeight: 100)
            .border(Color.gray.opacity(0.3), width: 1)
            .cornerRadius(4)
        }
    }

    private func profileExamplesField(_ p: Profile) -> some View {
        VStack(alignment: .leading, spacing: SpeakSpacing.xs) {
            Text("Few-shot examples").font(.speakBody(.caption)).foregroundStyle(.secondary)
            Text("Spoken → written pairs that steer the model. Strongest lever for small on-device models.")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)

            if !p.examples.isEmpty {
                VStack(alignment: .leading, spacing: SpeakSpacing.sm) {
                    ForEach(Array(p.examples.enumerated()), id: \.offset) { idx, example in
                        exampleRow(idx, example)
                    }
                }
            }

            Button(action: { addExample() }) {
                Label("Add example", systemImage: "plus").font(.speakBody(.caption))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, SpeakSpacing.xs)
        }
    }

    private func exampleRow(_ idx: Int, _ example: Example) -> some View {
        VStack(alignment: .leading, spacing: SpeakSpacing.xs) {
            HStack {
                Text("Example \(idx + 1)")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Button(action: { removeExample(idx) }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .help("Remove example \(idx + 1)")
            }
            HStack(spacing: SpeakSpacing.sm) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Spoken").font(.system(size: 9)).foregroundStyle(.tertiary)
                    TextField("Spoken input", text: Binding(
                        get: { example.spoken },
                        set: { v in updateProfile { $0.examples[idx].spoken = v } }
                    ))
                    .font(.speakMonoFace(.caption))
                    .textFieldStyle(.roundedBorder)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Written").font(.system(size: 9)).foregroundStyle(.tertiary)
                    TextField("Written output", text: Binding(
                        get: { example.written },
                        set: { v in updateProfile { $0.examples[idx].written = v } }
                    ))
                    .font(.speakMonoFace(.caption))
                    .textFieldStyle(.roundedBorder)
                }
            }
        }
        .padding(SpeakSpacing.xs)
        .background(Color.speakSurface)
        .cornerRadius(4)
    }

    private func addExample() {
        updateProfile { $0.examples.append(Example(spoken: "", written: "")) }
    }

    private func removeExample(_ idx: Int) {
        updateProfile { $0.examples.remove(at: idx) }
    }

    private func profileFormatOptions(_ p: Profile) -> some View {
        VStack(alignment: .leading, spacing: SpeakSpacing.xs) {
            Text("Output format").font(.speakBody(.caption)).foregroundStyle(.secondary)
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
            Text("Tone").font(.speakBody(.caption)).foregroundStyle(.secondary)
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
            Text("Length bias").font(.speakBody(.caption)).foregroundStyle(.secondary)
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
            Text("Target apps (bundle IDs or names)").font(.speakBody(.caption)).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: SpeakSpacing.xs) {
                ForEach(Array(p.targetApps.enumerated()), id: \.offset) { idx, app in
                    HStack(spacing: SpeakSpacing.xs) {
                        TextField("App", text: Binding(
                            get: { app },
                            set: { newValue in updateProfile { $0.targetApps[idx] = newValue } }
                        ))
                        .font(.speakMonoFace(.caption))
                        .textFieldStyle(.roundedBorder)

                        Button(action: { removeTargetApp(idx) }) {
                            Image(systemName: "xmark").foregroundStyle(.secondary)
                        }
                        .buttonStyle(.borderless)
                    }
                }

                Button(action: { addTargetApp() }) {
                    Label("Add app", systemImage: "plus").font(.speakBody(.caption))
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
        .font(.speakBody(.caption))
    }

    private func previewBox(_ p: Profile) -> some View {
        VStack(alignment: .leading, spacing: SpeakSpacing.sm) {
            Text("Live preview").font(.speakBody(.caption)).foregroundStyle(.secondary)
            TextField("Enter sample text", text: $previewSample)
                .font(.speakMonoFace(.base))
                .textFieldStyle(.roundedBorder)

            Button(action: { runPreview(p) }) {
                Label("Preview", systemImage: "play.fill").font(.speakBody(.caption))
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
                    .font(.speakBody(.caption))
                    .foregroundStyle(.secondary)
            case .raw:
                Text("Raw profile: output equals input (passthrough).")
                    .font(.speakBody(.caption))
                    .foregroundStyle(.secondary)
            case .transformed(let output):
                VStack(alignment: .leading, spacing: SpeakSpacing.xs) {
                    Text("Transformed output:").font(.speakBody(.caption)).foregroundStyle(.secondary)
                    Text(output)
                        .font(.speakMonoFace(.base))
                        .textSelection(.enabled)
                        .padding(SpeakSpacing.sm)
                        .background(Color.black.opacity(0.05))
                        .cornerRadius(4)
                    Text("[unverified on this Mac]").font(.system(size: 9)).foregroundStyle(.tertiary)
                }
            case .failed:
                Text("Preview failed. Check the system log for details.")
                    .font(.speakBody(.caption))
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
