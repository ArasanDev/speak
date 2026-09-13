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
                .font(model.activeStreamText.isEmpty ? .speakBody(.caption) : .speakMonoFace(.caption))
                .foregroundStyle(Color.speakBone)
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
                .foregroundStyle(block.isPolished ? Color.speakBone : Color.speakMica.opacity(0.75))
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

/// The `.processing` CENTER LANE inside the shared capsule-bar frame.
/// Felt-speed (input-felt-speed.md §3.3): when the raw transcript is available
/// (`settlingText` non-empty) we show it marked provisional — dimmed + italic,
/// with a small spinner — instead of a blank "Cleaning up…" spinner. The user
/// sees their words the moment they stop speaking. This is NOT capture, so it
/// never lights `onAir` (frontend-identity.md, frozen).
///
/// Owns only the lane content: the right zone carries the spinner, and the
/// header row carries the close button. The lane is bounded — the text is
/// line-limited and the parent clips it, so it can never cross a hairline.
struct SettlingProcessingContent: View {
    let model: OverlayViewModel
    let revealTextWhileProcessing: Bool

    /// Same line budget as the listening lane — the provisional text occupies
    /// the identical bounded column it was captured in.
    private static let lineBudget = 3

    var body: some View {
        Group {
            if revealTextWhileProcessing, !model.settlingText.isEmpty {
                HStack(alignment: .top, spacing: SpeakSpacing.xs) {
                    ProgressView()
                        .scaleEffect(0.7)
                        .frame(width: 16, height: 16)
                    // Provisional raw transcript — dimmed + italic to signal it's
                    // not final. The transformation (diff) replaces it on reveal.
                    Text(model.settlingText)
                        .font(.speakMonoFace(.caption))
                        .foregroundStyle(Color.speakMica.opacity(0.85))
                        .italic()
                        .lineLimit(Self.lineBudget)
                        .multilineTextAlignment(.leading)
                        .lineSpacing(2)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .accessibilityLabel("Polishing transcription: \(model.settlingText)")
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                // Escape hatch / no raw text — spinner only (matches Aurora + Settings).
                HStack(spacing: SpeakSpacing.sm) {
                    ProgressView()
                        .scaleEffect(0.7)
                        .frame(width: 16, height: 16)
                    Text(model.isCleaningUp ? "Cleaning up\u{2026}" : "Pasting\u{2026}")
                        .font(.speakBody(.caption))
                        .foregroundStyle(Color.speakMica)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .accessibilityLabel(model.isCleaningUp ? "Cleaning up transcription" : "Pasting transcription")
            }
        }
    }
}

// MARK: - Polished diff content

/// The `.done` reveal — CENTER LANE inside the shared capsule-bar frame.
/// Felt-speed (input-felt-speed.md §3.3): the AI's transformation, made
/// visible — raw → clean word diff. Canceled words get the animated
/// strikethrough, inserted words fade in, kept words stay. The user WATCHES
/// the edit happen inside the same bounded column the raw words were captured
/// in ("polish inside the line itself"). This is refinement, not capture —
/// `onAir` is never lit.
///
/// `AnimatedTranscriptView` owns an internal ScrollView, so a long diff stays
/// bounded inside the lane height instead of pushing past the lane. The right
/// zone carries the delivered ✓; the header row carries the controls.
struct PolishedDiffContent: View {
    let model: OverlayViewModel
    let cleaned: String

    var body: some View {
        AnimatedTranscriptView(rawText: model.settlingText, cleanedText: cleaned)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .accessibilityLabel("Polished transcription. \(cleaned)")
    }
}
