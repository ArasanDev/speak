// App/Overlay/TranscriptOverlayView.swift
//
// The SwiftUI content hosted inside `TranscriptOverlayPanel`.
// Fluid, minimal floating pill HUD inspired by modern living audio interfaces.
//
// Decomposed for strict modularity (<800 lines):
//   • State & models in `OverlayViewModel.swift`
//   • Live reactive waveform in `OverlayWaveformView.swift`
//   • Per-dictation knob chips in `OverlayKnobsRow.swift`
//   • Provisional settling content in `SettlingOverlayContent.swift`

import AppKit
import SpeakCore
import SwiftUI

// MARK: - TranscriptOverlayView

/// The visible card shown during live dictation.
/// Renders four visual states: listening, processing, done, error.
struct TranscriptOverlayView: View {
    let model: OverlayViewModel
    let settingsStore: SettingsStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            // Inner clipped card (frosted-glass background + HUD content).
            ZStack {
                // Frosted-glass background — pulls from behind the panel.
                VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                // Subtle inner border highlight for depth
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.white.opacity(0.12), lineWidth: 0.75)

                contentLayer
            }
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: Color.black.opacity(0.18), radius: 12, x: 0, y: 6)

            // Animated border layer — switches based on settingsStore.borderAnimationStyle
            borderLayer
        }
        .padding(2)  // prevent shadow clipping at the edge
        .onChange(of: model.overlayState) { _, newState in
            postAccessibilityAnnouncement(for: newState)
        }
    }

    @ViewBuilder
    private var borderLayer: some View {
        switch settingsStore.borderAnimationStyle {
        case .none:
            EmptyView()

        case .fullGlow:
            AnimatedGradientBorder(
                shape: RoundedRectangle(cornerRadius: 16, style: .continuous),
                state: model.overlayState,
                level: model.level,
                reduceMotion: reduceMotion
            )

        case .edgeFlow:
            EdgeFlowBorder(
                shape: RoundedRectangle(cornerRadius: 16, style: .continuous),
                state: model.overlayState,
                level: model.level,
                speed: settingsStore.borderFlowSpeed,
                count: settingsStore.borderFlowCount,
                reduceMotion: reduceMotion
            )
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
        Group {
            if let loopManager = model.conversationLoopManager {
                ConversationOverlayView(
                    loopManager: loopManager,
                    model: model,
                    settingsStore: settingsStore
                )
            } else {
                calmListeningRow
                    .padding(.horizontal, SpeakSpacing.md)
                    .padding(.vertical, SpeakSpacing.sm + SpeakSpacing.xs)   // = 12 pt [decision]
            }
        }
    }

    /// Layout (locked 2026-08-06 — 3-line FIFO window):
    ///   [ waveform ] [ last ≤3 lines of speech — CENTER ] [ timer ] [ customize ] [ close ]
    private var calmListeningRow: some View {
        HStack(alignment: .center, spacing: SpeakSpacing.sm) {
            WaveformView(level: model.level, isActive: true)
                .frame(width: WaveformView.totalWidth)

            fifoWindowContent
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(Self.durationLabel(model.elapsedSeconds))
                .font(.speakMonoCaption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
            customizeButton
            closeButton
        }
        .frame(maxWidth: .infinity)
    }

    /// The fixed 3-line capture window. Shows `windowText` (FIFO remainder), not
    /// the full accumulated transcript — so long dictation flows instead of growing.
    @ViewBuilder
    private var fifoWindowContent: some View {
        if model.windowText.isEmpty {
            Text("Listening\u{2026}")
                .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(3)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .accessibilityLabel("Listening for speech")
                .accessibilityAddTraits(.updatesFrequently)
        } else {
            Text(model.windowText)
                .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                .foregroundStyle(.primary)
                .lineLimit(3)
                .multilineTextAlignment(.leading)
                .lineSpacing(2)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .contentTransition(.interpolate)
                .animation(.easeOut(duration: 0.2), value: model.windowText)
                .accessibilityLabel(model.windowText)
                .accessibilityAddTraits(.updatesFrequently)
        }
    }

    /// The base HUD's single button: opens the separate `CodingCustomizationPanel`.
    private var customizeButton: some View {
        Button {
            model.isCodingPanelOpen.toggle()
            model.onCodingPanelOpenChanged?(model.isCodingPanelOpen)
        } label: {
            Image(systemName: "slider.horizontal.3")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Customize the prompt for this dictation")
        .accessibilityAddTraits(model.isCodingPanelOpen ? [.isSelected, .isButton] : .isButton)
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
        .help("Cancel dictation and hide overlay")
        .accessibilityLabel("Cancel dictation")
    }

    /// Format elapsed seconds as `m:ss` for the HUD (e.g. 0:05, 1:23).
    static func durationLabel(_ seconds: Int) -> String {
        let s = max(0, seconds)
        return "\(s / 60):\(String(format: "%02d", s % 60))"
    }

    // MARK: - Processing state

    private var processingContent: some View {
        SettlingProcessingContent(
            model: model,
            revealTextWhileProcessing: settingsStore.revealTextWhileProcessing
        )
    }

    // MARK: - Done state

    private var doneContent: some View {
        Group {
            if model.isDiffTransforming, let cleaned = model.revealedText {
                PolishedDiffContent(model: model, cleaned: cleaned)
            } else {
                HStack(spacing: SpeakSpacing.sm) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.system(size: 15))
                    Text("Done")
                        .font(.speakMonoBody)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                    if model.onReadback != nil {
                        Button {
                            model.onReadback?()
                        } label: {
                            Image(systemName: "speaker.wave.2")
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("Read this back aloud")
                        .accessibilityLabel("Read the transcript back aloud")
                    }
                    if model.onReclean != nil {
                        Button {
                            model.onReclean?()
                        } label: {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("Re-clean with current settings")
                    }
                }
                .padding(.horizontal, SpeakSpacing.md)
                .padding(.vertical, SpeakSpacing.sm + SpeakSpacing.xs)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityLabel("Dictation complete")
            }
        }
    }

    // MARK: - Error state (W2.2)

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
            closeButton
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

    private func postAccessibilityAnnouncement(for state: OverlayState) {
        let message: String
        switch state {
        case .listening:   message = "Listening"
        case .processing:  message = model.isCleaningUp ? "Cleaning up" : "Pasting"
        case .done:        message = "Done"
        case .error:       message = "Dictation error. Press Escape or try again."
        }
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

#if DEBUG
#Preview("Listening — placeholder") {
    let model = OverlayViewModel()
    model.overlayState = .listening
    model.partialText = ""
    model.level = 0.0
    return TranscriptOverlayView(model: model, settingsStore: SettingsStore())
        .frame(width: 340, height: 60)
}

#Preview("Listening — live level 0.6") {
    let model = OverlayViewModel()
    model.overlayState = .listening
    model.partialText = "the quick brown fox"
    model.level = 0.6
    return TranscriptOverlayView(model: model, settingsStore: SettingsStore())
        .frame(width: 340, height: 60)
}

#Preview("Processing — cleanup on") {
    let model = OverlayViewModel()
    model.overlayState = .processing
    model.isCleaningUp = true
    return TranscriptOverlayView(model: model, settingsStore: SettingsStore())
        .frame(width: 340, height: 60)
}

#Preview("Processing — cleanup off") {
    let model = OverlayViewModel()
    model.overlayState = .processing
    model.isCleaningUp = false
    return TranscriptOverlayView(model: model, settingsStore: SettingsStore())
        .frame(width: 340, height: 60)
}

#Preview("Done") {
    let model = OverlayViewModel()
    model.overlayState = .done
    return TranscriptOverlayView(model: model, settingsStore: SettingsStore())
        .frame(width: 340, height: 60)
}

#Preview("Done — readback + re-clean") {
    let model = OverlayViewModel()
    model.overlayState = .done
    model.onReadback = {}
    model.onReclean = {}
    return TranscriptOverlayView(model: model, settingsStore: SettingsStore())
        .frame(width: 340, height: 60)
}

#Preview("Error") {
    let model = OverlayViewModel()
    model.overlayState = .error
    model.errorReason = "Speech engine unavailable"
    return TranscriptOverlayView(model: model, settingsStore: SettingsStore())
        .frame(width: 340, height: 60)
}

#Preview("Error — no reason") {
    let model = OverlayViewModel()
    model.overlayState = .error
    model.errorReason = nil
    return TranscriptOverlayView(model: model, settingsStore: SettingsStore())
        .frame(width: 340, height: 60)
}

#Preview("Listening — customize panel open") {
    let model = OverlayViewModel()
    model.overlayState = .listening
    model.partialText = "open the customization panel"
    model.isCodingPanelOpen = true
    return TranscriptOverlayView(model: model, settingsStore: SettingsStore())
        .frame(width: 340, height: 60)
}
#endif
