// App/Overlay/AnimatedTranscriptView.swift
//
// Animated streaming transcript view with diff-based word transitions.
// Extracted from TranscriptOverlayView.swift to satisfy file_length lint cap.

import SpeakCore
import SwiftUI

struct AnimatedTranscriptView: View {
    let text: String
    @State private var previousText: String = ""
    /// Internal for `@testable` access in `AnimatedTranscriptViewTests` — the resolved
    /// raw→clean diff tokens. The pure diff classification is unit-tested; the SwiftUI
    /// rendering (strikethrough animation, flow layout) is a live-visual surface.
    @State var diffTokens: [DiffToken] = []
    @State private var cleanupTask: Task<Void, Never>?

    /// Felt-speed (input-felt-speed.md §3.3): initialize from a raw→clean pair so the
    /// diff runs once on appear — canceled raw words get the animated strikethrough,
    /// inserted clean words fade in. This makes the AI's edit visible. `rawText` is the
    /// preserved provisional transcript (`settlingText`), `cleanedText` the final result.
    init(rawText: String, cleanedText: String) {
        self.text = cleanedText
        self._previousText = State(initialValue: rawText)
        self._diffTokens = State(initialValue: TextDiffResolver().resolve(raw: rawText, cleaned: cleanedText))
    }

    /// Streaming form: tracks `text` over time and diffs each update against the prior.
    init(text: String) {
        self.text = text
    }

    var body: some View {
        ScrollViewReader { _ in
            ScrollView(.vertical, showsIndicators: false) {
                FlowLayout(spacing: 4) {
                    ForEach(Array(diffTokens.enumerated()), id: \.offset) { _, token in
                        TokenView(token: token)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .onAppear {
            // For the streaming form only: initialize from raw→text when no explicit
            // raw was provided (previousText empty + tokens empty ⇒ initial resolve).
            if previousText.isEmpty && diffTokens.isEmpty && !text.isEmpty {
                let resolver = TextDiffResolver()
                diffTokens = resolver.resolve(raw: "", cleaned: text)
            }
        }
        .onChange(of: text) { _, newText in
            let resolver = TextDiffResolver()
            let tokens = resolver.resolve(raw: previousText, cleaned: newText)

            withAnimation(.easeInOut(duration: 0.2)) {
                diffTokens = tokens
            }

            // Clean up canceled tokens after delay
            cleanupTask?.cancel()
            cleanupTask = Task { @MainActor in
                try? await Task.sleep(for: .seconds(0.8))
                guard !Task.isCancelled else { return }
                previousText = newText
                let cleanTokens = resolver.resolve(raw: "", cleaned: newText)
                withAnimation(.easeInOut(duration: 0.2)) {
                    diffTokens = cleanTokens
                }
            }
        }
    }
}

private struct TokenView: View {
    let token: DiffToken
    @State private var progress: CGFloat = 0

    var body: some View {
        Text(token.text)
            .font(.speakMonoFace(.caption))
            .foregroundStyle(token.state == .canceled ? .secondary : .primary)
            .overlay(
                Group {
                    if token.state == .canceled {
                        AnimatedStrikethroughLine(progress: progress)
                            .stroke(Color.red, style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                            .onAppear {
                                withAnimation(.easeOut(duration: 0.2)) {
                                    progress = 1.0
                                }
                            }
                    }
                }
            )
            // Canceled words look slightly faded
            .opacity(token.state == .canceled ? 0.6 : 1.0)
    }
}

private struct FlowLayout: Layout {
    var spacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = FlowResult(in: proposal.width ?? .infinity, subviews: subviews, spacing: spacing)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = FlowResult(in: bounds.width, subviews: subviews, spacing: spacing)
        for (index, subview) in subviews.enumerated() {
            let point = result.frames[index].origin
            subview.place(at: CGPoint(x: point.x + bounds.minX, y: point.y + bounds.minY), proposal: .unspecified)
        }
    }

    struct FlowResult {
        var size: CGSize = .zero
        var frames: [CGRect] = []

        init(in maxWidth: CGFloat, subviews: Subviews, spacing: CGFloat) {
            var currentX: CGFloat = 0
            var currentY: CGFloat = 0
            var lineHeight: CGFloat = 0

            for subview in subviews {
                let size = subview.sizeThatFits(.unspecified)
                if currentX + size.width > maxWidth && currentX > 0 {
                    currentX = 0
                    currentY += lineHeight + spacing
                    lineHeight = 0
                }
                frames.append(CGRect(origin: CGPoint(x: currentX, y: currentY), size: size))
                currentX += size.width + spacing
                lineHeight = max(lineHeight, size.height)
            }
            size = CGSize(width: maxWidth, height: currentY + lineHeight)
        }
    }
}
