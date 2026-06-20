// App/Overlay/TranscriptOverlayView.swift
//
// The SwiftUI content hosted inside `TranscriptOverlayPanel`.
//
// Three view states:
//   • Empty (listening, no partials yet) — "Listening…" placeholder with a
//     pulsing dot, so the user has immediate feedback that the mic is live.
//   • In-flight (partials arriving)      — live partial text in a rounded card.
//   • (Error / done)                     — panel is hidden; this view is never shown.
//
// Design intent (v0 — functional first, polish at P8):
//   - Translucent rounded card with vibrancy, small drop shadow (panel provides).
//   - Subtle "listening" pulse on the mic dot (driven by @State animation).
//   - Partial text in a secondary-font color — it's *in progress*, not finished.
//   - No hard-coded colors; uses `VisualEffectView` + system materials.

import SwiftUI
import AppKit

// MARK: - OverlayViewModel

/// Observable model bridging `DictationController` → `TranscriptOverlayView`.
/// `@MainActor` because all writes come from `DictationController` (also @MainActor).
@MainActor
final class OverlayViewModel: ObservableObject {
    @Published var partialText: String = ""
}

// MARK: - VisualEffectView

/// Thin AppKit-backed SwiftUI wrapper that applies NSVisualEffectView material.
/// Used to give the overlay a frosted-glass appearance consistent with macOS.
private struct VisualEffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = material
        v.blendingMode = blendingMode
        v.state = .active
        return v
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}

// MARK: - TranscriptOverlayView

/// The visible card shown during live dictation.
struct TranscriptOverlayView: View {
    @ObservedObject var model: OverlayViewModel

    /// Animation state for the "listening" pulse dot.
    @State private var isPulsing: Bool = false

    var body: some View {
        ZStack {
            // Frosted-glass background — pulls from behind the panel.
            VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            contentLayer
        }
        // Outer shadow is provided by the NSPanel (`hasShadow = true`).
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .padding(2)  // prevent shadow clipping at the edge
    }

    @ViewBuilder
    private var contentLayer: some View {
        HStack(alignment: .top, spacing: 10) {
            listeningDot
            textContent
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    // MARK: - Listening dot

    private var listeningDot: some View {
        Circle()
            .fill(Color.red)
            .frame(width: 8, height: 8)
            .opacity(isPulsing ? 0.4 : 1.0)
            .animation(
                Animation
                    .easeInOut(duration: 0.8)   // [decision] 0.8 s gives a natural breath rhythm
                    .repeatForever(autoreverses: true),
                value: isPulsing
            )
            .onAppear { isPulsing = true }
            .onDisappear { isPulsing = false }
            .padding(.top, 4)  // align with cap-height of the text
    }

    // MARK: - Text content

    @ViewBuilder
    private var textContent: some View {
        if model.partialText.isEmpty {
            // Empty state: "Listening…" placeholder shown while awaiting first partial.
            Text("Listening\u{2026}")
                .font(.system(size: 13, weight: .regular, design: .default))
                .foregroundStyle(.secondary)
                .lineLimit(3)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            // In-flight state: display the running partial transcript.
            Text(model.partialText)
                .font(.system(size: 13, weight: .regular, design: .default))
                .foregroundStyle(.primary)
                .lineLimit(3)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
