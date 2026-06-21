// SpeakTests/OnboardingFlowTests.swift
//
// Unit tests for `OnboardingStateMachine` (SpeakCore/Permissions/OnboardingState.swift).
//
// This is the "headless-verifiable slice" of P7: the step machine is pure value
// logic with zero UI dependencies. All paths are exercised here. The rendered
// onboarding flow and live deep-links are [deferred — visual, human-verification.md §4.4].
//
// --- Phase A semantics (spec §2) ---
// Input Monitoring is NON-BLOCKING: its absence does NOT prevent isComplete == true
// and does NOT appear in blockingPermissions. Only Mic + Accessibility are blocking.
// IM still has its own step so the user is shown how to grant it, but the machine
// advances past it to completion regardless of its state.

import Testing
import Foundation
@testable import SpeakCore

// MARK: - All granted + complete

@Test
func allGrantedAndCompleted_isComplete() {
    let eval = OnboardingStateMachine.evaluate(
        microphone: .granted,
        accessibility: .granted,
        inputMonitoring: .granted,
        hasCompletedOnboarding: true
    )
    #expect(eval.isComplete == true)
    #expect(eval.currentStep == .done)
    #expect(eval.blockingPermissions.isEmpty)
}

// MARK: - All granted but flag not yet set

@Test
func allGrantedButFlagNotSet_isHotkeyStep() {
    let eval = OnboardingStateMachine.evaluate(
        microphone: .granted,
        accessibility: .granted,
        inputMonitoring: .granted,
        hasCompletedOnboarding: false
    )
    #expect(eval.isComplete == false)
    #expect(eval.currentStep == .hotkey)
    #expect(eval.blockingPermissions.isEmpty)
}

// MARK: - Only microphone missing

@Test
func onlyMicMissing_notDetermined_isMicStep() {
    let eval = OnboardingStateMachine.evaluate(
        microphone: .notDetermined,
        accessibility: .granted,
        inputMonitoring: .granted,
        hasCompletedOnboarding: false
    )
    #expect(eval.currentStep == .microphone)
    #expect(eval.blockingPermissions == [.microphone])
}

@Test
func onlyMicMissing_denied_isMicStep() {
    let eval = OnboardingStateMachine.evaluate(
        microphone: .denied,
        accessibility: .granted,
        inputMonitoring: .granted,
        hasCompletedOnboarding: false
    )
    #expect(eval.currentStep == .microphone)
    #expect(eval.blockingPermissions == [.microphone])
    #expect(eval.isComplete == false)
}

// MARK: - Only accessibility missing

@Test
func onlyAccessibilityMissing_isAccessibilityStep() {
    let eval = OnboardingStateMachine.evaluate(
        microphone: .granted,
        accessibility: .notDetermined,
        inputMonitoring: .granted,
        hasCompletedOnboarding: false
    )
    #expect(eval.currentStep == .accessibility)
    #expect(eval.blockingPermissions == [.accessibility])
}

// MARK: - Input Monitoring non-blocking (Phase A, spec §2)

/// Core Phase A invariant: IM absence alone DOES NOT block completion.
@Test
func inputMonitoringMissing_withCompletedFlag_isComplete() {
    // Mic + AX granted, IM missing, flag set → complete (IM is non-blocking).
    let eval = OnboardingStateMachine.evaluate(
        microphone: .granted,
        accessibility: .granted,
        inputMonitoring: .notDetermined,
        hasCompletedOnboarding: true
    )
    #expect(eval.isComplete == true, "IM absence must not block isComplete when Mic+AX are granted")
    #expect(eval.currentStep == .done)
    #expect(eval.blockingPermissions.isEmpty, "blockingPermissions must not include .inputMonitoring")
}

@Test
func inputMonitoringDenied_withCompletedFlag_isComplete() {
    let eval = OnboardingStateMachine.evaluate(
        microphone: .granted,
        accessibility: .granted,
        inputMonitoring: .denied,
        hasCompletedOnboarding: true
    )
    #expect(eval.isComplete == true)
    #expect(eval.blockingPermissions.isEmpty)
}

/// IM still surfaces as a step during onboarding (so the user is guided to grant it),
/// but its absence does NOT appear in blockingPermissions.
@Test
func onlyInputMonitoringMissing_isInputMonitoringStep_notBlocking() {
    let eval = OnboardingStateMachine.evaluate(
        microphone: .granted,
        accessibility: .granted,
        inputMonitoring: .notDetermined,
        hasCompletedOnboarding: false
    )
    // Step surfaces as inputMonitoring (UI guides user to grant it).
    #expect(eval.currentStep == .inputMonitoring)
    // NOT a blocking permission.
    #expect(eval.blockingPermissions.isEmpty, "IM should not be in blockingPermissions")
    // Not complete because flag is not set (user needs to tap Done in onboarding).
    #expect(eval.isComplete == false)
}

@Test
func onlyInputMonitoringDenied_isInputMonitoringStep_notBlocking() {
    let eval = OnboardingStateMachine.evaluate(
        microphone: .granted,
        accessibility: .granted,
        inputMonitoring: .denied,
        hasCompletedOnboarding: false
    )
    #expect(eval.currentStep == .inputMonitoring)
    #expect(eval.blockingPermissions.isEmpty)
}

// MARK: - Multiple permissions missing (ordering — only mic + AX in blocking)

@Test
func micAndAccessibilityMissing_firstStepIsMic() {
    let eval = OnboardingStateMachine.evaluate(
        microphone: .notDetermined,
        accessibility: .notDetermined,
        inputMonitoring: .granted,
        hasCompletedOnboarding: false
    )
    #expect(eval.currentStep == .microphone)
    // Both mic and AX are blocking; IM is not.
    #expect(eval.blockingPermissions == [.microphone, .accessibility])
}

@Test
func allMissing_firstStepIsMic_twoBlockers() {
    // Phase A: only mic + AX are blocking; IM is NOT in blockingPermissions even when missing.
    let eval = OnboardingStateMachine.evaluate(
        microphone: .notDetermined,
        accessibility: .notDetermined,
        inputMonitoring: .notDetermined,
        hasCompletedOnboarding: false
    )
    #expect(eval.currentStep == .microphone)
    // Only 2 blocking permissions (mic + AX); IM is excluded.
    #expect(eval.blockingPermissions == [.microphone, .accessibility])
    #expect(eval.isComplete == false)
}

@Test
func accessibilityAndInputMissing_firstStepIsAccessibility() {
    // IM missing but not blocking — AX still is.
    let eval = OnboardingStateMachine.evaluate(
        microphone: .granted,
        accessibility: .denied,
        inputMonitoring: .denied,
        hasCompletedOnboarding: false
    )
    #expect(eval.currentStep == .accessibility)
    // Only AX is blocking; IM is not.
    #expect(eval.blockingPermissions == [.accessibility])
}

// MARK: - Restricted state (counts as not-granted for blocking permissions)

@Test
func micRestricted_isMicStep() {
    let eval = OnboardingStateMachine.evaluate(
        microphone: .restricted,
        accessibility: .granted,
        inputMonitoring: .granted,
        hasCompletedOnboarding: false
    )
    #expect(eval.currentStep == .microphone)
    #expect(eval.blockingPermissions == [.microphone])
    #expect(eval.isComplete == false)
}

// MARK: - hasCompletedOnboarding true but required permissions missing (re-show path)

@Test
func completedFlagTrueButMicDenied_notComplete() {
    // If the user revokes microphone after completing onboarding, re-show onboarding.
    let eval = OnboardingStateMachine.evaluate(
        microphone: .denied,
        accessibility: .granted,
        inputMonitoring: .granted,
        hasCompletedOnboarding: true
    )
    #expect(eval.isComplete == false)
    #expect(eval.currentStep == .microphone)
}

@Test
func completedFlagTrueButMicAndAxDenied_twoBlockers() {
    // Phase A: only mic + AX block. Even with IM denied, only 2 blockers.
    let eval = OnboardingStateMachine.evaluate(
        microphone: .denied,
        accessibility: .denied,
        inputMonitoring: .denied,
        hasCompletedOnboarding: true
    )
    #expect(eval.isComplete == false)
    #expect(eval.blockingPermissions.count == 2, "Only mic + AX block; IM is non-blocking")
    #expect(eval.blockingPermissions.contains(.microphone))
    #expect(eval.blockingPermissions.contains(.accessibility))
    #expect(!eval.blockingPermissions.contains(.inputMonitoring))
}

// MARK: - PermissionState coverage

@Test
func requestingStateCountsAsNotGranted() {
    // `.requesting` is a transient state while the mic dialog is open.
    let eval = OnboardingStateMachine.evaluate(
        microphone: .requesting,
        accessibility: .granted,
        inputMonitoring: .granted,
        hasCompletedOnboarding: false
    )
    #expect(eval.currentStep == .microphone)
    #expect(eval.blockingPermissions == [.microphone])
}
