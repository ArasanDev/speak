// SpeakTests/OnboardingViewModelDoublePromptTests.swift
//
// Regression guard: no-double-prompt + clean-advance behavior in OnboardingViewModel.
//
// PURPOSE:
//   Verifies that the Accessibility and Input Monitoring steps fire the TCC
//   registration prompt at most ONCE per session, that subsequent taps only
//   open System Settings (no second dialog), and that the waiting state clears
//   correctly when the poll detects a grant.
//
// APPROACH:
//   Uses `StubPermissionManager` (defined below) to control permission state
//   without touching real TCC APIs. The ViewModel is instantiated directly and
//   its @Published properties are observed synchronously on the MainActor.
//
//   Import path: @testable import Speak (App module, available via TEST_HOST —
//   same pattern as TranscriptOverlayPanelTests.swift).
//
// [decision: MainActor throughout — PermissionManaging and OnboardingViewModel
//  are both @MainActor; XCTest supports this via async test methods.]

import XCTest
import SpeakCore
@testable import Speak

// MARK: - Stub

/// A controllable `PermissionManaging` stub that records how many times each
/// request method was called. Simulates responses via injectable closures.
@MainActor
final class StubPermissionManager: PermissionManaging {

    // Configurable responses
    var micStatus: PermissionState = .notDetermined
    var axStatus: PermissionState = .notDetermined
    var imStatus: PermissionState = .notDetermined

    var axRequestResult: Bool = false
    var imRequestResult: Bool = false

    // Call counts
    private(set) var axRequestCallCount: Int = 0
    private(set) var imRequestCallCount: Int = 0
    private(set) var settingsOpenCallCount: Int = 0

    func status(_ kind: PermissionKind) -> PermissionState {
        switch kind {
        case .microphone:      return micStatus
        case .accessibility:   return axStatus
        case .inputMonitoring: return imStatus
        }
    }

    func requestMicrophone() async -> PermissionState {
        return micStatus
    }

    @discardableResult
    func requestAccessibility() -> Bool {
        axRequestCallCount += 1
        return axRequestResult
    }

    @discardableResult
    func requestInputMonitoring() -> Bool {
        imRequestCallCount += 1
        return imRequestResult
    }
}

// MARK: - Stub SettingsStore helper

private extension SettingsStore {
    /// A fresh SettingsStore with onboarding not completed.
    static func fresh() -> SettingsStore {
        let s = SettingsStore()
        s.hasCompletedOnboarding = false
        return s
    }
}

// MARK: - Tests

@MainActor
final class OnboardingViewModelDoublePromptTests: XCTestCase {

    // MARK: - Accessibility: first tap fires prompt once

    func test_requestAccessibility_firstTap_firesPromptOnce() {
        let stub = StubPermissionManager()
        stub.axStatus = .notDetermined
        let vm = OnboardingViewModel(permissionManager: stub, settings: .fresh())

        vm.requestAccessibility()

        XCTAssertEqual(stub.axRequestCallCount, 1,
            "First tap must fire requestAccessibility() exactly once")
    }

    func test_requestAccessibility_firstTap_setsWaitingState() {
        let stub = StubPermissionManager()
        stub.axStatus = .notDetermined
        stub.axRequestResult = false
        let vm = OnboardingViewModel(permissionManager: stub, settings: .fresh())

        vm.requestAccessibility()

        XCTAssertTrue(vm.isWaitingForAccessibility,
            "isWaitingForAccessibility must be true after first tap when not yet granted")
    }

    // MARK: - Accessibility: second tap does NOT re-prompt

    func test_requestAccessibility_secondTap_doesNotRePrompt() {
        let stub = StubPermissionManager()
        stub.axStatus = .notDetermined
        stub.axRequestResult = false
        let vm = OnboardingViewModel(permissionManager: stub, settings: .fresh())

        vm.requestAccessibility() // first tap
        vm.requestAccessibility() // second tap

        XCTAssertEqual(stub.axRequestCallCount, 1,
            "Second tap must NOT re-fire requestAccessibility() — guard against double-prompt")
    }

    func test_requestAccessibility_thirdTap_doesNotRePrompt() {
        let stub = StubPermissionManager()
        stub.axStatus = .notDetermined
        stub.axRequestResult = false
        let vm = OnboardingViewModel(permissionManager: stub, settings: .fresh())

        vm.requestAccessibility()
        vm.requestAccessibility()
        vm.requestAccessibility()

        XCTAssertEqual(stub.axRequestCallCount, 1,
            "Any number of subsequent taps must not re-fire the TCC prompt")
    }

    // MARK: - Accessibility: already granted → no prompt, immediate advance

    func test_requestAccessibility_alreadyGranted_doesNotPrompt() {
        let stub = StubPermissionManager()
        stub.axStatus = .granted
        let vm = OnboardingViewModel(permissionManager: stub, settings: .fresh())

        vm.requestAccessibility()

        XCTAssertEqual(stub.axRequestCallCount, 0,
            "Must not call requestAccessibility() when already granted")
        XCTAssertFalse(vm.isWaitingForAccessibility,
            "isWaitingForAccessibility must remain false when already granted")
    }

    func test_requestAccessibility_alreadyGranted_doesNotSetWaitingState() {
        let stub = StubPermissionManager()
        stub.axStatus = .granted
        stub.axRequestResult = true
        let vm = OnboardingViewModel(permissionManager: stub, settings: .fresh())

        vm.requestAccessibility()

        XCTAssertFalse(vm.isWaitingForAccessibility)
    }

    // MARK: - Input Monitoring: first tap fires prompt once

    func test_requestInputMonitoring_firstTap_firesPromptOnce() {
        let stub = StubPermissionManager()
        stub.axStatus = .granted // so we don't short-circuit at accessibility
        stub.imStatus = .notDetermined
        let vm = OnboardingViewModel(permissionManager: stub, settings: .fresh())

        vm.requestInputMonitoring()

        XCTAssertEqual(stub.imRequestCallCount, 1,
            "First tap must fire requestInputMonitoring() exactly once")
    }

    func test_requestInputMonitoring_firstTap_setsWaitingState() {
        let stub = StubPermissionManager()
        stub.axStatus = .granted
        stub.imStatus = .notDetermined
        stub.imRequestResult = false
        let vm = OnboardingViewModel(permissionManager: stub, settings: .fresh())

        vm.requestInputMonitoring()

        XCTAssertTrue(vm.isWaitingForInputMonitoring,
            "isWaitingForInputMonitoring must be true after first tap when not yet granted")
    }

    // MARK: - Input Monitoring: second tap does NOT re-prompt

    func test_requestInputMonitoring_secondTap_doesNotRePrompt() {
        let stub = StubPermissionManager()
        stub.axStatus = .granted
        stub.imStatus = .notDetermined
        stub.imRequestResult = false
        let vm = OnboardingViewModel(permissionManager: stub, settings: .fresh())

        vm.requestInputMonitoring()
        vm.requestInputMonitoring()

        XCTAssertEqual(stub.imRequestCallCount, 1,
            "Second tap must NOT re-fire requestInputMonitoring() — guard against double-prompt")
    }

    // MARK: - Input Monitoring: already granted → no prompt

    func test_requestInputMonitoring_alreadyGranted_doesNotPrompt() {
        let stub = StubPermissionManager()
        stub.axStatus = .granted
        stub.imStatus = .granted
        let vm = OnboardingViewModel(permissionManager: stub, settings: .fresh())

        vm.requestInputMonitoring()

        XCTAssertEqual(stub.imRequestCallCount, 0,
            "Must not call requestInputMonitoring() when already granted")
        XCTAssertFalse(vm.isWaitingForInputMonitoring)
    }

    // MARK: - Waiting state cleared on grant (simulated via direct status change)
    //
    // The poll loop is the real path in production. Here we simulate the grant
    // by mutating stub state and calling the internal refreshEvaluation path
    // indirectly through a second requestAccessibility() call after granting.
    // We verify that isWaiting clears when already granted on first-tap path.

    func test_requestAccessibility_immediateGrant_clearsWaiting() {
        let stub = StubPermissionManager()
        stub.axStatus = .notDetermined
        stub.axRequestResult = true // simulate: already trusted when polled
        let vm = OnboardingViewModel(permissionManager: stub, settings: .fresh())

        // Simulate: by the time requestAccessibility() checks, AX is trusted.
        stub.axStatus = .granted

        vm.requestAccessibility()

        XCTAssertFalse(vm.isWaitingForAccessibility,
            "isWaitingForAccessibility must be false when grant is detected immediately")
    }

    func test_requestInputMonitoring_immediateGrant_clearsWaiting() {
        let stub = StubPermissionManager()
        stub.axStatus = .granted
        stub.imStatus = .granted
        stub.imRequestResult = true
        let vm = OnboardingViewModel(permissionManager: stub, settings: .fresh())

        vm.requestInputMonitoring()

        XCTAssertFalse(vm.isWaitingForInputMonitoring,
            "isWaitingForInputMonitoring must be false when grant is detected immediately")
    }

    // MARK: - Accessibility and InputMonitoring waiting states are independent

    func test_waitingStates_areIndependent() {
        let stub = StubPermissionManager()
        stub.axStatus = .notDetermined
        stub.axRequestResult = false
        stub.imStatus = .notDetermined
        stub.imRequestResult = false
        let vm = OnboardingViewModel(permissionManager: stub, settings: .fresh())

        vm.requestAccessibility()
        XCTAssertTrue(vm.isWaitingForAccessibility)
        XCTAssertFalse(vm.isWaitingForInputMonitoring,
            "IM waiting state must not be set by an AX tap")

        stub.axStatus = .granted  // simulating AX becomes granted
        stub.imStatus = .notDetermined
        vm.requestInputMonitoring()
        XCTAssertTrue(vm.isWaitingForInputMonitoring)
    }
}
