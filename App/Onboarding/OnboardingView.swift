// App/Onboarding/OnboardingView.swift
//
// The first-run onboarding window content.
//
// DESIGN (product.md §7.3 + 3 states per screen):
//   Each step has three states:
//     - loading/in-progress: permission request in-flight (spinner + disabled button)
//     - active/empty: permission not yet granted (Why text + action button)
//     - granted/done: permission granted (checkmark + Continue button)
//
// HOTKEY LABEL (W2.5):
//   Onboarding reads the live binding from `OnboardingViewModel.currentHotkeyDisplayString`
//   which sources `UserDefaultsBindingStore` + `settings.triggerMode` — the same
//   pair `DictationController` uses — so the hotkey step and done screen always show
//   the user's actual configured gesture (e.g. "⌘⌘ Right Command", "Fn ×2").
//
// HONESTY BOUNDARY:
//   The rendered flow, system prompts, and deep-link correctness are
//   [deferred — needs human verification: human-verification.md §4.4].
//   The step-state machine is [verified] by OnboardingFlowTests.
//
// THREADING:
//   SwiftUI View bodies are @MainActor by default.
//   `viewModel` is @StateObject (owns lifetime) or @ObservedObject (injected).

import SpeakCore
import SwiftUI

// MARK: - OnboardingView

/// The root onboarding view. Rendered inside `OnboardingWindowController`.
struct OnboardingView: View {
    let viewModel: OnboardingViewModel

    var body: some View {
        VStack(spacing: 0) {
            stepContent
            Spacer(minLength: 0)
            footer
        }
        .frame(width: 480, height: 460) // [decision: 460pt height to accommodate hotkey step conflict card + try pill, W1.2]
        .background(.background)
        .onAppear { viewModel.onAppear() }
        .onDisappear { viewModel.onDisappear() }
    }

    // MARK: - Step dispatch

    @ViewBuilder
    private var stepContent: some View {
        switch viewModel.displayedStep {
        case .welcome:
            WelcomeStepView(onContinue: { viewModel.advance() })

        case .microphone:
            PermissionStepView(
                kind: .microphone,
                status: viewModel.evaluation.blockingPermissions.contains(.microphone)
                    ? .needed : .granted,
                isLoading: viewModel.isRequestingMic,
                isWaiting: false,
                onAction: { viewModel.requestMicrophone() },
                onContinue: { viewModel.advance() },
                onOpenSettings: { viewModel.openSystemSettings(for: .microphone) }
            )

        case .accessibility:
            PermissionStepView(
                kind: .accessibility,
                status: viewModel.evaluation.blockingPermissions.contains(.accessibility)
                    ? .needed : .granted,
                isLoading: false,
                isWaiting: viewModel.isWaitingForAccessibility,
                onAction: { viewModel.requestAccessibility() },
                onContinue: { viewModel.advance() },
                onOpenSettings: { viewModel.openSystemSettings(for: .accessibility) }
            )

        case .hotkey:
            HotkeyStepView(
                hotkeyLabel: viewModel.currentHotkeyDisplayString,
                hotkeyTriggered: viewModel.hotkeyTriggered,
                onContinue: { viewModel.advance() }
            )

        case .done:
            DoneStepView(hotkeyLabel: viewModel.currentHotkeyDisplayString)
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Button("Skip for now") {
                viewModel.skip()
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .font(.caption)
            Spacer()
            progressDots
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
    }

    /// Step-position dots (visual only — pure decoration).
    private var progressDots: some View {
        // `.done` is included so `firstIndex(of:)` returns the last index when the
        // Done screen is shown, lighting the final dot rather than falling back to
        // `?? 0` (Welcome). [decision: 5-dot sequence — done follows hotkey]
        let allSteps: [OnboardingStep] = [.welcome, .microphone, .accessibility, .hotkey, .done]
        // When `displayedStep` is `.done`, `firstIndex` returns 4 (last dot) — correct.
        // `?? 0` is a defensive fallback only; with `.done` included it is unreachable.
        let currentIndex = allSteps.firstIndex(of: viewModel.displayedStep) ?? 0
        return HStack(spacing: 6) {
            ForEach(0..<allSteps.count, id: \.self) { idx in
                Circle()
                    .fill(idx == currentIndex ? Color.accentColor : Color.secondary.opacity(0.3))
                    .frame(width: 7, height: 7)
            }
        }
    }
}

// MARK: - WelcomeStepView

private struct WelcomeStepView: View {
    let onContinue: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "waveform.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.tint)
                .padding(.top, 40)

            VStack(spacing: 8) {
                Text("Welcome to speak")
                    .font(.title.bold())
                Text("speak turns your voice into polished text, entirely on your Mac. Nothing leaves your device.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 340)
            }

            Button("Get Started") {
                onContinue()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding(.horizontal, 40)
    }
}

// MARK: - PermissionStepView

private enum PermissionStatus {
    case needed
    case granted
}

private struct PermissionStepView: View {
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
        VStack(spacing: 24) {
            // Icon
            ZStack {
                Circle()
                    .fill(iconBackground)
                    .frame(width: 72, height: 72)
                Image(systemName: iconName)
                    .font(.system(size: 32))
                    .foregroundStyle(iconForeground)
            }
            .padding(.top, 36)

            // Title + description
            VStack(spacing: 8) {
                Text(title)
                    .font(.title2.bold())
                Text(description)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 360)
            }

            // Action area
            switch status {
            case .needed:
                if isLoading {
                    // Loading state: in-progress spinner (microphone request in-flight)
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Requesting access\u{2026}")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    VStack(spacing: 10) {
                        // Primary button: disabled in the "waiting" state so the user
                        // cannot tap again and trigger a second TCC dialog. The label
                        // communicates that we're waiting, not broken.
                        Button(isWaiting ? "Waiting for permission\u{2026}" : actionLabel) {
                            onAction()
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .disabled(isWaiting)

                        // Open System Settings link — always enabled for
                        // Accessibility and Input Monitoring steps, so the user
                        // can navigate back to the pane if they missed the prompt's
                        // own button, or if TCC already had a record (no prompt shown).
                        // For mic, shown only as a fallback when denied.
                        if kind == .microphone {
                            Button("Open System Settings instead") {
                                onOpenSettings()
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                            .font(.caption)
                        } else {
                            Button("Open System Settings") {
                                onOpenSettings()
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                            .font(.caption)
                        }
                    }
                }

            case .granted:
                // Success state: green checkmark + Continue
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("Permission granted")
                        .foregroundStyle(.secondary)
                }
                Button("Continue") {
                    onContinue()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
        }
        .padding(.horizontal, 40)
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
            return "speak captures your voice to transcribe it. Audio is processed on-device and never sent anywhere."

        case .accessibility:
            // swiftlint:disable:next line_length
            return "speak needs Accessibility access to simulate the Cmd+V keystroke that pastes your transcribed text at the cursor."
        }
    }

    private var actionLabel: String {
        switch kind {
        case .microphone:
            return "Grant Microphone Access"

        case .accessibility:
            return "Open System Settings"
        }
    }

    private var iconName: String {
        switch status {
        case .granted:
            return "checkmark.circle.fill"

        case .needed:
            switch kind {
            case .microphone:    return "mic.fill"
            case .accessibility: return "hand.point.up.left.fill"
            }
        }
    }

    private var iconBackground: Color {
        status == .granted ? Color.green.opacity(0.15) : Color.accentColor.opacity(0.12)
    }

    private var iconForeground: Color {
        status == .granted ? .green : .accentColor
    }
}

// MARK: - HotkeyStepView

private struct HotkeyStepView: View {
    /// The live hotkey gesture label (e.g. "⌘⌘ Right Command", "Fn ×2").
    /// Sourced from `OnboardingViewModel.currentHotkeyDisplayString`.
    let hotkeyLabel: String
    /// `true` once the user has fired the hotkey at least once during this step.
    let hotkeyTriggered: Bool
    let onContinue: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "command.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.tint)
                .padding(.top, 36)

            VStack(spacing: 8) {
                // `hotkeyLabel` already encodes the full gesture (e.g. "⌘⌘ Right Command")
                // so we show it as-is — never prepend "Double-tap" which would
                // double-encode the trigger and be wrong for hold mode.
                Text("Your Hotkey: \(hotkeyLabel)")
                    .font(.title2.bold())

                // swiftlint:disable:next line_length
                Text("Trigger the hotkey to start dictating; trigger it again to stop. speak listens while you work in any app.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 360)

                // Conflict guidance card [W1.2 decision: proactive, not detection-based]
                // macOS has no public API to read the system-dictation shortcut state.
                HotkeyConflictNoteView()
                    .padding(.top, 4)
            }

            // "Try it now" live test pill
            HotkeyTryPillView(hotkeyLabel: hotkeyLabel, triggered: hotkeyTriggered)

            Button("Finish Setup") {
                onContinue()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.bottom, 4)
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
                .foregroundStyle(.secondary)
                .font(.body)
                .padding(.top, 1)

            // swiftlint:disable:next line_length
            Text("speak uses double-tap Right-Command so it won't clash with macOS dictation. If you switch to Fn in Settings, disable **System Settings \u{2192} Keyboard \u{2192} Dictation** shortcut first.")
                .font(.speakMonoCaption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, SpeakSpacing.md)
        .padding(.vertical, SpeakSpacing.sm)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
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
        HStack(spacing: 8) {
            Image(systemName: triggered ? "checkmark.circle.fill" : "hand.tap")
                .foregroundStyle(triggered ? .green : .secondary)
                .font(.body)
            Text(triggered ? "Nice \u{2014} that worked." : "Try it now \u{2014} \(hotkeyLabel)")
                .font(.speakMonoCaption)
                .foregroundStyle(triggered ? .primary : .secondary)
        }
        .padding(.horizontal, SpeakSpacing.md)
        .padding(.vertical, SpeakSpacing.sm)
        .background(
            Capsule()
                .fill(triggered ? Color.green.opacity(0.12) : Color.secondary.opacity(0.1))
        )
        .overlay(
            Capsule()
                .strokeBorder(
                    triggered ? Color.green.opacity(0.4) : Color.secondary.opacity(0.2),
                    lineWidth: 1
                )
        )
        .animation(.easeInOut(duration: 0.25), value: triggered)
    }
}

// MARK: - DoneStepView

private struct DoneStepView: View {
    /// The live hotkey gesture label (e.g. "⌘⌘ Right Command", "Fn ×2").
    let hotkeyLabel: String

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 64))
                .foregroundStyle(.green)
                .padding(.top, 40)

            VStack(spacing: 8) {
                Text("You\u{2019}re all set.")
                    .font(.title.bold())
                // `hotkeyLabel` encodes the full gesture — shown directly, no prefix.
                Text("Use \(hotkeyLabel) to start dictating. speak will paste polished text wherever your cursor is.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 340)
            }
            Text("This window will close in a moment.")
                .font(.speakMonoCaption)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 40)
    }
}

// MARK: - Preview

#if DEBUG
#Preview("Welcome") {
    let pm = PermissionManager()
    let store = SettingsStore()
    let vm = OnboardingViewModel(permissionManager: pm, settings: store)
    return OnboardingView(viewModel: vm)
}
#endif
