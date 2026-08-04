// App/Dashboard/Panes/AgentPlaygroundDocument.swift
//
// The buffer itself: the scrolling document, the two kinds of turn, the wine-label
// colophon, the cadence-paced in-flight response, and the blank page.
//
// See `AgentPlaygroundSurfaces.swift` for the pane's full design thesis; the two
// rules that govern this file specifically:
//   - The human's line and the model's answer are different *kinds of text*, not
//     differently-coloured bubbles.
//   - Nothing may reflow after the fact: the colophon's line is reserved before
//     the receipt arrives, and the streaming reveal converges on the true text so
//     the swap to a finished paragraph is invisible.

import Foundation
import SpeakCore
import SpeakLLM
import SwiftUI

// MARK: - Document

/// The buffer. A single scrolling column of turns — no bubbles, no avatars, no
/// alternating alignment. The document is the interface.
struct PlaygroundDocument: View {
    @ObservedObject var viewModel: PlaygroundViewModel

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if viewModel.messages.isEmpty && !viewModel.isStreaming {
                        PlaygroundEmptyState { starter in
                            viewModel.inputText = starter
                        }
                    }

                    ForEach(viewModel.messages) { message in
                        PlaygroundTurn(
                            message: message,
                            provenance: viewModel.provenanceLog[message.id]
                        )
                        .id(message.id)
                    }

                    if viewModel.isStreaming {
                        PlaygroundStreamingTurn(text: viewModel.streamingText)
                            .id(PlaygroundDocument.streamAnchor)
                    }

                    Spacer(minLength: SpeakSpacing.xl)
                }
                .frame(maxWidth: PlaygroundMetrics.measure, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.horizontal, SpeakSpacing.lg)
                .padding(.bottom, SpeakSpacing.lg)
            }
            .onChange(of: viewModel.messages.count) {
                scrollToEnd(proxy)
            }
            .onChange(of: viewModel.streamingText) {
                withAnimation(.easeOut(duration: 0.08)) {
                    proxy.scrollTo(PlaygroundDocument.streamAnchor, anchor: .bottom)
                }
            }
        }
    }

    /// Stable identity for the in-flight response, so the scroll follows it.
    static let streamAnchor = "speak.playground.stream"

    private func scrollToEnd(_ proxy: ScrollViewProxy) {
        guard let lastId = viewModel.messages.last?.id else { return }
        withAnimation(.easeOut(duration: 0.15)) {
            proxy.scrollTo(lastId, anchor: .bottom)
        }
    }
}

// MARK: - Turn

/// One entry in the buffer. The human's line and the model's answer are typeset
/// as different *kinds of text*, not as differently-coloured chat bubbles.
struct PlaygroundTurn: View {
    let message: ChatMessage
    let provenance: ProvenanceReceipt?

    @State private var isHovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isUser: Bool { message.role == "user" }

    var body: some View {
        Group {
            if isUser {
                instruction
            } else {
                response
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // The human command line: dimmed, behind a warm rule.
    private var instruction: some View {
        HStack(alignment: .top, spacing: SpeakSpacing.sm + 2) {
            RoundedRectangle(cornerRadius: 1, style: .continuous)
                .fill(Color.speakHumanAmber.opacity(0.55))
                .frame(width: 2)

            Text(message.content)
                .font(.speakBody(.base))
                .foregroundStyle(Color.speakMica)
                .lineSpacing(3)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.top, PlaygroundMetrics.turnGap)
        .padding(.bottom, SpeakSpacing.md)
    }

    // The model's answer: full measure, composed, with its colophon at the foot.
    private var response: some View {
        VStack(alignment: .leading, spacing: SpeakSpacing.sm) {
            Text(message.content)
                .font(.speakBody(.body))
                .foregroundStyle(Color.speakBone)
                .lineSpacing(PlaygroundMetrics.proseLeading)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)

            PlaygroundColophon(receipt: provenance, isRevealed: isHovering)
        }
        .padding(.bottom, SpeakSpacing.xs)
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(SpeakMotion.micro(reduceMotion: reduceMotion)) { isHovering = hovering }
        }
    }
}

// MARK: - Colophon

/// The wine label: which backend actually poured this, how long it took, what it
/// cost. Always occupies its line so a late receipt cannot shift the page; sits at
/// half strength until the pointer enters the paragraph it belongs to.
struct PlaygroundColophon: View {
    let receipt: ProvenanceReceipt?
    let isRevealed: Bool

    var body: some View {
        HStack(spacing: SpeakSpacing.sm) {
            if let receipt {
                Text("◆")
                    .foregroundStyle(Color.speakAgentViolet.opacity(0.7))

                Text(receipt.backendID)
                    .foregroundStyle(Color.speakAgentViolet)

                separator
                Text("\(receipt.latencyMS) ms")
                    .foregroundStyle(Color.speakMica)

                separator
                Text("\(receipt.promptTokens + receipt.completionTokens) tok")
                    .foregroundStyle(Color.speakMica)

                if let rate = throughput(receipt) {
                    separator
                    Text(rate)
                        .foregroundStyle(Color.speakMica)
                }

                if receipt.fellBack {
                    separator
                    Text("fell back from \(receipt.requestedModel)")
                        .foregroundStyle(Color.speakHumanAmber.opacity(0.9))
                }
            }
        }
        .font(.speakMonoFace(.caption))
        .lineLimit(1)
        .frame(height: PlaygroundMetrics.colophonHeight, alignment: .leading)
        .opacity(opacity)
    }

    private var separator: some View {
        Text("·").foregroundStyle(Color.speakMica.opacity(0.5))
    }

    private var opacity: Double {
        guard receipt != nil else { return 0 }
        return isRevealed ? 1.0 : 0.45
    }

    /// Tokens per second, derived for display only. Nil when the latency is too
    /// small to make the figure meaningful.
    private func throughput(_ receipt: ProvenanceReceipt) -> String? {
        guard receipt.latencyMS > 50, receipt.completionTokens > 0 else { return nil }
        let perSecond = Double(receipt.completionTokens) / (Double(receipt.latencyMS) / 1000.0)
        return String(format: "%.0f tok/s", perSecond)
    }
}

// MARK: - Streaming turn

/// The in-flight response. The transport hands us uneven bursts; this re-paces
/// them into an even flow of ink that always converges on the true text, so when
/// the stream finishes and a finished paragraph replaces this view, nothing pops.
struct PlaygroundStreamingTurn: View {
    let text: String

    @State private var revealed = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Cadence tick. [decision: 30ms ≈ 33 fps — fast enough to read as ink
    /// arriving, slow enough that the document is not re-laid-out every frame.]
    private let cadence = Timer.publish(every: 0.03, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: SpeakSpacing.sm) {
            if visible.isEmpty {
                PlaygroundWaitingCaret()
            } else {
                inkedText
            }

            // Reserve the colophon's line now, so the finished turn is the same
            // height as this one and the swap is invisible.
            Color.clear.frame(height: PlaygroundMetrics.colophonHeight)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, SpeakSpacing.xs)
        .onReceive(cadence) { _ in advance() }
    }

    /// The revealed prose plus an inline caret, as one attributed run so the
    /// caret sits on the text's own baseline at the true end of the last line.
    /// Typography here must match `PlaygroundTurn.response` exactly — same face,
    /// same leading — or the hand-off to the finished paragraph would reflow.
    private var inkedText: some View {
        Text(inked)
            .font(.speakBody(.body))
            .lineSpacing(PlaygroundMetrics.proseLeading)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var inked: AttributedString {
        var prose = AttributedString(visible)
        prose.foregroundColor = Color.speakBone

        var caret = AttributedString("▌")
        caret.foregroundColor = Color.speakAgentViolet

        prose.append(caret)
        return prose
    }

    private var visible: String {
        String(text.prefix(revealed))
    }

    /// Converge on the true length rather than run at a fixed rate: close a third
    /// of the remaining gap each tick, never less than one character.
    private func advance() {
        let target = text.count
        if revealed > target { revealed = target }
        guard revealed < target else { return }

        if reduceMotion {
            revealed = target
            return
        }
        revealed += max(1, (target - revealed) / 3)
    }
}

/// The pre-first-token state: a standalone caret, blinking the way a terminal
/// waits. Only ever shown when there is no text for it to sit beside.
struct PlaygroundWaitingCaret: View {
    @State private var isDim = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        RoundedRectangle(cornerRadius: 1, style: .continuous)
            .fill(Color.speakAgentViolet)
            .frame(width: 2, height: 18)
            .opacity(isDim ? 0.15 : 1.0)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 0.55).repeatForever(autoreverses: true)) {
                    isDim = true
                }
            }
            .accessibilityLabel("Waiting for the model")
    }
}

// MARK: - Empty state

/// The blank page. Editorial rather than apologetic: it states what this surface
/// is, then offers three ways in.
struct PlaygroundEmptyState: View {
    let onPick: (String) -> Void

    /// [decision: three openers that each demonstrate a different capability —
    /// composition, transformation, reasoning — without pretending to be a chatbot.]
    private static let starters = [
        "Rewrite this paragraph so it sounds like I actually meant it.",
        "What's the smallest change that would make this idea work?",
        "Draft a short release note for a feature that removes a setting."
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: SpeakSpacing.md) {
            Text("The agent writes here.")
                .font(.speakDisplay(.title))
                .foregroundStyle(Color.speakBone)

            Text("Everything below streams from a model running on this machine. "
                 + "No account, no network, no transcript leaving the Mac. "
                 + "Each answer carries a receipt saying which engine produced it.")
                .font(.speakBody(.base))
                .foregroundStyle(Color.speakMica)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 520, alignment: .leading)

            PlaygroundHairline()
                .frame(maxWidth: 520)
                .padding(.vertical, SpeakSpacing.xs)

            VStack(alignment: .leading, spacing: 2) {
                ForEach(Self.starters, id: \.self) { starter in
                    PlaygroundStarterRow(text: starter) { onPick(starter) }
                }
            }
        }
        .padding(.top, SpeakSpacing.xl + SpeakSpacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// One suggested opener. Loads the composer rather than firing — the user still
/// presses send, so nothing is ever spoken on their behalf.
struct PlaygroundStarterRow: View {
    let text: String
    let action: () -> Void

    @State private var isHovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: SpeakSpacing.sm) {
                Text("↳")
                    .font(.speakMonoFace(.caption))
                    .foregroundStyle(Color.speakHumanAmber.opacity(isHovering ? 0.9 : 0.5))

                Text(text)
                    .font(.speakBody(.base))
                    .foregroundStyle(isHovering ? Color.speakBone : Color.speakMica)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, SpeakSpacing.sm)
            .padding(.vertical, 6)
            .frame(maxWidth: 520, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.speakHumanAmber.opacity(isHovering ? 0.06 : 0))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(SpeakMotion.micro(reduceMotion: reduceMotion)) { isHovering = hovering }
        }
    }
}
