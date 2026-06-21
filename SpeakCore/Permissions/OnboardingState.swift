// SpeakCore/Permissions/OnboardingState.swift
//
// Pure, headless step-state machine for the first-run permission onboarding flow.
//
// This type is `Sendable` value-semantic and has no UI dependencies — it can be
// instantiated and tested from `SpeakTests` with `@testable import SpeakCore`
// without any AppKit/SwiftUI involvement. The onboarding window reads these
// values and feeds them to its SwiftUI views.
//
// Step order matches product.md §7.3 and roadmap.md P7:
//   welcome → microphone → accessibility → inputMonitoring → done
//
// The machine is a pure function of the three `PermissionState`s and the
// `hasCompletedOnboarding` flag — calling `evaluate(...)` is idempotent and
// never has side-effects.
//
// --- Permission model (Phase A, spec §2) ---
// Mic + Accessibility are *blocking* permissions: missing either keeps isComplete
// == false and prevents onboarding from completing. Input Monitoring is a
// *surfaced-but-non-blocking* permission: it gets its own onboarding step so
// the user is shown how to grant it, but its absence does NOT block completion
// or tap arming. The Fn .flagsChanged tap is gated on Accessibility alone
// (research-verified: AltTab/Hex use AX only for a listen-only tap).

import Foundation

// MARK: - OnboardingStep

/// Each step in the first-run onboarding flow (product.md §7.3).
public enum OnboardingStep: Sendable, Equatable, CaseIterable {
    /// Title card — introduces `speak` before any permission requests.
    case welcome
    /// Microphone permission step.
    case microphone
    /// Accessibility permission step.
    case accessibility
    /// Input Monitoring permission step.
    /// Surfaced in the UI but does NOT block completion (spec §2).
    case inputMonitoring
    /// Explains the double-tap Fn hotkey. No permission required.
    case hotkey
    /// Final confirmation — the flow is complete.
    case done
}

// MARK: - OnboardingEvaluation

/// The result of evaluating the onboarding state machine.
public struct OnboardingEvaluation: Sendable, Equatable {
    /// The step the onboarding UI should currently display.
    public let currentStep: OnboardingStep
    /// `true` when Mic + Accessibility are granted AND `hasCompletedOnboarding == true`.
    /// Input Monitoring absence does NOT prevent completion (spec §2).
    public let isComplete: Bool
    /// The permissions still missing that BLOCK completion.
    /// Contains only `.microphone` and/or `.accessibility` — never `.inputMonitoring`.
    /// Empty when `isComplete == true`.
    public let blockingPermissions: [PermissionKind]

    public init(
        currentStep: OnboardingStep,
        isComplete: Bool,
        blockingPermissions: [PermissionKind]
    ) {
        self.currentStep = currentStep
        self.isComplete = isComplete
        self.blockingPermissions = blockingPermissions
    }
}

// MARK: - OnboardingStateMachine

/// Evaluates the current onboarding step from the three permission states and
/// the completion flag. This is a pure function — it has no stored state and
/// never calls `PermissionManager` directly, making it trivially unit-testable.
public enum OnboardingStateMachine {

    /// Evaluates the onboarding state machine.
    ///
    /// - Parameters:
    ///   - microphone: Current `PermissionState` for `.microphone`.
    ///   - accessibility: Current `PermissionState` for `.accessibility`.
    ///   - inputMonitoring: Current `PermissionState` for `.inputMonitoring`.
    ///   - hasCompletedOnboarding: Whether the user has previously finished or
    ///     explicitly skipped the flow.
    /// - Returns: An `OnboardingEvaluation` with the current step, completion
    ///   status, and any remaining BLOCKING permissions (Mic + AX only).
    public static func evaluate(
        microphone: PermissionState,
        accessibility: PermissionState,
        inputMonitoring: PermissionState,
        hasCompletedOnboarding: Bool
    ) -> OnboardingEvaluation {

        // Blocking permissions: Mic + AX only.
        // Input Monitoring is surfaced as a step but does NOT block completion (spec §2).
        var blocking: [PermissionKind] = []
        if !microphone.isGranted { blocking.append(.microphone) }
        if !accessibility.isGranted { blocking.append(.accessibility) }

        // The flow is complete when the two required permissions are granted AND flag is set.
        let allRequiredGranted = blocking.isEmpty
        let isComplete = allRequiredGranted && hasCompletedOnboarding

        if isComplete {
            return OnboardingEvaluation(
                currentStep: .done,
                isComplete: true,
                blockingPermissions: []
            )
        }

        // Walk the step sequence to find the first incomplete one.
        let currentStep: OnboardingStep
        if !microphone.isGranted {
            currentStep = .microphone
        } else if !accessibility.isGranted {
            currentStep = .accessibility
        } else if !inputMonitoring.isGranted {
            // IM not granted: show the IM step so the user can grant it,
            // but this does NOT set isComplete = false for the blocking gate.
            currentStep = .inputMonitoring
        } else if !hasCompletedOnboarding {
            // All permissions granted, flag not yet set — hotkey explanation.
            currentStep = .hotkey
        } else {
            // Shouldn't reach here given the isComplete guard above.
            currentStep = .done
        }

        return OnboardingEvaluation(
            currentStep: currentStep,
            isComplete: false,
            blockingPermissions: blocking
        )
    }

    /// Convenience: evaluate from a live `PermissionManaging` instance.
    ///
    /// - Parameters:
    ///   - manager: Any type conforming to `PermissionManaging`. Called on `@MainActor`.
    ///   - hasCompletedOnboarding: The flag from `SettingsStore`.
    @MainActor
    public static func evaluate(
        manager: any PermissionManaging,
        hasCompletedOnboarding: Bool
    ) -> OnboardingEvaluation {
        evaluate(
            microphone: manager.status(.microphone),
            accessibility: manager.status(.accessibility),
            inputMonitoring: manager.status(.inputMonitoring),
            hasCompletedOnboarding: hasCompletedOnboarding
        )
    }
}

// MARK: - PermissionState convenience

private extension PermissionState {
    var isGranted: Bool { self == .granted }
}
