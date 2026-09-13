// App/Settings/TextToSpeechSettingsView.swift
//
// "Text to Speech" — the voice-out stage of the pipeline: the voice that
// speaks back. Configures the shared `SpeechSynthesizing` engine
// (AppleSpeechSynthesizer / AVSpeechSynthesizer, 100% on-device): voice,
// rate, pitch, volume, the post-dictation readback affordance, and a live
// preview that speaks through the SAME engine instance the overlay uses
// (context.voiceOut), so what you hear here is what the app produces
// everywhere.
//
// [decision: voice list from `AVSpeechSynthesisVoice.speechVoices()` — sync,
//  local, already installed; voices matching the dictation language lead the
//  menu (divider-separated), then everything else. "Automatic" (empty
//  identifier) lets the engine pick the best voice for the session locale at
//  speak-time. A saved identifier that no longer resolves is surfaced — never
//  silently cleared — with a one-tap reset to Automatic; playback falls back
//  to the locale voice meanwhile (see AppleSpeechSynthesizer.speak).]

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
                description: savedVoiceMissing
                    ? "The saved voice isn't installed — playback uses Automatic."
                    : "“Automatic” picks the best installed voice for the dictation language."
            ) {
                Picker("", selection: Binding(
                    get: { store.ttsVoiceIdentifier },
                    set: { store.ttsVoiceIdentifier = $0 }
                )) {
                    Text("Automatic")
                        .tag("")

                    if savedVoiceMissing {
                        // Keep the missing identifier selectable so the picker
                        // never renders a blank selection.
                        Text("\(savedVoiceName) (not installed)")
                            .tag(store.ttsVoiceIdentifier)
                    }

                    if !matchingVoices.isEmpty {
                        Divider()
                        ForEach(matchingVoices, id: \.identifier) { voice in
                            Text(voiceLabel(voice))
                                .tag(voice.identifier)
                        }
                    }

                    if !otherVoices.isEmpty {
                        Divider()
                        ForEach(otherVoices, id: \.identifier) { voice in
                            Text(voiceLabel(voice))
                                .tag(voice.identifier)
                        }
                    }
                }
                .pickerStyle(.menu)
                .tint(.speakUIAccent)
                .fixedSize()
                .accessibilityLabel("Voice")
            }

            if savedVoiceMissing {
                SettingsRowSeparator()

                HStack(spacing: SpeakSpacing.xs) {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(Color.speakWarning)
                    Text("“\(savedVoiceName)” isn't installed on this Mac — playback falls back to Automatic until it returns.")
                        .font(.speakBody(.caption))
                        .foregroundStyle(Color.speakMica)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: SpeakSpacing.sm)
                    Button("Use Automatic") {
                        store.ttsVoiceIdentifier = ""
                    }
                    .font(.speakBody(.caption))
                    .buttonStyle(.borderless)
                    .tint(.speakUIAccent)
                }
                .padding(.horizontal, SpeakSpacing.md)
                .padding(.vertical, SpeakSpacing.sm + 4)
            }

            SettingsRowSeparator()

            sliderRow(
                "Speaking Rate",
                description: "0.50× is the system default — lower is slower, higher is faster.",
                value: Binding(
                    get: { store.ttsSpeechRate },
                    set: { store.ttsSpeechRate = $0 }
                ),
                range: 0.25...0.75,
                caption: rateCaption,
                accessibility: "Speaking rate"
            )

            SettingsRowSeparator()

            sliderRow(
                "Pitch",
                description: "1.00× is the voice's natural pitch.",
                value: Binding(
                    get: { store.ttsPitchMultiplier },
                    set: { store.ttsPitchMultiplier = $0 }
                ),
                range: 0.5...2.0,
                caption: pitchCaption,
                accessibility: "Pitch"
            )

            SettingsRowSeparator()

            sliderRow(
                "Volume",
                description: "Playback loudness for readbacks and agent speech.",
                value: Binding(
                    get: { store.ttsVolume },
                    set: { store.ttsVolume = $0 }
                ),
                range: 0...1.0,
                caption: volumeCaption,
                accessibility: "Volume"
            )
        }
    }

    /// One labelled slider + formatted-unit readout — the shared control shape
    /// for rate / pitch / volume. The readout is monospaced and fixed-width so
    /// dragging never shifts the layout.
    private func sliderRow(
        _ title: String,
        description: String,
        value: Binding<Float>,
        range: ClosedRange<Double>,
        caption: String,
        accessibility: String
    ) -> some View {
        SettingsRow(title, description: description) {
            HStack(spacing: SpeakSpacing.sm) {
                Slider(
                    value: Binding(
                        get: { Double(value.wrappedValue) },
                        set: { value.wrappedValue = Float($0) }
                    ),
                    in: range
                )
                .tint(.speakUIAccent)
                .frame(width: 140)
                .accessibilityLabel(accessibility)

                Text(caption)
                    .font(.speakMonoFace(.caption))
                    .foregroundStyle(Color.speakMica)
                    .frame(width: 44, alignment: .trailing)
            }
        }
    }

    // MARK: - Preview

    private var previewCard: some View {
        SettingsSectionCard(title: "Preview") {
            SettingsRow(
                "Hear this voice",
                description: previewDescription
            ) {
                HStack(spacing: SpeakSpacing.sm) {
                    TextField("Preview text", text: $previewText)
                        .textFieldStyle(.roundedBorder)
                        .font(.speakBody(.caption))
                        .tint(.speakUIAccent)
                        .frame(width: 220)
                        .onSubmit {
                            if !previewing { togglePreview() }
                        }

                    if previewing {
                        Image(systemName: "speaker.wave.2.fill")
                            .font(.speakBody(.caption))
                            .foregroundStyle(Color.speakUIAccent)
                            .symbolEffect(.variableColor.iterative, options: .repeating)
                            .accessibilityHidden(true)
                    }

                    Button {
                        togglePreview()
                    } label: {
                        Label(
                            previewing ? "Stop" : "Play",
                            systemImage: previewing ? "stop.fill" : "play.fill"
                        )
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.speakUIAccent)
                    .disabled(!previewAvailable || (!previewing && previewTextIsEmpty))
                    .accessibilityLabel(previewing ? "Stop preview" : "Play preview")
                }
            }
        }
    }

    // MARK: - Readback

    private var readbackCard: some View {
        SettingsSectionCard(title: "Readback") {
            SettingsRow(
                "Read back finished transcripts",
                description: """
                Adds a speaker button to each finished dictation — tap it to hear the transcript \
                read aloud on-device. It only speaks when you ask, and a new dictation stops it instantly.
                """
            ) {
                Toggle("", isOn: Binding(
                    get: { store.readbackEnabled },
                    set: { store.readbackEnabled = $0 }
                ))
                .toggleStyle(.switch)
                .controlSize(.small)
                .tint(.speakUIAccent)
            }
        }
    }

    // MARK: - Voice list

    /// Voices for the current dictation language — the first menu group.
    private var matchingVoices: [AVSpeechSynthesisVoice] {
        voices.filter { $0.language.hasPrefix(dictationLanguageCode) }
    }

    /// Every other installed voice — the second menu group.
    private var otherVoices: [AVSpeechSynthesisVoice] {
        voices.filter { !$0.language.hasPrefix(dictationLanguageCode) }
    }

    private var dictationLanguageCode: String {
        store.language.language.languageCode?.identifier ?? "en"
    }

    /// `true` when a voice is saved but no longer installed — the engine
    /// silently falls back to the locale voice, so we surface it here.
    private var savedVoiceMissing: Bool {
        let identifier = store.ttsVoiceIdentifier
        return !identifier.isEmpty
            && AVSpeechSynthesisVoice(identifier: identifier) == nil
    }

    /// Best-effort display name for a saved-but-missing voice — the
    /// identifier's last dotted component capitalized
    /// ("…voice.samantha" → "Samantha").
    private var savedVoiceName: String {
        store.ttsVoiceIdentifier
            .split(separator: ".")
            .last
            .map { $0.capitalized } ?? "Saved voice"
    }

    /// "Samantha — English (United States) · Enhanced": localized language
    /// name so the menu scans like System Settings, not like BCP-47 codes.
    private func voiceLabel(_ voice: AVSpeechSynthesisVoice) -> String {
        let language = Locale.current.localizedString(forIdentifier: voice.language)
            ?? voice.language
        var label = "\(voice.name) — \(language)"
        switch voice.quality {
        case .enhanced: label += " · Enhanced"
        case .premium:  label += " · Premium"
        default: break
        }
        return label
    }

    // MARK: - Captions + preview

    private var rateCaption: String {
        String(format: "%.2f×", store.ttsSpeechRate)
    }

    private var pitchCaption: String {
        String(format: "%.2f×", store.ttsPitchMultiplier)
    }

    private var volumeCaption: String {
        String(format: "%.0f%%", store.ttsVolume * 100)
    }

    private var previewAvailable: Bool {
        context.voiceOut != nil
    }

    private var previewTextIsEmpty: Bool {
        previewText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var previewDescription: String {
        if !previewAvailable {
            return "Preview is unavailable in this context."
        }
        if previewing {
            return "Playing through the same engine the overlay readback uses."
        }
        return "Speaks through the same engine the overlay readback uses."
    }

    private func togglePreview() {
        guard let voiceOut = context.voiceOut else { return }
        if previewing {
            Task { await voiceOut.stop() }
            previewing = false
            return
        }
        let text = previewText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        Task {
            previewing = true
            await voiceOut.speak(
                text,
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
