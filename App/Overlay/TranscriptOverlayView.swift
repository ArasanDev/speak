// App/Overlay/TranscriptOverlayView.swift
//
// The SwiftUI content hosted inside `TranscriptOverlayPanel`.
//
// Visual states (Phase C):
//   • .listening  — live level meter + partial text ("Listening…" before first partial).
//   • .processing — "Cleaning up…" label + a ProgressView spinner.
//   • .done       — brief checkmark, then panel hides.
//   (Panel is hidden on idle/error — this view is never shown then.)
//
// Level meter:
//   `level: Double` (0…1) is the wire point for a future real mic-RMS feed from
//   the AVAudioEngine tap (builder-audio-stt + builder-engine seam — tracked follow-up).
//   For this phase the bars use a neutral idle-breathing animation that is clearly
//   decorative, not a VU meter. Nothing in the animation looks mic-reactive.
//
// Design intent (v0 — functional first, polish at P8):
//   - Translucent rounded card with vibrancy, small drop shadow (panel provides).
//   - No hard-coded colors; uses `VisualEffectView` + system materials.

import SwiftUI
import AppKit
import SpeakCore

// MARK: - OverlayState

/// The visual state of the recording HUD. Driven by `DictationController`
/// as the dictation lifecycle transitions (listening → processing → done).
public enum OverlayState: Sendable {
    case listening
    case processing
    case done
}

// MARK: - OverlayViewModel

/// Observable model bridging `DictationController` → `TranscriptOverlayView`.
/// `@MainActor` because all writes come from `DictationController` (also @MainActor).
@MainActor
final class OverlayViewModel: ObservableObject {
    @Published var partialText: String = ""
    @Published var overlayState: OverlayState = .listening

    /// Elapsed seconds since the current dictation started listening. Driven by a 1 Hz
    /// timer in `OverlayController`; reset to 0 on each `start()`. Shown in the HUD so the
    /// user sees how long they've been dictating (verified Wispr HUD detail).
    @Published var elapsedSeconds: Int = 0

    /// Microphone level (0…1), linearized from dB via `pow(10, dB/20)`.
    /// Currently unused as a live feed — the bars run a neutral idle animation.
    /// Wire this to the AVAudioEngine RMS output when the real feed is plumbed
    /// (builder-audio-stt + builder-engine cross-seam work, deferred from Phase C).
    /// Pure math: `levelLinear(fromDB:)`, `levelSmoothed(previous:target:)`,
    /// `levelBarHeights(level:barCount:minHeight:maxHeight:)` live in
    /// `SpeakCore/Overlay/LevelMath.swift` and are unit-tested in `OverlayLevelTests`.
    @Published var level: Double = 0.0
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

// MARK: - LevelMeterView

/// A small N-bar waveform driven by `level` (0…1).
///
/// Bars use a neutral idle-breathing animation in the listening state. This animation
/// is deliberately uniform (all bars breathe together) so it does not look like a VU
/// meter. Once the real mic-level feed is plumbed from the AVAudioEngine tap, `level`
/// will be set per-frame and the breathing animation will be removed.
private struct LevelMeterView: View {
    let level: Double
    let isActive: Bool   // true = listening (use level); false = idle breathing

    // [decision: 5 bars — Handy waveform reference; fits HUD width. benchmark.md §7.]
    private static let barCount: Int = 5
    // [decision: 3 pt min, 20 pt max — fits 80 pt panel height. benchmark.md §7.]
    private static let minBarHeight: Double = 3.0
    private static let maxBarHeight: Double = 20.0
    // [decision: 2 pt bar width — narrow waveform look, matches Handy style.]
    private static let barWidth: CGFloat = 3.0
    // [decision: 3 pt gap — breathing room between bars.]
    private static let barGap: CGFloat = 3.0

    /// Breathing phase for the idle animation (0…1).
    @State private var breathPhase: Double = 0.0

    var body: some View {
        HStack(spacing: Self.barGap) {
            ForEach(Array(barHeights.enumerated()), id: \.offset) { _, height in
                RoundedRectangle(cornerRadius: Self.barWidth / 2, style: .continuous)
                    .fill(Color.primary.opacity(0.6))
                    .frame(width: Self.barWidth, height: CGFloat(height))
            }
        }
        .animation(.easeInOut(duration: 0.12), value: level)   // [decision: 0.12 s — snappy but not jarring]
        .onAppear { startBreathing() }
    }

    private var barHeights: [Double] {
        if isActive {
            // Real or placeholder level drives bar heights.
            return levelBarHeights(
                level: level,
                barCount: Self.barCount,
                minHeight: Self.minBarHeight,
                maxHeight: Self.maxBarHeight
            )
        } else {
            // Idle breathing: uniform gentle pulse. [decision: 0.3 amplitude at rest —
            // clearly decorative, not mic-reactive.]
            let breathLevel = 0.15 + 0.15 * breathPhase   // [decision: 0.15…0.30 range]
            return levelBarHeights(
                level: breathLevel,
                barCount: Self.barCount,
                minHeight: Self.minBarHeight,
                maxHeight: Self.maxBarHeight
            )
        }
    }

    private func startBreathing() {
        withAnimation(
            Animation
                // [decision: 1.2 s cycle — natural breath rhythm, clearly not mic-reactive]
                .easeInOut(duration: 1.2)
                .repeatForever(autoreverses: true)
        ) {
            breathPhase = 1.0
        }
    }
}

// MARK: - TranscriptOverlayView

/// The visible card shown during live dictation.
/// Renders three visual states: listening (level meter + text), processing (spinner),
/// and done (checkmark). The panel hides on idle/error — this view is not shown then.
struct TranscriptOverlayView: View {
    @ObservedObject var model: OverlayViewModel

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
        switch model.overlayState {
        case .listening:
            listeningContent
        case .processing:
            processingContent
        case .done:
            doneContent
        }
    }

    // MARK: - Listening state

    private var listeningContent: some View {
        HStack(alignment: .center, spacing: 10) {
            LevelMeterView(level: model.level, isActive: true)
                .frame(width: 27)   // 5 bars × 3 pt + 4 gaps × 3 pt = 27 pt [decision]
            textContent
            Text(Self.durationLabel(model.elapsedSeconds))
                .font(.system(size: 12, weight: .regular, design: .monospaced))
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    /// Format elapsed seconds as `m:ss` for the HUD (e.g. 0:05, 1:23).
    static func durationLabel(_ seconds: Int) -> String {
        let s = max(0, seconds)
        return "\(s / 60):\(String(format: "%02d", s % 60))"
    }

    @ViewBuilder
    private var textContent: some View {
        if model.partialText.isEmpty {
            // Empty listening state: placeholder before first partial arrives.
            Text("Listening\u{2026}")
                .font(.system(size: 13, weight: .regular, design: .default))
                .foregroundStyle(.secondary)
                .lineLimit(3)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            // In-flight: live partial transcript.
            Text(model.partialText)
                .font(.system(size: 13, weight: .regular, design: .default))
                .foregroundStyle(.primary)
                .lineLimit(3)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Processing state

    private var processingContent: some View {
        HStack(spacing: 8) {
            ProgressView()
                .scaleEffect(0.7)
                .frame(width: 16, height: 16)
            Text("Cleaning up\u{2026}")
                .font(.system(size: 13, weight: .regular, design: .default))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Done state

    private var doneContent: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.system(size: 15))
            Text("Done")
                .font(.system(size: 13, weight: .regular, design: .default))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Preview

// HONESTY BOUNDARY: these previews verify *content layout* only (text, meter
// bars, icons, padding). They do NOT verify panel/window-server behavior:
// floating-over-other-apps, bottom-center positioning, `.nonactivatingPanel`,
// `canBecomeKey=false`, or hide-on-done timing — those are irreducibly live per
// docs/agent-tooling.md §3.1 and remain [deferred — human verification].

#if DEBUG
/// Listening — placeholder state. No partial text yet; shows "Listening…" label
/// and idle-breathing level bars. This is the first visual a user sees on hotkey press.
#Preview("Listening — placeholder") {
    let model = OverlayViewModel()
    model.overlayState = .listening
    model.partialText = ""
    model.level = 0.0
    return TranscriptOverlayView(model: model)
        .frame(width: 340, height: 60)
}

/// Listening — with partial transcript. Shows in-flight recognized text plus
/// mid-range level bars (0.6 simulates a normal speaking volume). [decision: 0.6 = mid]
#Preview("Listening — with partial text") {
    let model = OverlayViewModel()
    model.overlayState = .listening
    model.partialText = "the quick brown fox"
    model.level = 0.6
    return TranscriptOverlayView(model: model)
        .frame(width: 340, height: 60)
}

/// Processing — cleanup spinner. Shown after audio capture ends while
/// Foundation Models cleans the transcript. No text or meter bars visible.
#Preview("Processing") {
    let model = OverlayViewModel()
    model.overlayState = .processing
    return TranscriptOverlayView(model: model)
        .frame(width: 340, height: 60)
}

/// Done — checkmark confirmation. Shown briefly before the panel hides.
#Preview("Done") {
    let model = OverlayViewModel()
    model.overlayState = .done
    return TranscriptOverlayView(model: model)
        .frame(width: 340, height: 60)
}
#endif
