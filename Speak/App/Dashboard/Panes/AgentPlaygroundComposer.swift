// App/Dashboard/Panes/AgentPlaygroundComposer.swift
//
// The composer — the human end of the buffer.
//
// It is a *card*, not a chrome strip: it sits on the same reading measure as the
// document, so the line you type lands exactly where the answer will appear. The
// warm prompt glyph marks it as the human channel; while the model is generating,
// the card wears the inference flow border (the app's one sanctioned "working"
// signal) and the send button becomes a stop.
//
// The footer is the instrument panel: persona, context pressure, and the key hint.
// Persona / key-hint labels are chrome (SF Pro); the token count is data (SF Mono).

import Foundation
import SpeakCore
import SpeakLLM
import SwiftUI

// MARK: - Composer

struct PlaygroundComposer: View {
    @ObservedObject var viewModel: PlaygroundViewModel

    @FocusState private var isFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            PlaygroundHairline()

            VStack(alignment: .leading, spacing: SpeakSpacing.sm) {
                if let error = viewModel.errorMessage {
                    PlaygroundErrorStrip(message: error) { viewModel.errorMessage = nil }
                }

                card
            }
            .frame(maxWidth: PlaygroundMetrics.measure, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.horizontal, SpeakSpacing.lg)
            .padding(.vertical, SpeakSpacing.md)
        }
        .onAppear { isFocused = true }
    }

    // MARK: - Card

    private var card: some View {
        VStack(alignment: .leading, spacing: SpeakSpacing.sm) {
            inputRow
            PlaygroundComposerFooter(viewModel: viewModel)
        }
        .padding(.horizontal, SpeakSpacing.md - 2)
        .padding(.vertical, SpeakSpacing.sm + 2)
        .background(
            RoundedRectangle(cornerRadius: PlaygroundMetrics.cardRadius, style: .continuous)
                .fill(Color.speakCardCanvas)
        )
        .overlay(
            RoundedRectangle(cornerRadius: PlaygroundMetrics.cardRadius, style: .continuous)
                .strokeBorder(borderColor, lineWidth: 1)
        )
        .flowBorder(
            colors: Color.speakFlowInference,
            lineWidth: 1.5,
            cornerRadius: PlaygroundMetrics.cardRadius,
            speed: 1.5,
            isActive: viewModel.isStreaming
        )
        .animation(SpeakMotion.micro(reduceMotion: reduceMotion), value: isFocused)
    }

    private var borderColor: Color {
        if viewModel.isStreaming { return .clear }
        return isFocused ? Color.speakAgentViolet.opacity(0.35) : Color.speakCardBorder
    }

    // MARK: - Input row

    private var inputRow: some View {
        HStack(alignment: .top, spacing: SpeakSpacing.sm + 2) {
            Text("›")
                .font(.speakBody(.body, semibold: true))
                .foregroundStyle(Color.speakHumanAmber.opacity(isFocused ? 0.9 : 0.5))
                .padding(.top, 1)

            TextField(placeholder, text: $viewModel.inputText, axis: .vertical)
                .font(.speakBody(.base))
                .foregroundStyle(Color.speakBone)
                .textFieldStyle(.plain)
                .lineLimit(1...8)
                .focused($isFocused)
                .onSubmit(handleSubmit)

            actionButton
        }
    }

    private var placeholder: String {
        viewModel.isStreaming ? "the agent is writing…" : "Ask, or hand it something to work on"
    }

    private func handleSubmit() {
        guard !NSEvent.modifierFlags.contains(.shift) else { return }
        viewModel.sendMessage()
    }

    // MARK: - Send / stop

    @ViewBuilder
    private var actionButton: some View {
        if viewModel.isStreaming {
            PlaygroundCircleButton(
                symbol: "stop.fill",
                tint: Color(nsColor: .systemRed),
                isEnabled: true,
                help: "Stop generating",
                action: { viewModel.cancelStream() }
            )
        } else {
            PlaygroundCircleButton(
                symbol: "arrow.up",
                tint: Color.speakAgentViolet,
                isEnabled: canSend,
                help: "Send (Return)",
                action: { viewModel.sendMessage() }
            )
        }
    }

    private var canSend: Bool {
        !viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

// MARK: - Circle button

/// The one button shape in the composer. Enabled state is carried entirely by
/// tint strength — no shape change, so send↔stop is a pure crossfade.
struct PlaygroundCircleButton: View {
    let symbol: String
    let tint: Color
    let isEnabled: Bool
    let help: String
    let action: () -> Void

    @State private var isHovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(isEnabled ? tint : Color.speakMica.opacity(0.5))
                .frame(width: 28, height: 28)
                .background(Circle().fill(tint.opacity(fillOpacity)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .help(help)
        .onHover { hovering in
            withAnimation(SpeakMotion.micro(reduceMotion: reduceMotion)) { isHovering = hovering }
        }
    }

    private var fillOpacity: Double {
        guard isEnabled else { return 0.04 }
        return isHovering ? 0.22 : 0.13
    }
}

// MARK: - Footer

/// Persona · context pressure · key hint. Persona/key hint are chrome (SF Pro);
/// the token count is data (SF Mono). All tertiary until something asks for attention.
struct PlaygroundComposerFooter: View {
    @ObservedObject var viewModel: PlaygroundViewModel

    var body: some View {
        HStack(spacing: SpeakSpacing.sm) {
            personaButton

            Spacer(minLength: SpeakSpacing.sm)

            PlaygroundContextMeter(
                progress: viewModel.contextProgress,
                tokens: viewModel.contextTokenEstimate
            )

            Text("⇧⏎ newline")
                .font(.speakBody(.caption))
                .foregroundStyle(Color.speakMica.opacity(0.6))
        }
    }

    private var personaButton: some View {
        Button {
            viewModel.showSystemPrompt.toggle()
        } label: {
            HStack(spacing: 5) {
                Image(systemName: hasPersona ? "person.crop.square.filled.and.at.rectangle" : "person.crop.square")
                    .font(.system(size: 10))
                Text(hasPersona ? "persona set" : "persona")
                    .font(.speakBody(.caption))
            }
            .foregroundStyle(hasPersona ? Color.speakAgentViolet : Color.speakMica)
            .padding(.horizontal, SpeakSpacing.sm - 1)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(Color.speakAgentViolet.opacity(hasPersona ? 0.12 : 0))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Edit the system persona prepended to every request")
        .popover(isPresented: $viewModel.showSystemPrompt, arrowEdge: .bottom) {
            PlaygroundPersonaEditor(viewModel: viewModel)
        }
    }

    private var hasPersona: Bool {
        !viewModel.systemPrompt.isEmpty
    }
}

// MARK: - Context meter

/// Context pressure as a short capsule rather than a full-width bar: it is a
/// gauge, not a progress indicator, and it should read at a glance without
/// drawing a line across the whole window.
struct PlaygroundContextMeter: View {
    let progress: Double
    let tokens: Int

    var body: some View {
        HStack(spacing: 6) {
            Capsule(style: .continuous)
                .fill(Color.speakMica.opacity(0.2))
                .frame(width: 44, height: 3)
                .overlay(alignment: .leading) {
                    Capsule(style: .continuous)
                        .fill(barColor)
                        .frame(width: 44 * max(0, min(progress, 1)), height: 3)
                }

            Text("\(tokens) tok")
                .font(.speakMonoFace(.caption))
                .foregroundStyle(Color.speakMica.opacity(0.8))
                .monospacedDigit()
        }
        .help("Approximate context used in this conversation")
    }

    private var barColor: Color {
        if progress > 0.85 { return Color(nsColor: .systemRed).opacity(0.8) }
        if progress > 0.6 { return Color.speakHumanAmber.opacity(0.8) }
        return Color.speakAgentViolet.opacity(0.7)
    }
}

// MARK: - Error strip

/// Failures are part of the document, not a truncated string in the toolbar:
/// full text, dismissible, and out of the way once read.
struct PlaygroundErrorStrip: View {
    let message: String
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: SpeakSpacing.sm) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 11))
                .foregroundStyle(Color(nsColor: .systemRed))

            Text(message)
                .font(.speakBody(.caption))
                .foregroundStyle(Color.speakBone.opacity(0.9))
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)

            Spacer(minLength: SpeakSpacing.sm)

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Color.speakMica)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Dismiss")
        }
        .padding(.horizontal, SpeakSpacing.sm + 2)
        .padding(.vertical, SpeakSpacing.sm)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(nsColor: .systemRed).opacity(0.09))
        )
    }
}

// MARK: - Persona editor

/// The system persona, edited in place. Framed as authorship ("the voice the
/// agent writes in"), which is what it actually controls.
struct PlaygroundPersonaEditor: View {
    @ObservedObject var viewModel: PlaygroundViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: SpeakSpacing.sm) {
            Text("Persona")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color.speakBone)

            Text("Prepended to every request. The voice and constraints the agent writes in.")
                .font(.speakBody(.caption))
                .foregroundStyle(Color.speakMica)
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: 340, alignment: .leading)

            TextEditor(text: $viewModel.systemPrompt)
                .font(.speakBody(.base))
                .foregroundStyle(Color.speakBone)
                .frame(width: 340, height: 120)
                .scrollContentBackground(.hidden)
                .padding(SpeakSpacing.sm)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.speakSidebarSelection.opacity(0.5))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color.speakCardBorder, lineWidth: 1)
                )

            HStack(spacing: SpeakSpacing.sm) {
                Button("Clear") { viewModel.systemPrompt = "" }
                    .disabled(viewModel.systemPrompt.isEmpty)

                Spacer()

                Button("Done") { viewModel.showSystemPrompt = false }
                    .keyboardShortcut(.defaultAction)
            }
            .font(.speakBody(.caption))
        }
        .padding(SpeakSpacing.md)
    }
}
