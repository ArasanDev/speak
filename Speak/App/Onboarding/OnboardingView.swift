// App/Onboarding/OnboardingView.swift
//
// The first-run onboarding window content.
//
// DESIGN (product.md §7.3 + explicit states per screen):
//   Every step shares one skeleton — centered icon well (semantic tint), a
//   speakDisplay-scale title, a one-line value prop, and exactly one primary
//   action. Skip is a quiet footer affordance. Permission steps have five
//   states (see OnboardingSteps.swift / `PermissionStepView`):
//     needed · loading · waiting · denied · granted
//   Grants are also picked up by the view model's 1 s poll, which
//   auto-advances the step without a tap.
//
//   The permission + hotkey step views live in OnboardingSteps.swift (split
//   for the file_length cap); the Welcome/Done bookends stay here.
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
                // Identity per step → a soft cross-fade between steps instead
                // of a hard cut.
                .id(viewModel.displayedStep)
                .transition(.opacity)
            Spacer(minLength: 0)
            footer
        }
        .frame(width: 480, height: 460) // [decision: 460pt height to accommodate hotkey step conflict card + try pill, W1.2]
        .background(Color.speakWindowCanvas)
        .animation(.easeInOut(duration: 0.2), value: viewModel.displayedStep)
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
                status: micStatus,
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

    /// Microphone maps its full TCC state onto the step: `.denied` gets its
    /// own UI because a refused grant can't be re-prompted — the only fix is
    /// the System Settings toggle. (Accessibility reports `.denied` for the
    /// normal untrusted state, so only the mic uses this mapping.)
    private var micStatus: PermissionStatus {
        switch viewModel.permissionState(.microphone) {
        case .granted:
            return .granted

        case .denied, .restricted:
            return .denied

        case .notDetermined, .requesting:
            return .needed
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            // Skip is a quiet affordance — and meaningless on the done step,
            // which is already completing on its own.
            if viewModel.displayedStep != .done {
                Button("Skip for now") {
                    viewModel.skip()
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.speakMica)
                .font(.speakBody(.caption))
            }
            Spacer()
            progressDots
        }
        .padding(.horizontal, SpeakSpacing.lg)
        .padding(.vertical, SpeakSpacing.md)
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
                    .fill(idx == currentIndex ? Color.speakUIAccent : Color.speakMica.opacity(0.3))
                    .frame(width: 7, height: 7)
            }
        }
    }
}

// MARK: - WelcomeStepView

/// The opening bookend — brand mark, display title, one-line value prop, one
/// primary action.
private struct WelcomeStepView: View {
    let onContinue: () -> Void

    var body: some View {
        VStack(spacing: SpeakSpacing.lg) {
            // Brand mark: the amber waveform — the human channel IS the brand.
            OnboardingStepIcon(symbol: "waveform", tint: .speakHumanAmber)
                .padding(.top, SpeakSpacing.xl + SpeakSpacing.sm)

            VStack(spacing: SpeakSpacing.sm) {
                Text("Welcome to speak")
                    .font(.speakDisplay())
                    .foregroundStyle(Color.speakBone)
                Text("Your voice becomes polished text — entirely on your Mac. Nothing leaves your device.")
                    .font(.speakBody(.body))
                    .foregroundStyle(Color.speakMica)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 340)
            }

            Button("Get Started") {
                onContinue()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(.speakUIAccent)
        }
        .padding(.horizontal, 40)
    }
}

// MARK: - DoneStepView

/// The closing bookend — terminal completion, so the icon takes the
/// `delivered` role rather than a generic green. The window auto-closes
/// (OnboardingWindowController watches for `.done`); no button needed.
private struct DoneStepView: View {
    /// The live hotkey gesture label (e.g. "⌘⌘ Right Command", "Fn ×2").
    let hotkeyLabel: String

    var body: some View {
        VStack(spacing: SpeakSpacing.lg) {
            OnboardingStepIcon(symbol: "checkmark.seal.fill", tint: .speakDelivered)
                .padding(.top, SpeakSpacing.xl + SpeakSpacing.sm)

            VStack(spacing: SpeakSpacing.sm) {
                Text("You're all set.")
                    .font(.speakDisplay())
                    .foregroundStyle(Color.speakBone)
                // `hotkeyLabel` encodes the full gesture — shown directly, no prefix.
                Text("Use \(hotkeyLabel) to start dictating — speak pastes polished text wherever your cursor is.")
                    .font(.speakBody(.body))
                    .foregroundStyle(Color.speakMica)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 340)
            }
            Text("This window will close in a moment.")
                .font(.speakBody(.caption))
                .foregroundStyle(Color.speakMica)
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
