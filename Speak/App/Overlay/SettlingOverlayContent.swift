// App/Overlay/SettlingOverlayContent.swift
//
// Felt-speed (input-felt-speed.md §3.3) overlay content — the "settling" provisional
// state and the raw→clean diff reveal. Extracted from TranscriptOverlayView.swift to
// satisfy file_length/type_body_length lint caps — pure code motion, no behavior change.
//
// The two pieces:
//   - `SettlingProcessingContent`: the `.processing` window with the raw transcript
//     preserved (marked provisional) instead of a blank spinner.
//   - `PolishedDiffContent`: the `.done` reveal that animates raw→clean via the word
//     diff (canceled words struck, inserted fade in).
//
// `onAir` discipline (frontend-identity.md, frozen) is preserved by construction:
// both views render only under `.processing`/`.done` — refinement is never capture.

import SpeakCore
import SwiftUI

// MARK: - Filmstrip view (horizontal block transcript)

/// The horizontal filmstrip transcript — live text left, completed blocks as
/// compact chips accumulating to the right (bounded). Desktop FIFO is off while
/// this path is on (one overflow choreography at a time).
///
/// The panel NEVER grows vertically and never scrolls. When the active streaming
/// text would overflow the char budget, it is captured as a block chip; the
/// active area keeps the remainder. Each block is sent to the live per-block AI
/// cleaner as it's captured.
///
/// Layout (locked 2026-08-04 — bounded stack, fixed panel): fixed-width center
/// lane; block count capped so oldest chips fade rather than widening the lane.
struct FilmstripView: View {
    let model: OverlayViewModel

    /// [design: cap the visible block count so the lane stays bounded. Oldest
    ///  blocks fade out past this count — the panel never grows to fit them.]
    private static let maxVisibleBlocks = 4

    var body: some View {
        HStack(spacing: SpeakSpacing.xs) {
            // The active streaming text at full size (the live capture) — the anchor.
            Text(model.activeStreamText.isEmpty ? "Listening\u{2026}" : model.activeStreamText)
                .font(.speakMono(9.5, weight: .medium))
                .foregroundStyle(.primary)
                .lineLimit(4)
                .lineSpacing(1.5)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .contentTransition(.interpolate)
                .accessibilityLabel(model.activeStreamText)

            // Bounded block lane — completed blocks, oldest first, capped count.
            HStack(spacing: 3) {
                ForEach(visibleBlocks) { block in
                    FilmstripBlockView(block: block)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .fixedSize(horizontal: true, vertical: false)
            .animation(.easeInOut(duration: 0.25), value: visibleBlocks)
        }
        .animation(.easeInOut(duration: 0.25), value: model.activeStreamText)
    }

    /// The newest `maxVisibleBlocks` blocks. Oldest beyond the cap fade out —
    /// the lane never grows, the panel never moves. [design: bounded stack]
    private var visibleBlocks: [FilmstripBlock] {
        Array(model.filmstripBlocks.suffix(Self.maxVisibleBlocks))
    }
}

/// One miniaturized filmstrip block. Renders the display text (cleaned when the live
/// per-block AI has finished, else raw) compactly, with a "Polishing…" affordance
/// while the AI pass is in flight. Progress is the raw→cleaned flip: a polishing
/// block is dim, a polished block shows the cleaned words at readable weight.
/// [design: compact but legible — the flip raw→cleaned is the visible proof of work.]
private struct FilmstripBlockView: View {
    let block: FilmstripBlock

    var body: some View {
        HStack(spacing: 3) {
            if block.isPolishing {
                ProgressView()
                    .controlSize(.mini)
                    .scaleEffect(0.6)
                    .frame(width: 8, height: 8)
            }
            Text(block.displayText)
                .font(.system(size: 9, weight: block.isPolished ? .medium : .regular, design: .monospaced))
                .foregroundStyle(block.isPolished ? Color.primary : Color.secondary.opacity(0.75))
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 1)
        .frame(maxWidth: 150)  // [decision: compact chip cap — snapshot, not a page]
        .fixedSize(horizontal: true, vertical: false)
        .opacity(block.isPolished ? 1.0 : 0.85)
        .accessibilityLabel(block.displayText)
        .accessibilityValue(block.isPolishing ? "Polishing" : "Polished")
    }
}

// MARK: - Settling processing content

/// The `.processing` window. Felt-speed (input-felt-speed.md §3.3): when the raw
/// transcript is available (`settlingText` non-empty) we show it marked provisional —
/// a small spinner + "Polishing…" — instead of a blank "Cleaning up…" spinner. The
/// user sees their words the moment they stop speaking. This is NOT capture, so it
/// never lights `onAir` (frontend-identity.md, frozen).
struct SettlingProcessingContent: View {
    let model: OverlayViewModel
    let revealTextWhileProcessing: Bool

    var body: some View {
        Group {
            if revealTextWhileProcessing, !model.settlingText.isEmpty {
                HStack(alignment: .top, spacing: SpeakSpacing.sm) {
                    ProgressView()
                        .scaleEffect(0.7)
                        .frame(width: 16, height: 16)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(model.isCleaningUp ? "Polishing\u{2026}" : "Pasting\u{2026}")
                            .font(.speakMonoBody)
                            .foregroundStyle(.secondary)
                        // Provisional raw transcript — dimmed + italic to signal it's
                        // not final. The transformation (diff) replaces it on reveal.
                        Text(model.settlingText)
                            .font(.speakMono(9.5, weight: .medium))
                            .foregroundStyle(.secondary.opacity(0.8))
                            .italic()
                            .lineLimit(4)
                            .multilineTextAlignment(.leading)
                            .lineSpacing(1.5)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .accessibilityLabel("Polishing transcription: \(model.settlingText)")
                    }
                    Spacer(minLength: 0)
                    closeButton
                }
                .padding(.horizontal, SpeakSpacing.md)
                .padding(.vertical, SpeakSpacing.sm + SpeakSpacing.xs)
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                // Escape hatch / no raw text — spinner only (matches Aurora + Settings).
                HStack(spacing: SpeakSpacing.sm) {
                    ProgressView()
                        .scaleEffect(0.7)
                        .frame(width: 16, height: 16)
                    Text(model.isCleaningUp ? "Cleaning up\u{2026}" : "Pasting\u{2026}")
                        .font(.speakMonoBody)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                    closeButton
                }
                .padding(.horizontal, SpeakSpacing.md)
                .padding(.vertical, SpeakSpacing.sm + SpeakSpacing.xs)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityLabel(model.isCleaningUp ? "Cleaning up transcription" : "Pasting transcription")
            }
        }
    }

    /// The same close/cancel affordance the base HUD uses.
    private var closeButton: some View {
        Button {
            model.onCancel?()
        } label: {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 12))
                .foregroundStyle(.secondary.opacity(0.8))
        }
        .buttonStyle(.plain)
        .help("Cancel dictation and hide overlay")
        .accessibilityLabel("Cancel dictation")
    }
}

// MARK: - Polished diff content

/// The `.done` reveal. Felt-speed (input-felt-speed.md §3.3): the AI's transformation,
/// made visible — raw → clean word diff. Canceled words get the animated strikethrough,
/// inserted words fade in, kept words stay. The user WATCHES the edit happen instead of
/// seeing a hard swap. This is refinement, not capture — `onAir` is never lit.
struct PolishedDiffContent: View {
    let model: OverlayViewModel
    let cleaned: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: SpeakSpacing.sm) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.system(size: 15))
                Text("Polished")
                    .font(.speakMonoBody)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                closeButton
            }
            AnimatedTranscriptView(rawText: model.settlingText, cleanedText: cleaned)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, SpeakSpacing.md)
        .padding(.vertical, SpeakSpacing.sm + SpeakSpacing.xs)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityLabel("Polished transcription. \(cleaned)")
    }

    private var closeButton: some View {
        Button {
            model.onCancel?()
        } label: {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 12))
                .foregroundStyle(.secondary.opacity(0.8))
        }
        .buttonStyle(.plain)
        .help("Dismiss")
        .accessibilityLabel("Dismiss")
    }
}
