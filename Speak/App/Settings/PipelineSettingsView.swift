// App/Settings/PipelineSettingsView.swift
//
// "Voice Pipeline" — the assembled final layer of the dedicated Settings
// experience. The product is a pipeline — `speech → text → intelligence →
// speech` — and this page is where the three layer panes (Speech to Text,
// Intelligence, Text to Speech) are shown composed: each stage row reports its
// live configuration and status and jumps straight to that layer's pane.
//
// It also hosts the end-to-end "Test the Loop" sandbox (a real CaptureSession
// with inserter: nil — nothing is pasted) plus a "Read result aloud" step, so
// the full loop — ears → intelligence → voice — is provable from one card.
// Voice Actions routing (the spoken-prefix intent router, H-1) lives here as
// the pipeline's behavior switch.

import AVFoundation
import SpeakCore
import SwiftUI

// MARK: - PipelineSettingsView

@MainActor
struct PipelineSettingsView: View {
    let context: DashboardContext
    /// Jumps the rail to a layer's own pane (the "Configure" affordance).
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

    private var loopCard: some View {
        SettingsSectionCard(title: "The Voice Loop") {
            layerRow(
                category: .speechToText,
                summary: sttSummary,
                status: sttStatus
            )

            connectorRow

            layerRow(
                category: .intelligence,
                summary: intelligenceSummary,
                status: intelligenceStatus
            )

            connectorRow

            layerRow(
                category: .textToSpeech,
                summary: ttsSummary,
                status: ttsStatus
            )
        }
    }

    /// One pipeline stage: bordered neutral tile + layer name + live config
    /// summary on the left; optional status pill + chevron on the right. The
    /// tile is a flow node — shape carries it, not hue (same icon language as
    /// the rail). The whole row navigates. Pills are shown only for meaningful
    /// state; the default healthy path is not badged.
    private func layerRow(
        category: SettingsCategory,
        summary: String,
        status: (text: String, tint: Color)?
    ) -> some View {
        Button {
            onSelectCategory(category)
        } label: {
            HStack(spacing: SpeakSpacing.sm + 2) {
                Image(systemName: category.systemImage)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.speakMica)
                    .frame(width: 26, height: 26)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(Color.speakSurface)
                            .overlay(
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .stroke(Color.speakCardBorder, lineWidth: 1)
                            )
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text(category.title)
                        .font(.speakBody(.base, semibold: true))
                        .foregroundStyle(.speakBone)
                    Text(summary)
                        .font(.speakBody(.caption))
                        .foregroundStyle(.speakMica)
                        .lineLimit(1)
                }

                Spacer(minLength: SpeakSpacing.sm)

                if let status {
                    SettingsStatusPill(text: status.text, tint: status.tint)
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.speakMica)
            }
            .padding(.horizontal, SpeakSpacing.md)
            .padding(.vertical, SpeakSpacing.sm + 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// The `↓` connector between stages — same left inset as the tiles so the
    /// chain reads as one vertical flow.
    private var connectorRow: some View {
        Image(systemName: "arrow.down")
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(.speakMica)
            .padding(.leading, SpeakSpacing.md + 8)
            .padding(.vertical, 2)
    }

    // MARK: - Stage summaries + status

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
        context.permissionManager?.status(.microphone) == .granted
            ? nil
            : ("Needs mic", .speakWarning)
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
        store.effectiveCleanupLevel == .none
            ? nil
            : ("On", .speakAgentViolet)
    }

    private var ttsSummary: String {
        let voice = store.ttsVoiceIdentifier.isEmpty
            ? "Automatic voice"
            : (AVSpeechSynthesisVoice(identifier: store.ttsVoiceIdentifier)?.name ?? "Custom voice")
        return "\(voice) · rate \(String(format: "%.2f", store.ttsSpeechRate))"
    }

    private var ttsStatus: (text: String, tint: Color)? {
        store.readbackEnabled ? ("Readback", .speakAgentViolet) : nil
    }

    // MARK: - Test the Loop

    /// End-to-end sandbox: a real `CaptureSession` (settings-derived locale,
    /// vocab + corrections, snippets, cleanup mode) with `inserter: nil` —
    /// nothing is pasted. When a result lands, "Read it aloud" runs the text
    /// through `context.voiceOut` with the stored TTS settings — the literal
    /// speech → text → intelligence → speech loop.
    private var testCard: some View {
        SettingsSectionCard(title: "Test the Loop") {
            VStack(alignment: .leading, spacing: SpeakSpacing.sm) {
                HStack(spacing: SpeakSpacing.md) {
                    HoldToTalkPill(
                        model: sandbox,
                        isEnabled: context.permissionManager?.status(.microphone) == .granted
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
                            .foregroundStyle(.speakMica)
                    }
                }

                SettingsRowSeparator()

                sandboxContent
            }
            .padding(.horizontal, SpeakSpacing.md)
            .padding(.vertical, SpeakSpacing.sm + 4)
        }
    }

    @ViewBuilder
    private var sandboxContent: some View {
        switch sandbox.phase {
        case .idle:
            if context.permissionManager?.status(.microphone) != .granted {
                HStack(spacing: SpeakSpacing.xs) {
                    Image(systemName: "mic.slash")
                        .foregroundStyle(.speakWarning)
                    Text("Microphone permission is required to test the loop.")
                        .font(.speakBody(.caption))
                        .foregroundStyle(.speakMica)
                }
            } else {
                Text("Hold the pill (or tap once) and say a sentence — e.g. “um open the rippo and run cubectl get pods”. The pipeline cleans it on-device; nothing is pasted.")
                    .font(.speakBody(.caption))
                    .foregroundStyle(.speakMica)
            }

        case .listening, .processing:
            VStack(alignment: .leading, spacing: SpeakSpacing.xs) {
                ScrollView {
                    Text(sandbox.transcriptText.isEmpty ? "Listening…" : sandbox.transcriptText)
                        .font(.speakMonoFace(.base))
                        .foregroundStyle(sandbox.transcriptText.isEmpty ? .speakMica : .speakBone)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(minHeight: 44, maxHeight: 96)

                if sandbox.phase == .processing {
                    HStack(spacing: SpeakSpacing.xs) {
                        ProgressView().controlSize(.small)
                        Text("Cleaning on-device…")
                            .font(.speakBody(.caption))
                            .foregroundStyle(.speakMica)
                    }
                }
            }

        case .done:
            if let result = sandbox.result {
                VStack(alignment: .leading, spacing: SpeakSpacing.xs) {
                    CleanupDiffView(rawText: result.rawText, cleanedText: result.cleanedText)
                        .frame(minHeight: 120)

                    HStack(spacing: SpeakSpacing.xs) {
                        if let ms = sandbox.processingMilliseconds {
                            Text(result.cleanedText == nil
                                 ? "delivered raw — cleanup off or engine unavailable"
                                 : "cleaned in \(ms) ms by \(result.engineId)")
                                .font(.speakMonoFace(.caption))
                                .foregroundStyle(.speakMica)
                        }
                        Spacer()
                        if context.voiceOut != nil {
                            Button(readingAloud ? "Stop" : "Read it aloud") {
                                toggleReadAloud(result)
                            }
                            .font(.speakBody(.caption))
                            .buttonStyle(.borderless)
                            .tint(.speakUIAccent)
                        }
                        Button("Test again") { sandbox.reset() }
                            .font(.speakBody(.caption))
                            .buttonStyle(.borderless)
                            .tint(.speakUIAccent)
                    }
                }
            }

        case .failed(let message):
            HStack(spacing: SpeakSpacing.xs) {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(.speakError)
                Text(message)
                    .font(.speakBody(.caption))
                    .foregroundStyle(.speakMica)
                Spacer()
                Button("Try again") { sandbox.reset() }
                    .font(.speakBody(.caption))
                    .buttonStyle(.borderless)
                    .tint(.speakUIAccent)
            }
        }
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
            }
        }
    }
}
