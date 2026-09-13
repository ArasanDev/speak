// App/Settings/PipelineSettingsView.swift
//
// "Voice Pipeline" — the assembled final layer of the dedicated Settings
// experience. The product is a pipeline — `speech → text → intelligence →
// speech` — and this page is where the three layer panes (Speech to Text,
// Intelligence, Text to Speech) are shown composed: a left-to-right status
// map of live stage tiles that each jump straight to their layer's pane.
//
// It also hosts the end-to-end "Test the Loop" sandbox (a real CaptureSession
// with inserter: nil — nothing is pasted) plus a "Read aloud" step, so the
// full loop — ears → intelligence → voice — is provable from one card.
// Voice Actions routing (the spoken-prefix intent router, H-1) lives here as
// the pipeline's behavior switch.
//
// Stage tiles are neutral bordered nodes (speakSurface + hairline); status
// pills carry state — ON ok / NEEDS MIC warning / FALLS BACK warning /
// READBACK agentViolet / UNAVAILABLE error — so the map is readable at a
// glance without hue doing structural work.

import AVFoundation
import SpeakCore
import SwiftUI

// MARK: - PipelineSettingsView

@MainActor
struct PipelineSettingsView: View {
    let context: DashboardContext
    /// Jumps the rail to a layer's own pane (the "Open" affordance).
    let onSelectCategory: (SettingsCategory) -> Void

    private var store: SettingsStore { context.settingsStore }

    @State private var sandbox = VoiceSandboxModel()
    @State private var readingAloud = false

    var body: some View {
        VStack(alignment: .leading, spacing: SpeakSpacing.lg) {
            loopCard
            testCard
            voiceActionsCard
        }
        .onDisappear {
            Task { await sandbox.cancel() }
            if let voiceOut = context.voiceOut {
                Task { await voiceOut.stop() }
            }
        }
    }

    // MARK: - The assembled loop

    /// The live stage map — STT → Intelligence → Voice Out, left to right.
    /// Each tile reports its live configuration summary + status pill and the
    /// whole tile is a jump link into that layer's pane.
    private var loopCard: some View {
        SettingsSectionCard(title: "The Voice Loop") {
            HStack(alignment: .center, spacing: SpeakSpacing.sm) {
                PipelineStageTile(
                    category: .speechToText,
                    summary: sttSummary,
                    status: sttStatus
                ) {
                    onSelectCategory(.speechToText)
                }

                flowArrow

                PipelineStageTile(
                    category: .intelligence,
                    summary: intelligenceSummary,
                    status: intelligenceStatus
                ) {
                    onSelectCategory(.intelligence)
                }

                flowArrow

                PipelineStageTile(
                    category: .textToSpeech,
                    summary: ttsSummary,
                    status: ttsStatus
                ) {
                    onSelectCategory(.textToSpeech)
                }
            }
            .padding(.horizontal, SpeakSpacing.md)
            .padding(.vertical, SpeakSpacing.sm + 4)
        }
    }

    /// The `→` between stage tiles — the flow is left to right, ears to voice.
    private var flowArrow: some View {
        Image(systemName: "arrow.right")
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(Color.speakMica)
            .accessibilityHidden(true)
    }

    // MARK: - Stage summaries + status

    private var micGranted: Bool {
        context.permissionManager?.status(.microphone) == .granted
    }

    private var sttSummary: String {
        let engine: String
        switch store.sttEngine {
        case .appleSpeech: engine = "Apple Speech"
        case .whisperKit:  engine = "WhisperKit"
        case .whisperCpp:  engine = "whisper.cpp"
        }
        return "\(engine) · \(store.language.identifier)"
    }

    private var sttStatus: (text: String, tint: Color)? {
        if !micGranted { return ("Needs mic", .speakWarning) }
        // Unimplemented engines degrade to Apple Speech at capture time.
        return store.sttEngine == .appleSpeech
            ? ("On", .speakOK)
            : ("Falls back", .speakWarning)
    }

    private var intelligenceSummary: String {
        let engine: String
        switch store.cleanupEngine {
        case .foundationModels: engine = "Foundation Models"
        case .ollama(let model): engine = "Ollama · \(model)"
        case .openAICompatible(let preset, let model): engine = "\(preset.displayName) · \(model)"
        case .mlx(let model): engine = "MLX · \(model)"
        }
        return "\(engine) · \(store.effectiveCleanupLevel.displayName)"
    }

    private var intelligenceStatus: (text: String, tint: Color)? {
        guard store.effectiveCleanupLevel != .none else {
            return ("Off", .speakMica)
        }
        // MLX is a v0.1 stub — sessions fall back to the raw transcript.
        if case .mlx = store.cleanupEngine {
            return ("Falls back", .speakWarning)
        }
        return ("On", .speakOK)
    }

    private var ttsSummary: String {
        "\(ttsVoiceName) · \(String(format: "%.2f×", store.ttsSpeechRate)) rate"
    }

    /// Saved-voice display name — resolves the identifier to an installed
    /// voice, or falls back to the identifier's last component so a missing
    /// voice still reads as a name, not an opaque ID.
    private var ttsVoiceName: String {
        let identifier = store.ttsVoiceIdentifier
        if identifier.isEmpty { return "Automatic voice" }
        if let voice = AVSpeechSynthesisVoice(identifier: identifier) {
            return voice.name
        }
        return identifier.split(separator: ".").last.map { $0.capitalized }
            ?? "Saved voice"
    }

    private var ttsStatus: (text: String, tint: Color)? {
        if context.voiceOut == nil { return ("Unavailable", .speakError) }
        let identifier = store.ttsVoiceIdentifier
        if !identifier.isEmpty, AVSpeechSynthesisVoice(identifier: identifier) == nil {
            return ("Voice missing", .speakWarning)
        }
        return store.readbackEnabled
            ? ("Readback", .speakAgentViolet)
            : ("Ready", .speakOK)
    }

    // MARK: - Test the Loop

    /// End-to-end sandbox: a real `CaptureSession` (settings-derived locale,
    /// vocab + corrections, snippets, cleanup mode) with `inserter: nil` —
    /// nothing is pasted. When a result lands, "Read aloud" runs the text
    /// through `context.voiceOut` with the stored TTS settings — the literal
    /// speech → text → intelligence → speech loop.
    private var testCard: some View {
        SettingsSectionCard(title: "Test the Loop") {
            VStack(alignment: .leading, spacing: SpeakSpacing.sm) {
                HStack(spacing: SpeakSpacing.md) {
                    HoldToTalkPill(
                        model: sandbox,
                        isEnabled: micGranted
                    ) {
                        await sandbox.begin(settings: store, snippetStore: context.snippetStore)
                    } onEnd: {
                        await sandbox.end()
                    }

                    VUMeterView(level: sandbox.level)
                        .opacity(sandbox.phase == .listening ? 1 : 0.35)

                    Spacer()

                    if sandbox.phase == .listening {
                        Text(String(format: "%.1fs", sandbox.elapsed))
                            .font(.speakMonoFace(.caption))
                            .foregroundStyle(Color.speakMica)
                    }

                    phasePill
                }

                SettingsRowSeparator()

                sandboxContent
            }
            .padding(.horizontal, SpeakSpacing.md)
            .padding(.vertical, SpeakSpacing.sm + 4)
        }
    }

    /// The sandbox's own status pill — ON AIR only while the mic is live,
    /// DELIVERED for a terminal success, ERROR for a failed run.
    @ViewBuilder
    private var phasePill: some View {
        switch sandbox.phase {
        case .idle:
            EmptyView()
        case .listening:
            SettingsStatusPill(text: "Recording", tint: .speakOnAir)
        case .processing:
            SettingsStatusPill(text: "Cleaning", tint: .speakMica)
        case .done:
            SettingsStatusPill(text: "Done", tint: .speakDelivered)
        case .failed:
            SettingsStatusPill(text: "Failed", tint: .speakError)
        }
    }

    @ViewBuilder
    private var sandboxContent: some View {
        switch sandbox.phase {
        case .idle:
            if !micGranted {
                Label(
                    "Microphone permission is required to test the loop.",
                    systemImage: "mic.slash"
                )
                .font(.speakBody(.caption))
                .foregroundStyle(Color.speakWarning)
            } else {
                Text("Hold the pill — or tap once to latch — and say a sentence, e.g. “um open the rippo and run cubectl get pods”. The full pipeline cleans it on-device; nothing is pasted.")
                    .font(.speakBody(.caption))
                    .foregroundStyle(Color.speakMica)
                    .fixedSize(horizontal: false, vertical: true)
            }

        case .listening, .processing:
            VStack(alignment: .leading, spacing: SpeakSpacing.xs) {
                ScrollView {
                    Text(sandbox.transcriptText.isEmpty ? "Listening…" : sandbox.transcriptText)
                        .font(.speakMonoFace(.base))
                        .foregroundStyle(sandbox.transcriptText.isEmpty ? Color.speakMica : Color.speakBone)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(SpeakSpacing.sm)
                }
                .frame(minHeight: 44, maxHeight: 96)
                .speakInset()

                if sandbox.phase == .processing {
                    HStack(spacing: SpeakSpacing.xs) {
                        ProgressView().controlSize(.small)
                        Text("Cleaning on-device…")
                            .font(.speakBody(.caption))
                            .foregroundStyle(Color.speakMica)
                    }
                }
            }

        case .done:
            if let result = sandbox.result {
                VStack(alignment: .leading, spacing: SpeakSpacing.xs) {
                    if result.audioWasSilent {
                        sandboxNote(
                            icon: "mic.slash",
                            tint: .speakWarning,
                            text: "The microphone heard silence — check the input source on the Speech to Text layer."
                        )
                    } else if spokenText(for: result).isEmpty {
                        sandboxNote(
                            icon: "text.quote",
                            tint: .speakMica,
                            text: "Nothing was transcribed — hold a little longer and try again."
                        )
                    } else {
                        CleanupDiffView(rawText: result.rawText, cleanedText: result.cleanedText)
                            .frame(minHeight: 120)
                    }

                    HStack(spacing: SpeakSpacing.sm) {
                        if let ms = sandbox.processingMilliseconds {
                            Text(result.cleanedText == nil
                                 ? "Delivered raw — cleanup is off or the engine was unavailable"
                                 : "Cleaned in \(ms) ms by \(result.engineId)")
                                .font(.speakMonoFace(.caption))
                                .foregroundStyle(Color.speakMica)
                        }
                        Spacer()
                        if context.voiceOut != nil, !spokenText(for: result).isEmpty {
                            Button {
                                toggleReadAloud(result)
                            } label: {
                                Label(
                                    readingAloud ? "Stop" : "Read aloud",
                                    systemImage: readingAloud ? "stop.fill" : "speaker.wave.2.fill"
                                )
                            }
                            .font(.speakBody(.caption))
                            .buttonStyle(.borderless)
                            .tint(.speakUIAccent)
                        }
                        Button {
                            resetSandbox()
                        } label: {
                            Label("Test again", systemImage: "arrow.clockwise")
                        }
                        .font(.speakBody(.caption))
                        .buttonStyle(.borderless)
                        .tint(.speakUIAccent)
                    }
                }
            }

        case .failed(let message):
            HStack(spacing: SpeakSpacing.xs) {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(Color.speakError)
                Text(message)
                    .font(.speakBody(.caption))
                    .foregroundStyle(Color.speakMica)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
                Button {
                    resetSandbox()
                } label: {
                    Label("Try again", systemImage: "arrow.clockwise")
                }
                .font(.speakBody(.caption))
                .buttonStyle(.borderless)
                .tint(.speakUIAccent)
            }
        }
    }

    /// One caption-strength note row (icon + wrapped text) inside the sandbox.
    private func sandboxNote(icon: String, tint: Color, text: String) -> some View {
        HStack(alignment: .top, spacing: SpeakSpacing.xs) {
            Image(systemName: icon)
                .foregroundStyle(tint)
            Text(text)
                .font(.speakBody(.caption))
                .foregroundStyle(Color.speakMica)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// What "Read aloud" would speak — cleaned when available, else raw.
    private func spokenText(for result: TranscriptionResult) -> String {
        (result.cleanedText ?? result.rawText)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Resetting the sandbox also stops an in-flight read-aloud — a stale
    /// result must never keep speaking over the next run.
    private func resetSandbox() {
        readingAloud = false
        if let voiceOut = context.voiceOut {
            Task { await voiceOut.stop() }
        }
        sandbox.reset()
    }

    private func toggleReadAloud(_ result: TranscriptionResult) {
        guard let voiceOut = context.voiceOut else { return }
        if readingAloud {
            Task { await voiceOut.stop() }
            readingAloud = false
            return
        }
        let text = result.cleanedText ?? result.rawText
        Task {
            readingAloud = true
            await voiceOut.speak(
                text,
                voiceIdentifier: store.ttsVoiceIdentifier.isEmpty ? nil : store.ttsVoiceIdentifier,
                rate: store.ttsSpeechRate,
                pitch: store.ttsPitchMultiplier,
                volume: store.ttsVolume,
                locale: store.language
            )
            readingAloud = false
        }
    }

    // MARK: - Voice Actions

    /// H-1 (specs/horizon-voice-os.md Pillar 1): the spoken-prefix intent
    /// router. Off = byte-identical dictation behavior; on = a leading
    /// "hey speak …" routes to commands/actions instead of typing.
    private var voiceActionsCard: some View {
        SettingsSectionCard(title: "Voice Actions") {
            SettingsRow(
                "Voice Actions",
                description: "Say the prefix at the start of an utterance to run a command instead of dictating text."
            ) {
                Toggle("", isOn: Binding(
                    get: { store.voiceActionsEnabled },
                    set: { store.voiceActionsEnabled = $0 }
                ))
                .toggleStyle(.switch)
                .controlSize(.small)
                .tint(.speakUIAccent)
            }

            if store.voiceActionsEnabled {
                SettingsRowSeparator()

                SettingsRow(
                    "Activation Prefix",
                    description: "Matched at the start of what you say, case-insensitive."
                ) {
                    TextField("hey speak", text: Binding(
                        get: { store.voiceActionsPrefix },
                        set: { store.voiceActionsPrefix = $0 }
                    ))
                    .textFieldStyle(.roundedBorder)
                    .font(.speakBody(.caption))
                    .tint(.speakUIAccent)
                    .frame(width: 140)
                }

                if store.voiceActionsPrefix.trimmingCharacters(in: .whitespaces).isEmpty {
                    SettingsRowSeparator()

                    HStack(spacing: SpeakSpacing.xs) {
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundStyle(Color.speakWarning)
                        Text("Voice Actions won't trigger with an empty prefix.")
                            .font(.speakBody(.caption))
                            .foregroundStyle(Color.speakMica)
                        Spacer()
                    }
                    .padding(.horizontal, SpeakSpacing.md)
                    .padding(.vertical, SpeakSpacing.sm + 4)
                }
            }
        }
    }
}

// MARK: - PipelineStageTile

/// One node in the voice-loop map: a neutral bordered tile (speakSurface +
/// hairline — same shape language as the rail icons) with the layer icon,
/// name, live config summary, and a status pill. The whole tile is the jump
/// link — an accent "Open →" affordance plus a hover ring make that obvious.
/// [decision: shape carries the flow node, hue stays on the status pill]
private struct PipelineStageTile: View {
    let category: SettingsCategory
    let summary: String
    let status: (text: String, tint: Color)?
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: SpeakSpacing.xs) {
                HStack(spacing: SpeakSpacing.xs) {
                    Image(systemName: category.systemImage)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.speakBone)
                        .frame(width: 24, height: 24)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(Color.speakCardCanvas)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .stroke(Color.speakCardBorder, lineWidth: 1)
                                )
                        )

                    Spacer(minLength: 0)

                    if let status {
                        SettingsStatusPill(text: status.text, tint: status.tint)
                    }
                }

                Text(category.title)
                    .font(.speakBody(.base, semibold: true))
                    .foregroundStyle(Color.speakBone)

                Text(summary)
                    .font(.speakBody(.caption))
                    .foregroundStyle(Color.speakMica)
                    .lineLimit(2, reservesSpace: true)
                    .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: SpeakSpacing.xs) {
                    Text("Open")
                        .font(.speakBody(.caption, semibold: true))
                    Image(systemName: "arrow.right")
                        .font(.system(size: 9, weight: .bold))
                }
                .foregroundStyle(Color.speakUIAccent)
            }
            .padding(SpeakSpacing.sm + 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.speakSurface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(
                                hovering ? Color.speakUIAccent : Color.speakCardBorder,
                                lineWidth: 1
                            )
                    )
            )
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeInOut(duration: 0.15), value: hovering)
        .accessibilityHint("Opens \(category.title) settings")
    }
}
