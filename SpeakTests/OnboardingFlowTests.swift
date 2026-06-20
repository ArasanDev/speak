// SpeakTests/OnboardingFlowTests.swift
//
// Unit tests for `OnboardingStateMachine` (SpeakCore/Permissions/OnboardingState.swift).
//
// This is the "headless-verifiable slice" of P7: the step machine is pure value
// logic with zero UI dependencies. All paths are exercised here. The rendered
// onboarding flow and live deep-links are [deferred — visual, human-verification.md §4.4].

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

// MARK: - Only inputMonitoring missing

@Test
func onlyInputMonitoringMissing_isInputMonitoringStep() {
    let eval = OnboardingStateMachine.evaluate(
        microphone: .granted,
        accessibility: .granted,
        inputMonitoring: .notDetermined,
        hasCompletedOnboarding: false
    )
    #expect(eval.currentStep == .inputMonitoring)
    #expect(eval.blockingPermissions == [.inputMonitoring])
}

@Test
func onlyInputMonitoringDenied_isInputMonitoringStep() {
    let eval = OnboardingStateMachine.evaluate(
        microphone: .granted,
        accessibility: .granted,
        inputMonitoring: .denied,
        hasCompletedOnboarding: false
    )
    #expect(eval.currentStep == .inputMonitoring)
    #expect(eval.blockingPermissions == [.inputMonitoring])
}

// MARK: - Multiple permissions missing (ordering)

@Test
func micAndAccessibilityMissing_firstStepIsMic() {
    let eval = OnboardingStateMachine.evaluate(
        microphone: .notDetermined,
        accessibility: .notDetermined,
        inputMonitoring: .granted,
        hasCompletedOnboarding: false
    )
    #expect(eval.currentStep == .microphone)
    #expect(eval.blockingPermissions == [.microphone, .accessibility])
}

@Test
func allMissing_firstStepIsMic() {
    let eval = OnboardingStateMachine.evaluate(
        microphone: .notDetermined,
        accessibility: .notDetermined,
        inputMonitoring: .notDetermined,
        hasCompletedOnboarding: false
    )
    #expect(eval.currentStep == .microphone)
    #expect(eval.blockingPermissions == [.microphone, .accessibility, .inputMonitoring])
    #expect(eval.isComplete == false)
}

@Test
func accessibilityAndInputMissing_firstStepIsAccessibility() {
    let eval = OnboardingStateMachine.evaluate(
        microphone: .granted,
        accessibility: .denied,
        inputMonitoring: .denied,
        hasCompletedOnboarding: false
    )
    #expect(eval.currentStep == .accessibility)
    #expect(eval.blockingPermissions == [.accessibility, .inputMonitoring])
}

// MARK: - Restricted state (counts as not-granted)

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

// MARK: - hasCompletedOnboarding true but permissions missing (re-show path)

@Test
func completedFlagTrueButMicDenied_notComplete() {
    // If the user revokes microphone after completing onboarding, they should
    // be re-shown onboarding when the app starts (the OR clause in show-on-launch).
    // The machine correctly reflects incomplete state regardless of the flag.
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
func completedFlagTrueButAllDenied_notComplete() {
    let eval = OnboardingStateMachine.evaluate(
        microphone: .denied,
        accessibility: .denied,
        inputMonitoring: .denied,
        hasCompletedOnboarding: true
    )
    #expect(eval.isComplete == false)
    #expect(eval.blockingPermissions.count == 3)
}

// MARK: - PermissionState coverage

@Test
func requestingStateCountsAsNotGranted() {
    // `.requesting` is a transient state while the mic dialog is open.
    // The machine treats it as not-yet-granted so the step doesn't advance.
    let eval = OnboardingStateMachine.evaluate(
        microphone: .requesting,
        accessibility: .granted,
        inputMonitoring: .granted,
        hasCompletedOnboarding: false
    )
    #expect(eval.currentStep == .microphone)
    #expect(eval.blockingPermissions == [.microphone])
}
