// App/Onboarding/OnboardingSteps.swift
//
// The permission + hotkey step views for the first-run onboarding flow —
// split out of OnboardingView.swift to hold both files under SwiftLint's
// file_length cap (same pattern as AboutSettingsTab / HUDStyleSection).
// Internal (not private) because they live in their own file; they are
// onboarding internals, not meant for reuse elsewhere. The Welcome/Done
// bookends stay in OnboardingView.swift with the step dispatch.
//
// `PermissionStepView` renders five states: needed (primary CTA requests),
// loading (request in-flight), waiting (prompt fired, grant pending in System
// Settings — disabled button + deep link), denied (TCC refused — primary CTA
// deep-links to the exact pane), granted (ok check + Continue).

import SpeakCore
import SwiftUI

// MARK: - OnboardingStepIcon

/// The shared icon well every step leads with: a tinted circle + SF Symbol.
/// Tint is semantic — accent for "needs action", ok for granted, error for
/// denied, humanAmber for the human-owned hotkey.
struct OnboardingStepIcon: View {
    let symbol: String
    var tint: Color = .speakUIAccent

    var body: some View {
        ZStack {
            Circle()
                .fill(tint.opacity(0.14))
                .frame(width: 76, height: 76)
            Image(systemName: symbol)
                .font(.system(size: 32, weight: .medium))
                .foregroundStyle(tint)
        }
        .accessibilityHidden(true)
    }
}

// MARK: - PermissionStepView

enum PermissionStatus {
    /// Not yet granted — the primary CTA requests it.
    case needed
    /// TCC refused — only fixable in System Settings; the primary CTA
    /// deep-links to the exact pane.
    case denied
    /// Granted — ok check + Continue.
    case granted
}

struct PermissionStepView: View {
    let kind: PermissionKind
    let status: PermissionStatus
    let isLoading: Bool
    /// `true` for Accessibility after the first tap while waiting for the user to
    /// toggle the permission in System Settings. Disables the primary button and
    /// relabels it "Waiting for permission…" so re-taps cannot spawn a second TCC
    /// dialog. The "Open System Settings" link remains enabled.
    let isWaiting: Bool
    let onAction: () -> Void
    let onContinue: () -> Void
    let onOpenSettings: () -> Void

    var body: some View {
        VStack(spacing: SpeakSpacing.lg) {
            OnboardingStepIcon(symbol: iconName, tint: iconTint)
                .padding(.top, SpeakSpacing.xl + SpeakSpacing.xs)

            VStack(spacing: SpeakSpacing.sm) {
                Text(title)
                    .font(.speakDisplay(.title))
                    .foregroundStyle(Color.speakBone)
                Text(description)
                    .font(.speakBody(.body))
                    .foregroundStyle(Color.speakMica)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 360)
            }

            actionArea
        }
        .padding(.horizontal, 40)
    }

    // MARK: - Action area

    @ViewBuilder
    private var actionArea: some View {
        switch status {
        case .needed:
            if isLoading {
                // In-flight request (microphone prompt is on screen).
                HStack(spacing: SpeakSpacing.sm) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Requesting access…")
                        .font(.speakBody(.base))
                        .foregroundStyle(Color.speakMica)
                }
            } else if isWaiting {
                // TCC prompt fired — the grant now lives in System Settings.
                // The disabled primary prevents a second prompt; the deep link
                // re-opens the pane if the user lost it.
                VStack(spacing: SpeakSpacing.sm) {
                    Button(
                        action: {},
                        label: {
                            HStack(spacing: SpeakSpacing.sm) {
                                ProgressView()
                                    .controlSize(.small)
                                Text("Waiting for permission…")
                            }
                        }
                    )
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .tint(.speakUIAccent)
                    .disabled(true)

                    Text("Turn on speak in the Accessibility list — this window continues automatically.")
                        .font(.speakBody(.caption))
                        .foregroundStyle(Color.speakMica)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 320)

                    Button("Open System Settings") {
                        onOpenSettings()
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.speakUIAccent)
                    .font(.speakBody(.caption, semibold: true))
                }
            } else {
                VStack(spacing: SpeakSpacing.sm) {
                    Button(actionLabel) {
                        onAction()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .tint(.speakUIAccent)

                    // For mic, a quiet fallback for when TCC already holds a
                    // record (no prompt appears) or the user missed the
                    // prompt's own "Open Settings" button. Accessibility's
                    // primary action already opens the pane, so a second link
                    // would be redundant noise.
                    if kind == .microphone {
                        Button("Open System Settings instead") {
                            onOpenSettings()
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(Color.speakMica)
                        .font(.speakBody(.caption))
                    }
                }
            }

        case .denied:
            VStack(spacing: SpeakSpacing.sm) {
                Button("Open System Settings") {
                    onOpenSettings()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(.speakUIAccent)

                Text("This window continues automatically once it's on.")
                    .font(.speakBody(.caption))
                    .foregroundStyle(Color.speakMica)
            }

        case .granted:
            VStack(spacing: SpeakSpacing.sm) {
                HStack(spacing: SpeakSpacing.xs + 2) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.speakOK)
                    Text("Permission granted")
                        .font(.speakBody(.base))
                        .foregroundStyle(Color.speakMica)
                }
                Button("Continue") {
                    onContinue()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(.speakUIAccent)
            }
        }
    }

    // MARK: - Per-kind content

    private var title: String {
        switch kind {
        case .microphone:     return "Microphone Access"
        case .accessibility:  return "Accessibility Access"
        }
    }

    private var description: String {
        switch kind {
        case .microphone:
            if status == .denied {
                return "Microphone access is off for speak. Turn it on under "
                    + "Privacy & Security → Microphone in System Settings."
            }
            return "speak captures your voice to transcribe it — on-device only, never sent anywhere."

        case .accessibility:
            return "Accessibility lets speak hear your global hotkey in any app "
                + "and paste finished text at the cursor."
        }
    }

    private var actionLabel: String {
        switch kind {
        case .microphone:
            return "Grant Microphone Access"

        case .accessibility:
            return "Enable Accessibility Access"
        }
    }

    private var iconName: String {
        switch status {
        case .granted:
            return "checkmark.circle.fill"

        case .denied:
            return "mic.slash.fill"

        case .needed:
            switch kind {
            case .microphone:    return "mic.fill"
            case .accessibility: return "accessibility"
            }
        }
    }

    private var iconTint: Color {
        switch status {
        case .granted: return .speakOK
        case .denied:  return .speakError
        case .needed:  return .speakUIAccent
        }
    }
}

// MARK: - HotkeyStepView

struct HotkeyStepView: View {
    /// The live hotkey gesture label (e.g. "⌘⌘ Right Command", "Fn ×2").
    /// Sourced from `OnboardingViewModel.currentHotkeyDisplayString`.
    let hotkeyLabel: String
    /// `true` once the user has fired the hotkey at least once during this step.
    let hotkeyTriggered: Bool
    let onContinue: () -> Void

    var body: some View {
        // Tighter rhythm than the other steps — this one carries the conflict
        // card + try pill + primary action inside the fixed 460pt window.
        VStack(spacing: SpeakSpacing.md) {
            // The hotkey is a human affordance → humanAmber channel tint.
            OnboardingStepIcon(symbol: "command", tint: .speakHumanAmber)
                .padding(.top, SpeakSpacing.md)

            VStack(spacing: SpeakSpacing.sm) {
                // `hotkeyLabel` already encodes the full gesture (e.g. "⌘⌘ Right Command")
                // so we show it as-is — never prepend "Double-tap" which would
                // double-encode the trigger and be wrong for hold mode.
                Text("Your Hotkey")
                    .font(.speakDisplay(.title))
                    .foregroundStyle(Color.speakBone)

                // The gesture is data → mono face inside a recessed well.
                Text(hotkeyLabel)
                    .font(.speakMonoFace(.base, semibold: true))
                    .foregroundStyle(Color.speakBone)
                    .padding(.horizontal, SpeakSpacing.md)
                    .padding(.vertical, SpeakSpacing.xs + 2)
                    .speakInset()

                Text("Trigger it to start dictating; trigger again to stop. speak listens while you work in any app.")
                    .font(.speakBody(.body))
                    .foregroundStyle(Color.speakMica)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 360)

                // Conflict guidance card [W1.2 decision: proactive, not detection-based]
                // macOS has no public API to read the system-dictation shortcut state.
                HotkeyConflictNoteView()
            }

            // "Try it now" live test pill
            HotkeyTryPillView(hotkeyLabel: hotkeyLabel, triggered: hotkeyTriggered)

            Button("Finish Setup") {
                onContinue()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(.speakUIAccent)
        }
        .padding(.horizontal, 40)
    }
}

// MARK: - HotkeyConflictNoteView

/// Proactive conflict guidance card for the hotkey step.
///
/// macOS exposes no public API to read the system-dictation shortcut state
/// [decision: detect nothing — guide proactively instead, W1.2]. The card is
/// shown unconditionally and explains the safe default + what to do if the user
/// switches to Fn.
private struct HotkeyConflictNoteView: View {
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "info.circle")
                .foregroundStyle(Color.speakMica)
                .font(.speakBody(.base))
                .padding(.top, 1)

            Text(
                "speak uses double-tap Right-Command so it won't clash with macOS dictation. "
                    + "If you switch to Fn in Settings, disable **System Settings → Keyboard "
                    + "→ Dictation** shortcut first."
            )
                .font(.speakBody(.caption))
                .foregroundStyle(Color.speakMica)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, SpeakSpacing.md)
        .padding(.vertical, SpeakSpacing.sm)
        .speakInset()
        .frame(maxWidth: 360)
    }
}

// MARK: - HotkeyTryPillView

/// A pill that starts neutral and turns green once the user fires the hotkey.
///
/// Two visual states:
///   - Waiting: grey, "Try it now — \(hotkeyLabel)"
///   - Triggered (green): "Nice — that worked." with checkmark
///
/// The pill is a delighter, NOT a gate — advancing past this step
/// does not require the pill to be green.
private struct HotkeyTryPillView: View {
    /// The live hotkey gesture label (e.g. "⌘⌘ Right Command", "Fn ×2").
    let hotkeyLabel: String
    let triggered: Bool

    var body: some View {
        HStack(spacing: SpeakSpacing.sm) {
            Image(systemName: triggered ? "checkmark.circle.fill" : "hand.tap")
                .foregroundStyle(triggered ? Color.speakOK : Color.speakMica)
                .font(.speakBody(.base))
            Text(triggered ? "Nice — that worked." : "Try it now — \(hotkeyLabel)")
                .font(.speakBody(.caption))
                .foregroundStyle(triggered ? Color.speakBone : Color.speakMica)
        }
        .padding(.horizontal, SpeakSpacing.md)
        .padding(.vertical, SpeakSpacing.sm)
        .background(
            Capsule()
                .fill(triggered ? Color.speakOK.opacity(0.12) : Color.speakMica.opacity(0.1))
        )
        .overlay(
            Capsule()
                .strokeBorder(
                    triggered ? Color.speakOK.opacity(0.4) : Color.speakMica.opacity(0.2),
                    lineWidth: 1
                )
        )
        .animation(.easeInOut(duration: 0.25), value: triggered)
    }
}
