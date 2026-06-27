// App/Overlay/TranscriptOverlayView.swift
//
// The SwiftUI content hosted inside `TranscriptOverlayPanel`.
//
// W2.2 — VoiceInk-grade HUD rebuild:
//   • 4 visual states: .listening (live waveform + partial text),
//     .processing ("Cleaning up…" / "Pasting…" spinner),
//     .done (checkmark flash), .error (red pill + reason + retry).
//   • Live waveform: 15-bar reactive visualizer driven by `level` (W2.1).
//     Per-bar phase offset via `levelBarHeightsPhased(level:phase:)` in LevelMath.
//   • Monaco design: all text uses `Font.speakMono(...)` tokens from `SpeakTheme`.
//   • Reduce-motion: `NSWorkspace.accessibilityDisplayShouldReduceMotion` disables
//     the breathing animation and all animated transitions.
//   • VoiceOver: `accessibilityLabel` + `.accessibilityAddTraits(.updatesFrequently)`
//     on the partial-text region; state transitions post announcements via
//     `NSAccessibility.post(element:notification:)`.
//   • In-HUD cancel affordance: Escape is handled by `OverlayController`'s global
//     event monitor — the panel never becomes key (focus-steal prevention).
//
// Design tokens: all from `SpeakTheme` — no magic font names or raw hex colors.
// Bar constants are tagged [decision] with sources in benchmark.md §7.

import AppKit
import SpeakCore
import SwiftUI

// MARK: - OverlayState

/// The visual state of the recording HUD. Driven by `DictationController`
/// as the dictation lifecycle transitions.
public enum OverlayState: Sendable, Equatable {
    case listening
    case processing
    case done
    /// W2.2: an error occurred. Reason is stored separately on `OverlayViewModel.errorReason`
    /// so `OverlayState` stays payload-free and `Equatable` conformance is automatic.
    case error
}

// MARK: - OverlayViewModel

/// Observable model bridging `DictationController` → `TranscriptOverlayView`.
/// `@MainActor` because all writes come from `DictationController` (also @MainActor).
@Observable
@MainActor
final class OverlayViewModel {
    var partialText: String = ""
    var overlayState: OverlayState = .listening

    /// Elapsed seconds since the current dictation started listening.
    var elapsedSeconds: Int = 0

    /// Microphone level (0…1), smoothed RMS from `AudioCapture` (W2.1).
    /// 0.0 when idle; driven live during `.listening`.
    var level: Double = 0.0

    /// W2.2: Short error reason shown in the error pill. Nil when not in `.error` state.
    var errorReason: String?

    /// W2.2: `true` when AI cleanup will run after capture; drives "Cleaning up…" vs "Pasting…".
    /// Set at `start()` time from `DictationController.settingsStore`.
    var isCleaningUp: Bool = true
}

// MARK: - VisualEffectView

/// Thin AppKit-backed SwiftUI wrapper that applies NSVisualEffectView material.
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

// MARK: - WaveformView

/// A 15-bar waveform driven by `level` (0…1) with per-bar phase offset.
///
/// Bar heights are computed by `levelBarHeightsPhased(level:phase:barCount:…)` in
/// `LevelMath.swift` — a pure function that makes the waveform look organic while
/// remaining fully unit-testable. When `reduceMotion` is true (Accessibility setting),
/// the phase animation and idle-breathing are suppressed; bars still reflect the live
/// level value (information, not decoration).
///
/// Bar geometry decisions — all [decision] in benchmark.md §7:
///   - 15 bars: VoiceInk blueprint (competitor research W0, §0 finding #1).
///   - 2 pt width: thin "audio analyser" look, distinct from the 5-bar v0 design.
///   - 2 pt gap: breathing room; 15 × (2 + 2) = 60 pt total, fits the panel.
///   - 3 pt min height: always visible at silence — never disappears.
///   - 20 pt max height: fits the 80 pt panel with 12 pt vertical padding each side.
private struct WaveformView: View {

    let level: Double
    let isActive: Bool          // true = listening; false = silent/idle

    // [decision: 15 bars — VoiceInk blueprint, benchmark.md §7]
    private static let barCount: Int = 15
    // [decision: 2 pt bar width — thin analyser look, benchmark.md §7]
    private static let barWidth: CGFloat = 2.0
    // [decision: 2 pt gap — breathing room, 15 × 4 pt = 60 pt total, benchmark.md §7]
    private static let barGap: CGFloat  = 2.0
    // [decision: 3 pt min — always visible at silence, benchmark.md §7]
    private static let minHeight: Double = 3.0
    // [decision: 20 pt max — fits 80 pt panel, benchmark.md §7]
    private static let maxHeight: Double = 20.0

    /// Computed width of the waveform block (used by callers for `.frame(width:)`).
    static var totalWidth: CGFloat {
        CGFloat(barCount) * barWidth + CGFloat(barCount - 1) * barGap  // = 30 + 28 = 58 pt
    }

    /// Animated phase for the per-bar offset (0…1). Drives the organic waveform
    /// movement when listening. Suppressed when reduce-motion is on.
    @State private var animPhase: Double = 0.0
    /// Idle-breathing amplitude (0…1). Only used when `isActive == false` and
    /// reduce-motion is off. Suppressed when reduce-motion is on.
    @State private var breathPhase: Double = 0.0

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: Self.barGap) {
            ForEach(Array(barHeights.enumerated()), id: \.offset) { _, height in
                RoundedRectangle(cornerRadius: Self.barWidth / 2, style: .continuous)
                    .fill(barColor)
                    .frame(width: Self.barWidth, height: CGFloat(height))
            }
        }
        // [decision: 0.08 s animation — snappier than v0's 0.12 s for 15-bar feel]
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.08), value: level)
        .onAppear {
            guard !reduceMotion else { return }
            startPhaseAnimation()
            if !isActive { startBreathing() }
        }
        .onChange(of: isActive) { _, newValue in
            guard !reduceMotion else { return }
            if !newValue { startBreathing() } else { breathPhase = 0.0 }
        }
    }

    private var barColor: Color {
        isActive ? Color.primary.opacity(0.7) : Color.primary.opacity(0.35)
    }

    private var barHeights: [Double] {
        if isActive {
            return levelBarHeightsPhased(
                level: level,
                phase: animPhase,
                barCount: Self.barCount,
                minHeight: Self.minHeight,
                maxHeight: Self.maxHeight
            )
        } else {
            // Idle breathing when not active.
            let breathLevel = 0.12 + 0.12 * breathPhase   // [decision: 0.12…0.24 idle range]
            return levelBarHeightsPhased(
                level: breathLevel,
                phase: animPhase,
                barCount: Self.barCount,
                minHeight: Self.minHeight,
                maxHeight: Self.maxHeight
            )
        }
    }

    /// Advance the phase over time so adjacent bars appear to ripple.
    private func startPhaseAnimation() {
        withAnimation(
            // [decision: 1.8 s cycle — organic wave rhythm, VoiceInk-inspired feel]
            Animation.linear(duration: 1.8).repeatForever(autoreverses: false)
        ) {
            animPhase = 1.0
        }
    }

    /// Gentle idle breathing when not actively listening.
    private func startBreathing() {
        withAnimation(
            // [decision: 1.4 s breath cycle — slightly slower than active phase]
            Animation.easeInOut(duration: 1.4).repeatForever(autoreverses: true)
        ) {
            breathPhase = 1.0
        }
    }
}

// MARK: - TranscriptOverlayView

/// The visible card shown during live dictation.
/// Renders four visual states: listening, processing, done, error.
struct TranscriptOverlayView: View {
    let model: OverlayViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            // Frosted-glass background — pulls from behind the panel.
            VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            contentLayer
        }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .padding(2)  // prevent shadow clipping at the edge
        .onChange(of: model.overlayState) { _, newState in
            postAccessibilityAnnouncement(for: newState)
        }
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

        case .error:
            errorContent
        }
    }

    // MARK: - Listening state

    private var listeningContent: some View {
        HStack(alignment: .center, spacing: SpeakSpacing.sm) {
            WaveformView(level: model.level, isActive: true)
                .frame(width: WaveformView.totalWidth)
            textContent
            Text(Self.durationLabel(model.elapsedSeconds))
                .font(.speakMonoCaption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .padding(.horizontal, SpeakSpacing.md)
        .padding(.vertical, SpeakSpacing.sm + SpeakSpacing.xs)   // = 12 pt [decision]
    }

    /// Format elapsed seconds as `m:ss` for the HUD (e.g. 0:05, 1:23).
    static func durationLabel(_ seconds: Int) -> String {
        let s = max(0, seconds)
        return "\(s / 60):\(String(format: "%02d", s % 60))"
    }

    @ViewBuilder
    private var textContent: some View {
        if model.partialText.isEmpty {
            Text("Listening\u{2026}")
                .font(.speakMonoBody)
                .foregroundStyle(.secondary)
                .lineLimit(3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityLabel("Listening for speech")
                .accessibilityAddTraits(.updatesFrequently)
        } else {
            Text(model.partialText)
                .font(.speakMonoBody)
                .foregroundStyle(.primary)
                .lineLimit(3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityLabel(model.partialText)
                .accessibilityAddTraits(.updatesFrequently)
        }
    }

    // MARK: - Processing state

    private var processingContent: some View {
        HStack(spacing: SpeakSpacing.sm) {
            ProgressView()
                .scaleEffect(0.7)
                .frame(width: 16, height: 16)
            // W2.2: honest copy — "Cleaning up…" only when cleanup is actually running.
            Text(model.isCleaningUp ? "Cleaning up\u{2026}" : "Pasting\u{2026}")
                .font(.speakMonoBody)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, SpeakSpacing.md)
        .padding(.vertical, SpeakSpacing.sm + SpeakSpacing.xs)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityLabel(model.isCleaningUp ? "Cleaning up transcription" : "Pasting transcription")
    }

    // MARK: - Done state

    private var doneContent: some View {
        HStack(spacing: SpeakSpacing.sm) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.system(size: 15))
            Text("Done")
                .font(.speakMonoBody)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, SpeakSpacing.md)
        .padding(.vertical, SpeakSpacing.sm + SpeakSpacing.xs)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityLabel("Dictation complete")
    }

    // MARK: - Error state (W2.2)

    /// Red pill with a short reason string. The retry affordance is to press the
    /// hotkey again — shown in the label below the reason. Escape or tapping the
    /// hotkey dismisses the HUD (the Escape monitor is still active in error state).
    private var errorContent: some View {
        HStack(spacing: SpeakSpacing.sm) {
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(.red)
                .font(.system(size: 15))
            VStack(alignment: .leading, spacing: 2) {
                Text("Error")
                    .font(.speakMonoBody)
                    .foregroundStyle(.primary)
                if let reason = model.errorReason, !reason.isEmpty {
                    // Truncate the technical reason to one line — this is a status
                    // pill, not an alert. Full detail is in the os.Logger stream.
                    Text(reason)
                        .font(.speakMonoCaption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                Text("Press Escape or try again")
                    .font(.speakMonoCaption)
                    .foregroundStyle(Color.secondary.opacity(0.7))
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, SpeakSpacing.md)
        .padding(.vertical, SpeakSpacing.sm + SpeakSpacing.xs)
        .accessibilityLabel(accessibilityErrorLabel)
    }

    private var accessibilityErrorLabel: String {
        var label = "Dictation error."
        if let reason = model.errorReason, !reason.isEmpty {
            label += " \(reason)."
        }
        label += " Press Escape or try again."
        return label
    }

    // MARK: - VoiceOver state announcements

    /// Post a VoiceOver notification when the overlay state changes.
    /// Uses `NSAccessibility.post(element:notification:)` — the standard macOS
    /// mechanism for screen-reader state announcements from non-focused windows.
    /// [decision W2.2: announcement on every state transition so VoiceOver users
    ///  know when dictation has finished without watching the screen]
    private func postAccessibilityAnnouncement(for state: OverlayState) {
        let message: String
        switch state {
        case .listening:   message = "Listening"
        case .processing:  message = model.isCleaningUp ? "Cleaning up" : "Pasting"
        case .done:        message = "Done"
        case .error:       message = "Dictation error. Press Escape or try again."
        }
        // `NSApp` is the closest NSObject proxy for a non-key panel announcement.
        // The notification `.announcementRequested` + userInfo string is the
        // documented pattern for custom announcements.
        // [verified: NSAccessibility.NotificationUserInfoKey — macOS 26 renamed API]
        NSAccessibility.post(
            element: NSApp as AnyObject,
            notification: .announcementRequested,
            userInfo: [
                NSAccessibility.NotificationUserInfoKey.announcement: message,
                NSAccessibility.NotificationUserInfoKey.priority: NSAccessibilityPriorityLevel.high.rawValue
            ]
        )
    }
}

// MARK: - Preview

// HONESTY BOUNDARY: these previews verify *content layout* only (text, waveform
// bars, icons, padding). They do NOT verify panel/window-server behavior:
// floating-over-other-apps, bottom-center positioning, `.nonactivatingPanel`,
// `canBecomeKey=false`, or hide-on-done timing — those are irreducibly live.

#if DEBUG
/// Listening — placeholder state. No partial text; shows idle waveform.
#Preview("Listening — placeholder") {
    let model = OverlayViewModel()
    model.overlayState = .listening
    model.partialText = ""
    model.level = 0.0
    return TranscriptOverlayView(model: model)
        .frame(width: 340, height: 60)
}

/// Listening — with live level (mid volume). 15 bars reactive to 0.6 level.
#Preview("Listening — live level 0.6") {
    let model = OverlayViewModel()
    model.overlayState = .listening
    model.partialText = "the quick brown fox"
    model.level = 0.6
    return TranscriptOverlayView(model: model)
        .frame(width: 340, height: 60)
}

/// Processing — cleanup spinner. Shows "Cleaning up…" (cleanup on).
#Preview("Processing — cleanup on") {
    let model = OverlayViewModel()
    model.overlayState = .processing
    model.isCleaningUp = true
    return TranscriptOverlayView(model: model)
        .frame(width: 340, height: 60)
}

/// Processing — paste spinner. Shows "Pasting…" (cleanup off).
#Preview("Processing — cleanup off") {
    let model = OverlayViewModel()
    model.overlayState = .processing
    model.isCleaningUp = false
    return TranscriptOverlayView(model: model)
        .frame(width: 340, height: 60)
}

/// Done — checkmark confirmation.
#Preview("Done") {
    let model = OverlayViewModel()
    model.overlayState = .done
    return TranscriptOverlayView(model: model)
        .frame(width: 340, height: 60)
}

/// Error — red pill with reason. W2.2 new state.
#Preview("Error") {
    let model = OverlayViewModel()
    model.overlayState = .error
    model.errorReason = "Speech engine unavailable"
    return TranscriptOverlayView(model: model)
        .frame(width: 340, height: 60)
}

/// Error — no reason (engine didn't provide one).
#Preview("Error — no reason") {
    let model = OverlayViewModel()
    model.overlayState = .error
    model.errorReason = nil
    return TranscriptOverlayView(model: model)
        .frame(width: 340, height: 60)
}
#endif
