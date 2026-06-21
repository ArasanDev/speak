// SpeakTests/OnboardingFlowTests.swift
//
// Unit tests for `OnboardingStateMachine` (SpeakCore/Permissions/OnboardingState.swift).
//
// This is the "headless-verifiable slice" of P7: the step machine is pure value
// logic with zero UI dependencies. All paths are exercised here. The rendered
// onboarding flow and live deep-links are [deferred — visual, human-verification.md §4.4].
//
// Step order: welcome → microphone → accessibility → hotkey → done
// Blocking permissions: Microphone + Accessibility only.
// Input Monitoring was removed from the flow — the CGEventTap uses .defaultTap
// and is gated on Accessibility alone (verified: HotkeyMonitor.swift §84–86).

import Testing
import Foundation
@testable import SpeakCore

// MARK: - All granted + complete

@Test
func allGrantedAndCompleted_isComplete() {
    let eval = OnboardingStateMachine.evaluate(
        microphone: .granted,
        accessibility: .granted,
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
        hasCompletedOnboarding: false
    )
    #expect(eval.currentStep == .accessibility)
    #expect(eval.blockingPermissions == [.accessibility])
}

// MARK: - Multiple permissions missing (ordering)

@Test
func micAndAccessibilityMissing_firstStepIsMic() {
    let eval = OnboardingStateMachine.evaluate(
        microphone: .notDetermined,
        accessibility: .notDetermined,
        hasCompletedOnboarding: false
    )
    #expect(eval.currentStep == .microphone)
    #expect(eval.blockingPermissions == [.microphone, .accessibility])
}

@Test
func allMissing_firstStepIsMic_twoBlockers() {
    let eval = OnboardingStateMachine.evaluate(
        microphone: .notDetermined,
        accessibility: .notDetermined,
        hasCompletedOnboarding: false
    )
    #expect(eval.currentStep == .microphone)
    #expect(eval.blockingPermissions == [.microphone, .accessibility])
    #expect(eval.isComplete == false)
}

@Test
func accessibilityMissing_flagSet_notComplete() {
    let eval = OnboardingStateMachine.evaluate(
        microphone: .granted,
        accessibility: .denied,
        hasCompletedOnboarding: false
    )
    #expect(eval.currentStep == .accessibility)
    #expect(eval.blockingPermissions == [.accessibility])
}

// MARK: - Restricted state (counts as not-granted for blocking permissions)

@Test
func micRestricted_isMicStep() {
    let eval = OnboardingStateMachine.evaluate(
        microphone: .restricted,
        accessibility: .granted,
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
        hasCompletedOnboarding: true
    )
    #expect(eval.isComplete == false)
    #expect(eval.currentStep == .microphone)
}

@Test
func completedFlagTrueButMicAndAxDenied_twoBlockers() {
    let eval = OnboardingStateMachine.evaluate(
        microphone: .denied,
        accessibility: .denied,
        hasCompletedOnboarding: true
    )
    #expect(eval.isComplete == false)
    #expect(eval.blockingPermissions.count == 2, "Only mic + AX block")
    #expect(eval.blockingPermissions.contains(.microphone))
    #expect(eval.blockingPermissions.contains(.accessibility))
}

// MARK: - PermissionState coverage

@Test
func requestingStateCountsAsNotGranted() {
    // `.requesting` is a transient state while the mic dialog is open.
    let eval = OnboardingStateMachine.evaluate(
        microphone: .requesting,
        accessibility: .granted,
        hasCompletedOnboarding: false
    )
    #expect(eval.currentStep == .microphone)
    #expect(eval.blockingPermissions == [.microphone])
}
