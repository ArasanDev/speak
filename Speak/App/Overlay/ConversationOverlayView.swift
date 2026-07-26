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
//   - Applies Magenta / Violet color palette (`AnimatedGradientBorder` / `EdgeFlowBorder` with magenta hues).

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

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // MARK: - Local State

    @State private var typedText: String = ""
    @FocusState private var isInputFocused: Bool

    // MARK: - Body

    var body: some View {
        ZStack {
            // Glass background container
            ZStack {
                VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                contentVStack
            }
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

            // Magenta / Violet Animated Border Layer
            borderLayer
        }
        .padding(4)
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
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.6))
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
                    .fill(Color(nsColor: .controlBackgroundColor).opacity(0.5))
            )
        }
        .buttonStyle(.plain)
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
                    .tint(Color(hue: 0.83, saturation: 0.85, brightness: 1.00)) // Magenta tint
                    .frame(height: 3)
                    .transition(.opacity)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(nsColor: .textBackgroundColor).opacity(0.3))
        )
    }

    // MARK: - Controls Section

    private var controlsSection: some View {
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
                            .fill(Color(nsColor: .controlBackgroundColor).opacity(0.4))
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
                        .foregroundColor(typedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .secondary : Color(hue: 0.83, saturation: 0.85, brightness: 1.00))
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
                            .fill(loopManager.isMuted ? Color.purple.opacity(0.25) : Color(nsColor: .controlBackgroundColor).opacity(0.6))
                    )
                    .foregroundColor(loopManager.isMuted ? .purple : .primary)
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
                            .fill(isInterruptEnabled ? Color.pink.opacity(0.2) : Color(nsColor: .controlBackgroundColor).opacity(0.3))
                    )
                    .foregroundColor(isInterruptEnabled ? .pink : .secondary)
                }
                .buttonStyle(.plain)
                .disabled(!isInterruptEnabled)
            }
        }
    }

    // MARK: - Border Layer (Magenta / Violet Palette)

    @ViewBuilder
    private var borderLayer: some View {
        let roundedShape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        let mappedOverlayState = currentOverlayState

        switch settingsStore.borderAnimationStyle {
        case .none:
            // Fallback crisp magenta outline if border animation style is disabled
            roundedShape
                .stroke(
                    LinearGradient(
                        colors: magentaVioletPalette,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.5
                )

        case .fullGlow:
            AnimatedGradientBorder(
                shape: roundedShape,
                state: mappedOverlayState,
                level: model.level,
                reduceMotion: reduceMotion,
                customPalette: magentaVioletPalette
            )

        case .edgeFlow:
            EdgeFlowBorder(
                shape: roundedShape,
                state: mappedOverlayState,
                level: model.level,
                speed: settingsStore.borderFlowSpeed,
                count: settingsStore.borderFlowCount,
                reduceMotion: reduceMotion,
                customPalette: magentaVioletPalette
            )
        }
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
            return .secondary
        case .listening:
            return Color(hue: 0.83, saturation: 0.85, brightness: 1.00) // Magenta
        case .processing:
            return Color(hue: 0.78, saturation: 0.88, brightness: 1.00) // Violet
        case .agentSpeaking:
            return Color(hue: 0.85, saturation: 0.90, brightness: 1.00) // Vibrant Magenta
        case .interrupted:
            return .pink
        case .paused:
            return .purple
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
            return Color(hue: 0.78, saturation: 0.88, brightness: 1.00)
        case .interrupted:
            return .pink
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

    // MARK: - Actions

    private func commitTypedResponse() {
        let trimmed = typedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        SpeakLog.conversation.info("User committed typed response in overlay.")
        loopManager.commitUserTurn(prompt: trimmed)
        typedText = ""
    }

    // MARK: - Magenta / Violet Palette

    /// Magenta & Violet gradient stops for Layer 3 Bidirectional Voice UI.
    private var magentaVioletPalette: [Color] {
        switch loopManager.state {
        case .listening:
            return [
                Color(hue: 0.83, saturation: 0.85, brightness: 1.00),  // Deep Magenta
                Color(hue: 0.78, saturation: 0.88, brightness: 1.00),  // Violet
                Color(hue: 0.72, saturation: 0.82, brightness: 0.95),  // Indigo-Violet
                Color(hue: 0.88, saturation: 0.80, brightness: 1.00),  // Magenta-Rose
            ]
        case .agentSpeaking:
            return [
                Color(hue: 0.85, saturation: 0.90, brightness: 1.00),  // Vibrant Magenta
                Color(hue: 0.80, saturation: 0.85, brightness: 1.00),  // Bright Violet
                Color(hue: 0.75, saturation: 0.90, brightness: 1.00),  // Electric Violet
                Color(hue: 0.85, saturation: 0.90, brightness: 1.00),  // Wrap Magenta
            ]
        case .processing:
            return [
                Color(hue: 0.80, saturation: 0.75, brightness: 0.90),  // Muted Violet
                Color(hue: 0.85, saturation: 0.70, brightness: 0.95),  // Soft Magenta
                Color(hue: 0.78, saturation: 0.80, brightness: 0.85),  // Deep Purple
                Color(hue: 0.80, saturation: 0.75, brightness: 0.90),  // Wrap
            ]
        case .interrupted:
            return [
                Color(hue: 0.95, saturation: 0.88, brightness: 1.00),  // Crimson Pink
                Color(hue: 0.85, saturation: 0.95, brightness: 0.90),  // Magenta Alert
                Color(hue: 0.98, saturation: 0.80, brightness: 0.95),  // Deep Rose
                Color(hue: 0.95, saturation: 0.88, brightness: 1.00),
            ]
        case .paused, .idle:
            return [
                Color(hue: 0.78, saturation: 0.50, brightness: 0.70),  // Dimmed Violet
                Color(hue: 0.83, saturation: 0.45, brightness: 0.75),  // Dimmed Magenta
                Color(hue: 0.76, saturation: 0.50, brightness: 0.65),  // Dimmed Purple
                Color(hue: 0.78, saturation: 0.50, brightness: 0.70),
            ]
        }
    }
}
