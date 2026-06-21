// SpeakCore/Permissions/OnboardingState.swift
//
// Pure, headless step-state machine for the first-run permission onboarding flow.
//
// This type is `Sendable` value-semantic and has no UI dependencies — it can be
// instantiated and tested from `SpeakTests` with `@testable import SpeakCore`
// without any AppKit/SwiftUI involvement. The onboarding window reads these
// values and feeds them to its SwiftUI views.
//
// Step order (product.md §7.3, roadmap P7):
//   welcome → microphone → accessibility → hotkey → done
//
// The machine is a pure function of the two `PermissionState`s and the
// `hasCompletedOnboarding` flag — calling `evaluate(...)` is idempotent and
// never has side-effects.
//
// --- Permission model ---
// Mic + Accessibility are the only two required permissions in v0.
// Input Monitoring was removed: the CGEventTap uses .defaultTap and is gated
// on Accessibility alone (verified: HotkeyMonitor.swift §84–86). The IM step
// was vestigial scaffolding from an earlier listen-only-tap design.

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
    /// Explains the double-tap hotkey. No permission required.
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
    public let isComplete: Bool
    /// The permissions still missing that BLOCK completion.
    /// Contains only `.microphone` and/or `.accessibility`.
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

/// Evaluates the current onboarding step from the two permission states and
/// the completion flag. This is a pure function — it has no stored state and
/// never calls `PermissionManager` directly, making it trivially unit-testable.
public enum OnboardingStateMachine {

    /// Evaluates the onboarding state machine.
    ///
    /// - Parameters:
    ///   - microphone: Current `PermissionState` for `.microphone`.
    ///   - accessibility: Current `PermissionState` for `.accessibility`.
    ///   - hasCompletedOnboarding: Whether the user has previously finished or
    ///     explicitly skipped the flow.
    /// - Returns: An `OnboardingEvaluation` with the current step, completion
    ///   status, and any remaining BLOCKING permissions (Mic + AX only).
    public static func evaluate(
        microphone: PermissionState,
        accessibility: PermissionState,
        hasCompletedOnboarding: Bool
    ) -> OnboardingEvaluation {

        // Blocking permissions: Mic + AX only.
        var blocking: [PermissionKind] = []
        if !microphone.isGranted { blocking.append(.microphone) }
        if !accessibility.isGranted { blocking.append(.accessibility) }

        // The flow is complete when both required permissions are granted AND flag is set.
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
        } else if !hasCompletedOnboarding {
            // Both permissions granted, flag not yet set — hotkey explanation.
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
            hasCompletedOnboarding: hasCompletedOnboarding
        )
    }
}

// MARK: - PermissionState convenience

private extension PermissionState {
    var isGranted: Bool { self == .granted }
}
