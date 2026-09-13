// App/Overlay/ConversationOverlayView.swift
//
// Layer 3 Bidirectional Voice Architecture — Conversation Overlay View.
//
// Responsibilities:
//   - Displays floating macOS conversation HUD for active `ConversationState` states:
//     `.idle`, `.listening`, `.processing`, `.agentSpeaking`, `.interrupted`, `.paused`.
//   - Shows live user transcript and animated streaming agent speech text with readback progress.
//   - Surfaces Manual Fallback Controls:
//     - Mute/Pause Button (Space bar / tap): Toggles mic mute.
//     - Interrupt Button (Escape / tap): Immediately cuts off AI speech.
//     - Mode Switcher Chip: Toggle between Full-Duplex, Push-To-Talk, and Gated-Turn.
//     - Send Button & Input Field: Submit typed / gated turn responses.
//   - Theme tokens: speakAgentViolet (agent activity), speakError (interrupt), speakMica (idle/paused), speakSurface (wells).

import AppKit
import os
import SpeakCore
import SwiftUI

// MARK: - ConversationOverlayView

/// Floating macOS overlay view for bidirectional voice interaction.
struct ConversationOverlayView: View {

    // MARK: - Observed State

    @ObservedObject var loopManager: ConversationLoopManager
    let model: OverlayViewModel
    let settingsStore: SettingsStore

    // MARK: - Body

    var body: some View {
        contentVStack
            .padding(12)
            .frame(minWidth: 380, maxWidth: 440)
    }

    // MARK: - Content Layout

    private var contentVStack: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Top Row: State Pill + Mode Selector Chip
            headerRow

            // Middle: Transcript / Agent Response & Progress Display
            transcriptSection

            // Bottom: Text Input & Manual Controls Bar
            controlsSection
        }
        .padding(14)
    }

    // MARK: - Header Row

    private var headerRow: some View {
        ConversationHeaderRow(loopManager: loopManager)
    }

    // MARK: - Transcript Section

    private var transcriptSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Main Transcript / Streaming Speech Text
            ScrollViewReader { _ in
                ScrollView(.vertical, showsIndicators: false) {
                    Text(displayTranscriptText)
                        .font(.system(size: 13, weight: .regular))
                        .foregroundColor(displayTextColor)
                        .lineSpacing(3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 2)
                }
                .frame(maxHeight: 72)
            }

            // Agent Speech Playback Progress Bar (active during .agentSpeaking)
            if case .agentSpeaking(_, let progress) = loopManager.state {
                ProgressView(value: progress)
                    .progressViewStyle(.linear)
                    .tint(Color.speakAgentViolet)
                    .frame(height: 3)
                    .transition(.opacity)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.speakSurface)
        )
    }

    // MARK: - Controls Section

    private var controlsSection: some View {
        ConversationControlsSection(loopManager: loopManager)
    }

    // MARK: - State Helpers

    private var currentOverlayState: OverlayState {
        switch loopManager.state {
        case .idle, .paused:
            return .listening
        case .listening:
            return .listening
        case .processing:
            return .processing
        case .agentSpeaking:
            return .listening
        case .interrupted:
            return .error
        }
    }

    private var displayTranscriptText: String {
        switch loopManager.state {
        case .idle:
            return "Ready for conversation. Speak or type to begin."
        case .listening(let userText):
            let text = userText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty { return text }
            if !model.partialText.isEmpty { return model.partialText }
            return "Listening to your voice..."
        case .processing(let prompt):
            let text = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? "Processing request..." : "Thinking: \"\(text)\""
        case .agentSpeaking(let speechText, _):
            let text = speechText.trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? "Agent speaking..." : text
        case .interrupted(let partialText):
            let text = partialText.trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? "Speech interrupted. Ready for input." : "Interrupted: \"\(text)\""
        case .paused:
            return "Microphone is muted. Tap Mute or Space to resume."
        }
    }

    private var displayTextColor: Color {
        switch loopManager.state {
        case .idle, .paused:
            return .secondary
        case .listening, .agentSpeaking:
            return .primary
        case .processing:
            return Color.speakAgentViolet
        case .interrupted:
            return Color.speakError
        }
    }

}

// MARK: - ConversationHeaderRow

/// State badge pill + conversation mode selector chip for the conversation overlay header.
private struct ConversationHeaderRow: View {

    @ObservedObject var loopManager: ConversationLoopManager

    var body: some View {
        HStack(spacing: 8) {
            // State Badge Pill
            stateBadgePill

            Spacer()

            // Mode Selector Chip
            modeSelectorChip
        }
    }

    private var stateBadgePill: some View {
        HStack(spacing: 6) {
            Image(systemName: stateIconName)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(stateIconColor)

            Text(stateBadgeLabel)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.primary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(Color.speakSurface.opacity(0.6))
        )
    }

    private var modeSelectorChip: some View {
        Menu {
            ForEach(ConversationMode.allCases, id: \.self) { modeOption in
                Button {
                    SpeakLog.conversation.info("User switched conversation mode to \(modeOption.rawValue, privacy: .public)")
                    loopManager.setMode(modeOption)
                } label: {
                    HStack {
                        Text(modeOption.label)
                        if loopManager.mode == modeOption {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: modeIconName(for: loopManager.mode))
                    .font(.system(size: 10, weight: .bold))
                Text(loopManager.mode.label)
                    .font(.system(size: 11, weight: .medium))
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
            }
            .foregroundColor(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(Color.speakSurface.opacity(0.5))
            )
        }
        .buttonStyle(.plain)
    }

    private var stateBadgeLabel: String {
        switch loopManager.state {
        case .idle:
            return "Ready"
        case .listening:
            return "Listening..."
        case .processing:
            return "Thinking..."
        case .agentSpeaking(_, let progress):
            let percent = Int(progress * 100)
            return "Agent Speaking (\(percent)%)"
        case .interrupted:
            return "Interrupted"
        case .paused:
            return "Paused (Muted)"
        }
    }

    private var stateIconName: String {
        switch loopManager.state {
        case .idle:
            return "sparkler"
        case .listening:
            return "waveform.circle.fill"
        case .processing:
            return "sparkles"
        case .agentSpeaking:
            return "speaker.wave.2.fill"
        case .interrupted:
            return "exclamationmark.triangle.fill"
        case .paused:
            return "mic.slash.fill"
        }
    }

    private var stateIconColor: Color {
        switch loopManager.state {
        case .idle:
            return Color.speakMica
        case .listening, .processing, .agentSpeaking:
            return Color.speakAgentViolet
        case .interrupted:
            return Color.speakError
        case .paused:
            return Color.speakMica
        }
    }

    private func modeIconName(for mode: ConversationMode) -> String {
        switch mode {
        case .fullDuplex:
            return "waveform.path.ecg"
        case .pushToTalk:
            return "hand.tap.fill"
        case .gatedTurn:
            return "lock.fill"
        }
    }
}

// MARK: - ConversationControlsSection

/// Typed-response input row + Mute/Interrupt manual fallback controls for the conversation overlay.
private struct ConversationControlsSection: View {

    @ObservedObject var loopManager: ConversationLoopManager

    @State private var typedText: String = ""
    @FocusState private var isInputFocused: Bool

    var body: some View {
        VStack(spacing: 8) {
            // Optional Typed Response Row
            HStack(spacing: 6) {
                TextField("Type response (or press Space to speak)...", text: $typedText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.speakSurface.opacity(0.4))
                    )
                    .focused($isInputFocused)
                    .onSubmit {
                        commitTypedResponse()
                    }

                // Send Button
                Button {
                    commitTypedResponse()
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(typedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .secondary : Color.speakUIAccent)
                }
                .buttonStyle(.plain)
                .disabled(typedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .keyboardShortcut(.return, modifiers: [.command])
            }

            // Action Buttons Row (Mute / Pause, Interrupt)
            HStack(spacing: 8) {
                // Mute / Pause Button (Space)
                Button {
                    SpeakLog.conversation.info("User clicked Mute/Pause toggle button.")
                    _ = loopManager.toggleMute()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: loopManager.isMuted ? "mic.slash.fill" : "mic.fill")
                            .font(.system(size: 11, weight: .semibold))
                        Text(loopManager.isMuted ? "Unmute (Space)" : "Mute (Space)")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .frame(maxWidth: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(loopManager.isMuted ? Color.speakMica.opacity(0.25) : Color.speakSurface.opacity(0.6))
                    )
                    .foregroundColor(loopManager.isMuted ? Color.speakMica : .primary)
                }
                .buttonStyle(.plain)

                // Interrupt Button (Esc)
                Button {
                    SpeakLog.conversation.info("User clicked Interrupt button.")
                    loopManager.handleInterrupt()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 11, weight: .semibold))
                        Text("Interrupt (Esc)")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .frame(maxWidth: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(isInterruptEnabled ? Color.speakError.opacity(0.2) : Color.speakSurface.opacity(0.3))
                    )
                    .foregroundColor(isInterruptEnabled ? Color.speakError : .secondary)
                }
                .buttonStyle(.plain)
                .disabled(!isInterruptEnabled)
            }
        }
    }

    private var isInterruptEnabled: Bool {
        switch loopManager.state {
        case .agentSpeaking, .processing, .listening:
            return true
        case .idle, .interrupted, .paused:
            return false
        }
    }

    private func commitTypedResponse() {
        let trimmed = typedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        SpeakLog.conversation.info("User committed typed response in overlay.")
        loopManager.commitUserTurn(prompt: trimmed)
        typedText = ""
    }
}
