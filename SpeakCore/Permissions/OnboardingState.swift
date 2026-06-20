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
//   welcome → microphone → accessibility → inputMonitoring → hotkey → done
//
// The machine is a pure function of the three `PermissionState`s and the
// `hasCompletedOnboarding` flag — calling `evaluate(...)` is idempotent and
// never has side-effects.

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
    /// `true` when all permissions are granted and `hasCompletedOnboarding == true`.
    public let isComplete: Bool
    /// The permissions still missing (`.notDetermined`, `.denied`, `.restricted`).
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
    ///   status, and any remaining blocking permissions.
    public static func evaluate(
        microphone: PermissionState,
        accessibility: PermissionState,
        inputMonitoring: PermissionState,
        hasCompletedOnboarding: Bool
    ) -> OnboardingEvaluation {

        // Build the list of blocking permissions in order of presentation.
        var blocking: [PermissionKind] = []
        if !microphone.isGranted { blocking.append(.microphone) }
        if !accessibility.isGranted { blocking.append(.accessibility) }
        if !inputMonitoring.isGranted { blocking.append(.inputMonitoring) }

        // The flow is complete when all permissions granted AND flag is set.
        let allGranted = blocking.isEmpty
        let isComplete = allGranted && hasCompletedOnboarding

        if isComplete {
            return OnboardingEvaluation(
                currentStep: .done,
                isComplete: true,
                blockingPermissions: []
            )
        }

        // Walk the step sequence to find the first incomplete one.
        let currentStep: OnboardingStep
        if !hasCompletedOnboarding && microphone.isGranted && accessibility.isGranted && inputMonitoring.isGranted {
            // All permissions granted but the flag is not set — user is on the
            // hotkey-explanation step, about to finish.
            currentStep = .hotkey
        } else if !microphone.isGranted {
            currentStep = .microphone
        } else if !accessibility.isGranted {
            currentStep = .accessibility
        } else if !inputMonitoring.isGranted {
            currentStep = .inputMonitoring
        } else {
            // All permissions granted but flag not yet set: hotkey step.
            currentStep = .hotkey
        }

        return OnboardingEvaluation(
            currentStep: currentStep,
            isComplete: false,
            blockingPermissions: blocking
        )
    }

    /// Convenience: evaluate from a live `PermissionManager` instance.
    ///
    /// - Parameters:
    ///   - manager: The live permission manager. Called on `@MainActor`.
    ///   - hasCompletedOnboarding: The flag from `SettingsStore`.
    @MainActor
    public static func evaluate(
        manager: PermissionManager,
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
