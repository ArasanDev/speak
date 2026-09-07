// App/Dashboard/Panes/AgentPlaygroundSurfaces.swift
//
// The view layer of the Agent Playground. Split out of AgentPlaygroundView.swift
// so the pane's root + view-model stay legible and no single type body grows past
// the lint ceiling.
//
// DESIGN THESIS — "an agent co-authoring in my buffer", not a chatbot:
//
// 1. ONE READING COLUMN. Everything — masthead, document, composer — is bound to
//    the same measure (`PlaygroundMetrics.measure`). The eye never re-anchors.
// 2. TWO VOICES, TWO FACES. The human instruction is a dimmed SF Pro command line
//    behind an amber rule (warm = human). The model's answer is full-width SF Pro
//    body at the 15pt step with generous leading — composed prose, not a bubble.
//    SF Mono is reserved for *data*: engine room, colophon, token counts.
// 3. THE COLOPHON IS A WINE LABEL. Provenance sits at the foot of each response at
//    half opacity, rising to full on hover. Its height is always reserved, so the
//    receipt arriving a beat after the text (the stream finishes before the
//    provenance channel drains) never shifts the page.
// 4. STREAMING IS CADENCE, NOT CHUNKS. The transport delivers bursts; the view
//    re-paces them into an even ink flow that always *converges* on the true text,
//    so the hand-off to the finished paragraph is invisible.
// 5. MOTION ANSWERS TO REDUCE MOTION. Reveal becomes instant, the caret stops
//    blinking, the composer's flow border freezes.
//
// Palette discipline: `speakOnAir`/`speakFlowOnAir` are the microphone tally and
// are deliberately absent here — nothing in this pane touches the mic.

import Foundation
import SpeakCore
import SpeakLLM
import SwiftUI

// MARK: - Metrics

/// The pane's layout constants. One place, so the masthead, the document column
/// and the composer stay on the same measure and rhythm.
enum PlaygroundMetrics {
    /// The reading measure. [decision: 720pt ≈ 90 characters at the 15pt step —
    /// the upper bound of comfortable line length for composed prose.]
    static let measure: CGFloat = 720

    /// Vertical air above a new human instruction — the paragraph break that
    /// separates one exchange from the next. [decision: 32pt]
    static let turnGap: CGFloat = 32

    /// Leading for model prose at the 15pt step. [decision: 7pt → ~1.45 line height]
    static let proseLeading: CGFloat = 7

    /// Reserved height for the provenance colophon so a late receipt never
    /// reflows the document. [decision: matches the 11pt mono line box]
    static let colophonHeight: CGFloat = 14

    /// Corner radius for the composer card, matching the dashboard super-ellipse.
    static let cardRadius: CGFloat = 12
}

// MARK: - Hairline

/// The single hairline used throughout the pane — `Divider()` picks up a system
/// gray that fights the two-temperature palette.
struct PlaygroundHairline: View {
    var body: some View {
        Rectangle()
            .fill(Color.speakCardBorder)
            .frame(height: 1)
    }
}

// MARK: - Masthead

/// Title, subtitle and the engine room, on one baseline. The engine chips double
/// as the model selector — the health readout and the choice are the same object,
/// which is what an engine room is.
struct PlaygroundMasthead: View {
    @ObservedObject var viewModel: PlaygroundViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: SpeakSpacing.md) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Playground")
                        .font(.speakDisplay(.title))
                        .foregroundStyle(Color.speakBone)

                    Text("Local inference · streaming · nothing leaves this Mac")
                        .font(.speakBody(.caption))
                        .foregroundStyle(Color.speakMica)
                }

                Spacer(minLength: SpeakSpacing.md)

                PlaygroundEngineRoom(viewModel: viewModel)
            }
            .frame(maxWidth: PlaygroundMetrics.measure, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.horizontal, SpeakSpacing.lg)
            .padding(.top, SpeakSpacing.lg)
            .padding(.bottom, SpeakSpacing.md)

            PlaygroundHairline()
        }
    }
}

// MARK: - Engine room

/// The backend health readout. Each chip is a live probe result *and* the model
/// picker: clicking one routes the next request to it.
struct PlaygroundEngineRoom: View {
    @ObservedObject var viewModel: PlaygroundViewModel

    var body: some View {
        HStack(spacing: SpeakSpacing.xs) {
            if viewModel.backends.isEmpty {
                PlaygroundEngineChip(
                    name: "probing local backends",
                    status: .unknown,
                    isSelected: false,
                    action: nil
                )
            } else {
                ForEach(viewModel.backends) { backend in
                    PlaygroundEngineChip(
                        name: backend.name,
                        status: backend.status,
                        isSelected: viewModel.selectedModel == backend.id,
                        action: { viewModel.selectedModel = backend.id }
                    )
                }
            }

            Button {
                viewModel.discoverBackends()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.speakMica)
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Re-probe local inference backends")
        }
    }
}

/// One backend: a status dot, a mono name, and — when selected — a violet ring.
struct PlaygroundEngineChip: View {
    let name: String
    let status: BackendStatus
    let isSelected: Bool
    let action: (() -> Void)?

    @State private var isHovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let chip = HStack(spacing: 6) {
            Circle()
                .fill(statusColor)
                .frame(width: 5, height: 5)

            Text(name)
                .font(.speakMonoFace(.caption))
                .foregroundStyle(isSelected ? Color.speakBone : Color.speakMica)
                .lineLimit(1)
        }
        .padding(.horizontal, SpeakSpacing.sm)
        .padding(.vertical, 5)
        .background(background)
        .overlay(ring)
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(SpeakMotion.micro(reduceMotion: reduceMotion)) { isHovering = hovering }
        }
        .help(helpText)

        if let action {
            Button(action: action) { chip }
                .buttonStyle(.plain)
        } else {
            chip
        }
    }

    private var background: some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(Color.speakAgentViolet.opacity(fillOpacity))
    }

    private var ring: some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .strokeBorder(Color.speakAgentViolet.opacity(isSelected ? 0.35 : 0), lineWidth: 1)
    }

    private var fillOpacity: Double {
        if isSelected { return 0.14 }
        if isHovering && action != nil { return 0.07 }
        return 0
    }

    private var helpText: String {
        action == nil ? "Discovering backends…" : "\(name) — \(status.rawValue). Click to route requests here."
    }

    private var statusColor: Color {
        switch status {
        case .available, .reachable:
            return Color.speakDelivered

        case .offline:
            return Color(nsColor: .systemRed).opacity(0.8)

        case .unknown:
            return Color.speakMica.opacity(0.6)
        }
    }
}
