// App/Settings/TextToSpeechSettingsView.swift
//
// "Text to Speech" — the third pipeline layer of the dedicated Settings
// experience: the voice that speaks back. Configures the shared
// `SpeechSynthesizing` engine (AppleSpeechSynthesizer / AVSpeechSynthesizer,
// 100% on-device): voice, rate, pitch, volume, the post-dictation readback
// affordance, and a live preview that speaks through the SAME engine instance
// the overlay uses (context.voiceOut), so what you hear here is what the app
// produces everywhere.
//
// [decision: voice list from `AVSpeechSynthesisVoice.speechVoices()` — sync,
//  local, already installed; sorted so voices matching the dictation language
//  lead. "Automatic" (empty identifier) lets the engine pick the best voice
//  for the session locale at speak-time.]

import AVFoundation
import SpeakCore
import SwiftUI

// MARK: - TextToSpeechSettingsView

@MainActor
struct TextToSpeechSettingsView: View {
    let context: DashboardContext

    private var store: SettingsStore { context.settingsStore }

    @State private var voices: [AVSpeechSynthesisVoice] = []
    @State private var previewText = "This is how speak sounds when it reads text back to you."
    @State private var previewing = false

    var body: some View {
        VStack(alignment: .leading, spacing: SpeakSpacing.lg) {
            voiceCard
            previewCard
            readbackCard
        }
        .task {
            // One-shot sync query — the roster is already installed locally.
            if voices.isEmpty { voices = AVSpeechSynthesisVoice.speechVoices() }
        }
        .onDisappear {
            // Leaving the pane mid-preview must not leave speech playing.
            if previewing, let voiceOut = context.voiceOut {
                Task { await voiceOut.stop() }
            }
        }
    }

    // MARK: - Voice

    private var voiceCard: some View {
        SettingsSectionCard(title: "Voice") {
            SettingsRow(
                "Voice",
                description: "“Automatic” picks the best installed voice for the dictation language."
            ) {
                Picker("", selection: Binding(
                    get: { store.ttsVoiceIdentifier },
                    set: { store.ttsVoiceIdentifier = $0 }
                )) {
                    Text("Automatic").tag("")
                    ForEach(sortedVoices, id: \.identifier) { voice in
                        Text(voiceLabel(voice)).tag(voice.identifier)
                    }
                }
                .pickerStyle(.menu)
                .fixedSize()
            }

            SettingsRowSeparator()

            SettingsRow(
                "Speaking Rate",
                description: rateLabel
            ) {
                Slider(value: Binding(
                    get: { Double(store.ttsSpeechRate) },
                    set: { store.ttsSpeechRate = Float($0) }
                ), in: 0.25...0.75)
                .frame(width: 160)
            }

            SettingsRowSeparator()

            SettingsRow(
                "Pitch",
                description: pitchLabel
            ) {
                Slider(value: Binding(
                    get: { Double(store.ttsPitchMultiplier) },
                    set: { store.ttsPitchMultiplier = Float($0) }
                ), in: 0.5...2.0)
                .frame(width: 160)
            }

            SettingsRowSeparator()

            SettingsRow(
                "Volume",
                description: "Playback loudness for readbacks and agent speech."
            ) {
                Slider(value: Binding(
                    get: { Double(store.ttsVolume) },
                    set: { store.ttsVolume = Float($0) }
                ), in: 0...1.0)
                .frame(width: 160)
            }
        }
    }

    // MARK: - Preview

    private var previewCard: some View {
        SettingsSectionCard(title: "Preview") {
            SettingsRow(
                "Hear this voice",
                description: context.voiceOut == nil
                    ? "Preview is unavailable in this context."
                    : "Speaks through the same engine the overlay readback uses."
            ) {
                HStack(spacing: SpeakSpacing.sm) {
                    TextField("Preview text", text: $previewText)
                        .textFieldStyle(.roundedBorder)
                        .font(.speakBody(.caption))
                        .frame(width: 220)
                    Button(previewing ? "Stop" : "Play") {
                        togglePreview()
                    }
                    .disabled(context.voiceOut == nil
                              || (!previewing && previewText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty))
                }
            }
        }
    }

    // MARK: - Readback

    private var readbackCard: some View {
        SettingsSectionCard(title: "Readback") {
            SettingsRow(
                "Read back finished transcripts",
                description: "Adds a speaker button after each dictation to hear it read aloud on-device."
            ) {
                Toggle("", isOn: Binding(
                    get: { store.readbackEnabled },
                    set: { store.readbackEnabled = $0 }
                ))
                .toggleStyle(.switch)
                .controlSize(.small)
            }
        }
    }

    // MARK: - Helpers

    /// Voices for the current dictation language first, then everything else.
    private var sortedVoices: [AVSpeechSynthesisVoice] {
        let languageCode = store.language.language.languageCode?.identifier ?? "en"
        let matching = voices.filter { $0.language.hasPrefix(languageCode) }
        let rest = voices.filter { !$0.language.hasPrefix(languageCode) }
        return matching + rest
    }

    private func voiceLabel(_ voice: AVSpeechSynthesisVoice) -> String {
        var label = "\(voice.name) — \(voice.language)"
        if voice.quality == .enhanced { label += " (Enhanced)" }
        return label
    }

    private var rateLabel: String {
        String(format: "%.2f — 0.50 is the system default.", store.ttsSpeechRate)
    }

    private var pitchLabel: String {
        String(format: "%.1f× voice pitch.", store.ttsPitchMultiplier)
    }

    private func togglePreview() {
        guard let voiceOut = context.voiceOut else { return }
        if previewing {
            Task { await voiceOut.stop() }
            previewing = false
            return
        }
        Task {
            previewing = true
            await voiceOut.speak(
                previewText,
                voiceIdentifier: store.ttsVoiceIdentifier.isEmpty ? nil : store.ttsVoiceIdentifier,
                rate: store.ttsSpeechRate,
                pitch: store.ttsPitchMultiplier,
                volume: store.ttsVolume,
                locale: store.language
            )
            previewing = false
        }
    }
}
