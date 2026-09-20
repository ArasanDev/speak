// App/Overlay/HUDLaneContent.swift
//
// The lane CONTENT for the minimal-pill HUD — the header row, the
// state-dependent control cluster, the per-state lane bodies, and the
// (opt-in) animated border layer. Frame anatomy (helpers, pill frame,
// leading slot, text lane) lives in `HUDLaneViews.swift`; both files serve
// the same job: one shared pill design so a high-frequency `level` or
// `windowText` update re-evaluates only the subtree that reads it.
//
// v2 (2026-09-17): the timer merged into the header row (`LISTENING · 0:12`)
// — the dedicated timer endcap and its divider are gone. The customize
// affordance rides in the cluster for all HUD presentation now that the
// classic/Aurora styles are unified.

import SpeakCore
import SwiftUI

// MARK: - Header row

/// The header row — phase word leading, the elapsed timer riding inline
/// (`LISTENING · 0:12`), controls trailing. `overlayShowTimer` gates just
/// the `· m:ss` segment. The stop-gesture hint was removed (2026-11): the
/// trailing ✕ already affords cancel, and the bound hotkey is discoverable
/// in Settings — the header reads cleaner without a third metadata run.
/// [decision: owner direction — "remove the unnecessary command".]
struct HUDPillHeader: View {
    let model: OverlayViewModel
    let settingsStore: SettingsStore

    /// Timer text appears while listening (live) and on done (frozen final).
    private var showsTimer: Bool {
        settingsStore.overlayShowTimer
            && (model.overlayState == .listening || model.overlayState == .done)
    }

    var body: some View {
        HStack(alignment: .center, spacing: SpeakSpacing.xs) {
            // The `speakOnAir` tally lamp — brightens and grows with the live
            // mic level, so "is it hearing me" is glanceable in the header
            // (frozen rule survives: `speakOnAir` iff capturing — a tally
            // light, not a red wall). `level` is already smoothed RMS, so the
            // lamp breathes instead of jittering.
            if model.overlayState == .listening {
                let level = min(max(model.level, 0), 1)
                Circle()
                    .fill(Color.speakOnAir)
                    .frame(width: 6, height: 6)
                    .opacity(0.7 + 0.3 * level)
                    .scaleEffect(0.9 + 0.4 * level)
                    .accessibilityHidden(true)
            }

            Text(HUDLane.phaseWord(for: model.overlayState, isCleaningUp: model.isCleaningUp))
                .font(.speakMonoFace(.caption, semibold: true))
                .tracking(1.2)
                .foregroundStyle(HUDLane.phaseTint(for: model.overlayState))

            if showsTimer {
                Text("· \(HUDLane.durationLabel(model.elapsedSeconds))")
                    .font(.speakMonoFace(.caption))
                    .monospacedDigit()
                    .foregroundStyle(Color.speakMica)
                    .accessibilityLabel("Elapsed \(HUDLane.durationLabel(model.elapsedSeconds))")
            }

            Spacer(minLength: 0)
            HUDControlCluster(model: model)
        }
    }
}

// MARK: - Control cluster

/// State-dependent controls, quiet mica glyphs in the header's trailing edge.
/// Listening: customize + close. Processing: close only. Done: readback /
/// re-clean (when wired) + close. Error: close.
struct HUDControlCluster: View {
    let model: OverlayViewModel

    var body: some View {
        HStack(spacing: SpeakSpacing.xs) {
            switch model.overlayState {
            case .listening:
                HUDCustomizeButton(model: model)
                HUDCloseButton(model: model)

            case .processing, .error:
                HUDCloseButton(model: model)

            case .done:
                if model.onReadback != nil { HUDReadbackButton(model: model) }
                if model.onReclean != nil { HUDRecleanButton(model: model) }
                HUDCloseButton(model: model)
            }
        }
    }
}

/// Opens the separate `CodingCustomizationPanel` (per-dictation knobs).
private struct HUDCustomizeButton: View {
    let model: OverlayViewModel

    var body: some View {
        Button {
            model.isCodingPanelOpen.toggle()
            model.onCodingPanelOpenChanged?(model.isCodingPanelOpen)
        } label: {
            Image(systemName: "slider.horizontal.3")
                .font(.system(size: 12))
                .foregroundStyle(Color.speakBone.opacity(model.isCodingPanelOpen ? 1.0 : 0.85))
        }
        .buttonStyle(.plain)
        .help("Customize this dictation")
        .accessibilityLabel("Customize the prompt for this dictation")
        .accessibilityAddTraits(model.isCodingPanelOpen ? [.isSelected, .isButton] : .isButton)
    }
}

/// The close affordance — dismiss the HUD without the hotkey.
private struct HUDCloseButton: View {
    let model: OverlayViewModel

    var body: some View {
        Button {
            model.onCancel?()
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Color.speakBone.opacity(0.9))
        }
        .buttonStyle(.plain)
        .help("Cancel dictation and hide overlay")
        .accessibilityLabel("Cancel dictation")
    }
}

private struct HUDReadbackButton: View {
    let model: OverlayViewModel

    var body: some View {
        Button {
            model.onReadback?()
        } label: {
            Image(systemName: "speaker.wave.2")
                .font(.system(size: 13))
                .foregroundStyle(Color.speakBone.opacity(0.85))
        }
        .buttonStyle(.plain)
        .help("Read this back aloud")
        .accessibilityLabel("Read the transcript back aloud")
    }
}

private struct HUDRecleanButton: View {
    let model: OverlayViewModel

    var body: some View {
        Button {
            model.onReclean?()
        } label: {
            Image(systemName: "arrow.clockwise")
                .font(.system(size: 13))
                .foregroundStyle(Color.speakBone.opacity(0.85))
        }
        .buttonStyle(.plain)
        .help("Re-clean with current settings")
    }
}

// MARK: - Listening lane

/// The FIFO capture window. `windowText` holds the newest end of the
/// transcript (oldest leaves when the char budget fills) — long dictation
/// flows instead of growing. Rendered at footnote-scale mono inside the
/// bounded lane. Reads only `windowText` — a partial-transcript update
/// re-evaluates this lane and nothing else.
struct HUDListeningLane: View {
    let model: OverlayViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if model.windowText.isEmpty {
            Text("Listening\u{2026}")
                .font(.speakBody(.caption))
                .foregroundStyle(Color.speakBone.opacity(0.75))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .accessibilityLabel("Listening for speech")
                .accessibilityAddTraits(.updatesFrequently)
        } else {
            Text(model.windowText)
                .font(.speakMonoFace(.caption))
                .foregroundStyle(Color.speakBone)
                .lineLimit(HUDLane.lineBudget)
                .multilineTextAlignment(.leading)
                .lineSpacing(HUDLane.lineSpacing)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .contentTransition(.interpolate)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: model.windowText)
                .accessibilityLabel(model.windowText)
                .accessibilityAddTraits(.updatesFrequently)
        }
    }
}

// MARK: - Done lane

/// `.done` center — "polish inside the line itself": the raw→clean diff
/// reveals inside the bounded lane (`PolishedDiffContent` →
/// `AnimatedTranscriptView`, internally scrollable so it stays bounded).
/// Non-diff fallbacks show the revealed text; the header's DONE word and
/// the leading slot's tick already carry the state, so no extra glyph here.
struct HUDDoneLane: View {
    let model: OverlayViewModel

    var body: some View {
        if model.isDiffTransforming, let cleaned = model.revealedText {
            PolishedDiffContent(model: model, cleaned: cleaned)
        } else if let revealed = model.revealedText, !revealed.isEmpty {
            Text(revealed)
                .font(.speakMonoFace(.caption))
                .foregroundStyle(Color.speakBone)
                .lineLimit(HUDLane.lineBudget)
                .multilineTextAlignment(.leading)
                .lineSpacing(HUDLane.lineSpacing)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .accessibilityLabel("Dictation complete. \(revealed)")
        } else {
            Text("Pasted at cursor")
                .font(.speakBody(.caption))
                .foregroundStyle(Color.speakMica)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .accessibilityLabel("Dictation complete")
        }
    }
}

// MARK: - Error lane

/// `.error` center — the reason plus the recovery hint, inside the lane.
struct HUDErrorLane: View {
    let model: OverlayViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: SpeakSpacing.xs) {
            HStack(spacing: SpeakSpacing.xs) {
                if let reason = model.errorReason, !reason.isEmpty {
                    Text(reason)
                        .font(.speakBody(.caption))
                        .foregroundStyle(Color.speakBone)
                        .lineLimit(2)
                        .truncationMode(.tail)
                }
            }
            Text("Press Escape or try again")
                .font(.speakBody(.caption))
                .foregroundStyle(Color.speakMica.opacity(0.7))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
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
}

// MARK: - Border layer

/// The OPTIONAL animated border layer — applies only when the user has
/// explicitly chosen a `borderAnimationStyle` other than `.none`. The base
/// pill carries a static hairline + state wash instead (the v2 default);
/// the traveling/glow effects remain available as opt-in decoration.
/// Reads `model.level`/`overlayState` here so the border animates without
/// dragging the frame along.
struct HUDBorderLayer: View {
    let model: OverlayViewModel
    let settingsStore: SettingsStore
    let reduceMotion: Bool

    var body: some View {
        switch settingsStore.borderAnimationStyle {
        case .none:
            EmptyView()

        case .fullGlow:
            AnimatedGradientBorder(
                shape: HUDLane.panelShape,
                state: model.overlayState,
                level: model.level,
                reduceMotion: reduceMotion,
                customPalette: borderTintPalette
            )

        case .edgeFlow:
            EdgeFlowBorder(
                shape: HUDLane.panelShape,
                state: model.overlayState,
                level: model.level,
                speed: settingsStore.borderFlowSpeed,
                count: settingsStore.borderFlowCount,
                reduceMotion: reduceMotion,
                customPalette: borderTintPalette
            )
        }
    }

    /// Fixed border tint → a single-color palette both border views accept;
    /// `.adaptive` (nil) keeps the state-aware `speakFlow*` spectra.
    private var borderTintPalette: [Color]? {
        settingsStore.overlayBorderTint.fixedVoiceColor.map { [$0.color] }
    }
}
