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
            VStack(alignment: .leading, spacing: SpeakSpacing.md) {
                Picker("Studio View", selection: $selectedTab) {
                    ForEach(StudioTab.allCases) { tab in
                        Label(tab.rawValue, systemImage: tab.icon)
                            .foregroundStyle(.speakBone)
                            .tag(tab)
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
            DefaultProfileSection(context: context)

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
        InferenceEmptyState(
            systemImage: "brain.head.profile",
            headline: "No profile selected",
            message: "Pick a profile on the left to edit it,\nor create a new one."
        )
        .frame(maxHeight: .infinity)
        .speakCard()
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
                        .foregroundStyle(.speakBone)
                    Text("Configure on-device AVSpeechSynthesizer voices, speech rate, pitch, volume, and test live audio readbacks.")
                        .font(.speakBody(.caption))
                        .foregroundStyle(.speakMica)
                }
                Spacer()
                Button(action: resetTTSDefaults) {
                    Label("Reset Voice Defaults", systemImage: "arrow.counterclockwise")
                        .font(.speakBody(.caption))
                        .foregroundStyle(.speakBone)
                }
            }

            VStack(alignment: .leading, spacing: SpeakSpacing.md) {
                // On-Device Voice picker
                VStack(alignment: .leading, spacing: SpeakSpacing.xs) {
                    Text("On-Device TTS Voice").font(.speakBody(.caption)).foregroundStyle(.speakAgentViolet)
                    Picker("Voice", selection: Binding(
                        get: { context.settingsStore.ttsVoiceIdentifier },
                        set: { context.settingsStore.ttsVoiceIdentifier = $0 }
                    )) {
                        Text("System Default (Locale matching)").tag("").foregroundStyle(.speakBone)
                        ForEach(availableVoices, id: \.identifier) { voice in
                            Text("\(voice.name) (\(voice.language)\(qualityBadge(voice.quality)))")
                                .foregroundStyle(.speakBone)
                                .tag(voice.identifier)
                        }
                    }
                    .pickerStyle(.menu)
                }

                // Speech Rate
                VStack(alignment: .leading, spacing: SpeakSpacing.xs) {
                    HStack {
                        Text("Speech Rate").font(.speakBody(.caption)).foregroundStyle(.speakAgentViolet)
                        Spacer()
                        Text(String(format: "%.2fx (Default: 0.50x)", context.settingsStore.ttsSpeechRate))
                            .font(.speakMonoFace(.caption))
                            .foregroundStyle(.speakMica)
                    }
                    Slider(value: Binding(
                        get: { Double(context.settingsStore.ttsSpeechRate) },
                        set: { context.settingsStore.ttsSpeechRate = Float($0) }
                    ), in: 0.1...1.0, step: 0.05)
                }

                // Pitch Multiplier
                VStack(alignment: .leading, spacing: SpeakSpacing.xs) {
                    HStack {
                        Text("Pitch Multiplier").font(.speakBody(.caption)).foregroundStyle(.speakAgentViolet)
                        Spacer()
                        Text(String(format: "%.2fx (Default: 1.00x)", context.settingsStore.ttsPitchMultiplier))
                            .font(.speakMonoFace(.caption))
                            .foregroundStyle(.speakMica)
                    }
                    Slider(value: Binding(
                        get: { Double(context.settingsStore.ttsPitchMultiplier) },
                        set: { context.settingsStore.ttsPitchMultiplier = Float($0) }
                    ), in: 0.5...2.0, step: 0.05)
                }

                // Volume Slider
                VStack(alignment: .leading, spacing: SpeakSpacing.xs) {
                    HStack {
                        Text("Volume").font(.speakBody(.caption)).foregroundStyle(.speakAgentViolet)
                        Spacer()
                        Text(String(format: "%.0f%%", context.settingsStore.ttsVolume * 100))
                            .font(.speakMonoFace(.caption))
                            .foregroundStyle(.speakMica)
                    }
                    Slider(value: Binding(
                        get: { Double(context.settingsStore.ttsVolume) },
                        set: { context.settingsStore.ttsVolume = Float($0) }
                    ), in: 0.0...1.0, step: 0.05)
                }

                StudioHairline()

                // Live Audio Readback Test
                VStack(alignment: .leading, spacing: SpeakSpacing.sm) {
                    Text("Live Audio Readback Test").font(.speakBody(.caption)).foregroundStyle(.speakAgentViolet)

                    TextField("Test utterance text", text: $testText)
                        .font(.speakBody(.base))
                        .textFieldStyle(.roundedBorder)
                        .foregroundStyle(.speakBone)

                    HStack(spacing: SpeakSpacing.sm) {
                        Button(action: testReadback) {
                            Label(isSpeaking ? "Speaking…" : "Test Voice Readback", systemImage: "speaker.wave.2.fill")
                                .font(.speakBody(.caption))
                                .foregroundStyle(.speakBone)
                        }
                        .disabled(testText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSpeaking)

                        if isSpeaking {
                            Button(action: stopReadback) {
                                Label("Stop", systemImage: "square.fill")
                                    .font(.speakBody(.caption))
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.speakError)
                        }

                        Spacer()

                        if isSpeaking {
                            // TTS readback is the AGENT channel — violet, never
                            // amber (amber is the mic) and never onAir.
                            HStack(spacing: 5) {
                                Circle().fill(Color.speakAgentViolet).frame(width: 6, height: 6)
                                Text("Speaking")
                                    .font(.speakBody(.caption, semibold: true))
                                    .foregroundStyle(Color.speakAgentViolet)
                            }
                            .accessibilityLabel("Audio playing")
                        }
                    }
                }
            }
            .padding(SpeakSpacing.md)
            .speakCard()
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
    /// `nil` = no PermissionManager injected (previews) → no banner is shown.
    @State private var micPermission: PermissionState?
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
                        .foregroundStyle(.speakBone)
                    Text("Inspect audio signal dynamics, peak RMS levels, and PCM stream metrics.")
                        .font(.speakBody(.caption))
                        .foregroundStyle(.speakMica)
                }
                Spacer()
                Button(action: toggleSimulation) {
                    Label(isSimulating ? "Pause Inspection" : "Simulate Live Audio", systemImage: isSimulating ? "pause.fill" : "play.fill")
                        .font(.speakBody(.caption))
                        .foregroundStyle(.speakBone)
                }
            }

            VStack(alignment: .leading, spacing: SpeakSpacing.md) {
                if let micPermission, micPermission != .granted {
                    StudioNoticeStrip(
                        systemImage: "mic.slash.fill",
                        tint: .speakWarning,
                        message: "Microphone access is \(micPermission == .denied ? "denied" : "not granted") — live capture and voice answers cannot run until it is resolved.",
                        actionTitle: context.showOnboarding != nil ? "Resolve" : nil,
                        action: { context.showOnboarding?() }
                    )
                }

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
                    .speakInset(cornerRadius: 8)

                    HStack {
                        // The amber mic color is earned only while the meter is
                        // actually running — idle, the legend admits the levels
                        // below are a stored sample, not live capture.
                        Label(
                            isSimulating ? "Simulated 16 kHz mono PCM — running" : "Sample levels · 16 kHz mono PCM",
                            systemImage: "waveform"
                        )
                            .font(.speakBody(.caption))
                            .foregroundStyle(isSimulating ? Color.speakHumanAmber : Color.speakMica)
                        Spacer()
                        Text(String(format: "RMS Peak: %.2f (%.1f dBFS)", peakLevel, 20 * log10(max(0.0001, peakLevel))))
                            .font(.speakMonoFace(.caption))
                            .foregroundStyle(isSimulating ? Color.speakHumanAmber : .speakMica)
                    }
                }

                StudioHairline()

                // Metadata Details
                VStack(alignment: .leading, spacing: SpeakSpacing.xs) {
                    Text("PCM Buffer & Transcriber Pipeline Metrics")
                        .font(.speakBody(.caption, semibold: true))
                        .foregroundStyle(.speakBone)

                    Grid(alignment: .leading, horizontalSpacing: SpeakSpacing.lg, verticalSpacing: SpeakSpacing.xs) {
                        GridRow {
                            Text("Target Rate").font(.speakBody(.caption)).foregroundStyle(.speakMica)
                            Text("16,000 Hz (standard ASR)").font(.speakMonoFace(.caption)).foregroundStyle(.speakBone)
                        }
                        GridRow {
                            Text("Channels").font(.speakBody(.caption)).foregroundStyle(.speakMica)
                            Text("1 channel (mono)").font(.speakMonoFace(.caption)).foregroundStyle(.speakBone)
                        }
                        GridRow {
                            Text("Tap Buffer Size").font(.speakBody(.caption)).foregroundStyle(.speakMica)
                            Text("4,096 frames (~256 ms)").font(.speakMonoFace(.caption)).foregroundStyle(.speakBone)
                        }
                        GridRow {
                            Text("PCM Format").font(.speakBody(.caption)).foregroundStyle(.speakMica)
                            Text("Float32 non-interleaved").font(.speakMonoFace(.caption)).foregroundStyle(.speakBone)
                        }
                        GridRow {
                            Text("Signal Quality").font(.speakBody(.caption)).foregroundStyle(.speakMica)
                            Text("SNR ~38 dB (clean sample)").font(.speakMonoFace(.caption)).foregroundStyle(Color.speakOK)
                        }
                    }
                }
            }
            .padding(SpeakSpacing.md)
            .speakCard()
            .onAppear {
                micPermission = context.permissionManager?.status(.microphone)
            }
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
            Text("AI Cleanup")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.speakBone)

            VStack(alignment: .leading, spacing: SpeakSpacing.sm) {
                Toggle(isOn: Binding(
                    get: { settingsStore.cleanupEnabled },
                    set: { settingsStore.cleanupEnabled = $0 }
                )) {
                    Text("AI cleanup")
                        .font(.speakBody(.base))
                        .foregroundStyle(.speakBone)
                }

                Text("Off = raw transcript passes through untouched.")
                    .font(.speakBody(.caption))
                    .foregroundStyle(.speakMica)
            }
            .padding(SpeakSpacing.md)
            .speakCard()
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
                .foregroundStyle(.speakBone)

            VStack(alignment: .leading, spacing: SpeakSpacing.sm) {
                Picker("Default profile", selection: Binding(
                    get: { context.profileStore.defaultProfileID },
                    set: { context.profileStore.defaultProfileID = $0 }
                )) {
                    ForEach(context.profileStore.profiles, id: \.id) { profile in
                        Label(profile.name, systemImage: profile.icon)
                            .foregroundStyle(.speakBone)
                            .tag(profile.id)
                    }
                }
                .pickerStyle(.menu)

                Text("Sets which profile governs the default path. Today the everyday writing "
                     + "style is set in Settings › Intelligence — full default-profile wiring is "
                     + "the next step. App-specific profiles (below) are active now.")
                    .font(.speakBody(.caption))
                    .foregroundStyle(.speakMica)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(SpeakSpacing.md)
            .speakCard()
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
                .foregroundStyle(.speakBone)

            VStack(alignment: .leading, spacing: SpeakSpacing.xs) {
                ForEach(context.profileStore.profiles, id: \.id) { profile in
                    profileRow(profile)
                }

                Button(action: createNew) {
                    Label("New profile", systemImage: "plus")
                        .font(.speakBody(.caption))
                        .foregroundStyle(.speakBone)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, SpeakSpacing.sm)
            }
            .padding(SpeakSpacing.sm)
            .speakCard()
        }
    }

    private func profileRow(_ profile: Profile) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: { selectProfile(profile) }) {
                HStack(spacing: SpeakSpacing.sm) {
                    Image(systemName: profile.icon).font(.system(size: 12))
                    Text(profile.name).font(.speakBody(.caption))
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(SpeakSpacing.xs)
                .foregroundStyle(selectedID == profile.id ? Color.speakUIAccent : .speakBone)
                .background(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(selectedID == profile.id ? Color.speakUIAccent.opacity(0.12) : Color.clear)
                )
            }

            if !profile.targetApps.isEmpty {
                Text("Active in: " + profile.targetApps.joined(separator: ", "))
                    .font(.speakBody(.caption))
                    .foregroundStyle(.speakMica)
                    .lineLimit(2)
                    .padding(.leading, SpeakSpacing.xs)
                    .padding(.top, SpeakSpacing.xs)
            } else if profile.isBuiltIn {
                Text("Foundational")
                    .font(.speakBody(.caption))
                    .foregroundStyle(.speakMica)
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


// MARK: - Shared chrome (pane-local)

/// The themed hairline — `Divider()` picks up a system gray that fights the
/// two-temperature palette.
struct StudioHairline: View {
    var body: some View {
        Rectangle()
            .fill(Color.speakCardBorder)
            .frame(height: 1)
            .opacity(0.5)
    }
}

/// A one-line tinted notice strip — caution (warning) or failure (error)
/// callouts inside a card, with an optional trailing action.
struct StudioNoticeStrip: View {
    let systemImage: String
    let tint: Color
    let message: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .top, spacing: SpeakSpacing.sm) {
            Image(systemName: systemImage)
                .font(.system(size: 11))
            Text(message)
                .font(.speakBody(.caption))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: SpeakSpacing.sm)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .font(.speakBody(.caption, semibold: true))
                    .buttonStyle(.plain)
            }
        }
        .foregroundStyle(tint)
        .padding(SpeakSpacing.sm)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(tint.opacity(0.08))
        )
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
