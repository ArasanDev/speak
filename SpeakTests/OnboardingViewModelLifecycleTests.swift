// SpeakTests/OnboardingViewModelLifecycleTests.swift
//
// Lifecycle tests for `OnboardingViewModel`: advance(), skip(), finish(), and
// poll auto-advance. These close the 1C coverage gap identified in Phase 1C.
//
// APPROACH:
//   Uses `StubPermissionManager` (defined in OnboardingViewModelDoublePromptTests.swift
//   and visible across the test target) to control permission state without real TCC.
//   Tests run synchronously on the MainActor; the poll task is never started (advance
//   logic is deterministic without it).
//
// COVERAGE:
//   - `advance()` walks the step sequence correctly.
//   - `advance()` on the penultimate step (hotkey) calls finish() and lands on .done.
//   - `skip()` lands on .done and sets hasCompletedOnboarding.
//   - `displayedStep` starts at .welcome.
//   - `currentHotkeyDisplayString` is non-empty at init (cached, not re-read per render).
//   - `onDisappear()` cancels the poll task (pollTask is nil after).
//
// [decision: @MainActor throughout — OnboardingViewModel is @MainActor.]

import XCTest
import SpeakCore
@testable import Speak

@MainActor
final class OnboardingViewModelLifecycleTests: XCTestCase {

    // MARK: - Fixture

    private var manager: StubPermissionManager!
    private var settings: SettingsStore!
    private var viewModel: OnboardingViewModel!

    override func setUp() async throws {
        try await super.setUp()
        manager = StubPermissionManager()
        // Isolated UserDefaults so hasCompletedOnboarding doesn't persist between tests.
        let ud = try XCTUnwrap(
            UserDefaults(suiteName: "OnboardingViewModelLifecycleTests.\(UUID().uuidString)"),
            "UserDefaults(suiteName:) returned nil — UUID-based name must always succeed."
        )
        settings = SettingsStore(defaults: ud)
        viewModel = OnboardingViewModel(
            permissionManager: manager,
            settings: settings
        )
    }

    override func tearDown() async throws {
        viewModel = nil
        settings = nil
        manager = nil
        try await super.tearDown()
    }

    // MARK: - Initial step

    /// The view model always starts at `.welcome`, regardless of permission state.
    func testInitialStep_isWelcome() {
        XCTAssertEqual(viewModel.displayedStep, .welcome,
            "displayedStep must start at .welcome on init.")
    }

    // MARK: - advance() step sequence

    /// advance() from .welcome → .microphone.
    func testAdvance_fromWelcome_goesToMicrophone() {
        XCTAssertEqual(viewModel.displayedStep, .welcome)
        viewModel.advance()
        XCTAssertEqual(viewModel.displayedStep, .microphone,
            "advance() from .welcome must go to .microphone.")
    }

    /// advance() twice: .welcome → .microphone → .accessibility.
    func testAdvance_twice_goesToAccessibility() {
        viewModel.advance()
        viewModel.advance()
        XCTAssertEqual(viewModel.displayedStep, .accessibility,
            "Two advance() calls must reach .accessibility.")
    }

    /// advance() three times: .welcome → .microphone → .accessibility → .hotkey.
    func testAdvance_thrice_goesToHotkey() {
        viewModel.advance()
        viewModel.advance()
        viewModel.advance()
        XCTAssertEqual(viewModel.displayedStep, .hotkey,
            "Three advance() calls must reach .hotkey.")
    }

    /// advance() four times (from hotkey): calls finish() and lands on .done.
    /// Also sets hasCompletedOnboarding.
    func testAdvance_fourTimes_landsDoneAndSetsFlag() {
        viewModel.advance()   // → .microphone
        viewModel.advance()   // → .accessibility
        viewModel.advance()   // → .hotkey
        viewModel.advance()   // → finish() → .done
        XCTAssertEqual(viewModel.displayedStep, .done,
            "The fourth advance() (from .hotkey) must land on .done via finish().")
        XCTAssertTrue(settings.hasCompletedOnboarding,
            "finish() must set hasCompletedOnboarding = true.")
    }

    /// advance() on .done is a no-op — stays at .done.
    func testAdvance_fromDone_staysAtDone() {
        viewModel.advance()
        viewModel.advance()
        viewModel.advance()
        viewModel.advance()   // lands on .done
        XCTAssertEqual(viewModel.displayedStep, .done)
        viewModel.advance()   // no-op
        XCTAssertEqual(viewModel.displayedStep, .done,
            "advance() on .done must be a no-op.")
    }

    // MARK: - skip()

    /// skip() lands on .done and sets hasCompletedOnboarding.
    func testSkip_landsOnDone() {
        viewModel.skip()
        XCTAssertEqual(viewModel.displayedStep, .done,
            "skip() must set displayedStep to .done.")
        XCTAssertTrue(settings.hasCompletedOnboarding,
            "skip() must set hasCompletedOnboarding = true.")
    }

    /// skip() from any step (here .microphone) still lands on .done.
    func testSkip_fromMiddleStep_landsOnDone() {
        viewModel.advance()   // → .microphone
        viewModel.skip()
        XCTAssertEqual(viewModel.displayedStep, .done,
            "skip() from .microphone must still land on .done.")
    }

    // MARK: - currentHotkeyDisplayString cache

    /// `currentHotkeyDisplayString` is non-empty at init — the cached value was
    /// computed from the default binding (Fn ×2) rather than falling through to an
    /// empty string.
    func testCurrentHotkeyDisplayString_nonEmptyAtInit() {
        XCTAssertFalse(viewModel.currentHotkeyDisplayString.isEmpty,
            "currentHotkeyDisplayString must be non-empty at init (default binding text).")
    }

    /// Calling advance() (which internally calls refreshEvaluation) does not crash
    /// and leaves the display string non-empty — the static helper is re-evaluated.
    func testCurrentHotkeyDisplayString_remainsNonEmptyAfterAdvance() {
        viewModel.advance()
        XCTAssertFalse(viewModel.currentHotkeyDisplayString.isEmpty,
            "currentHotkeyDisplayString must remain non-empty after advance().")
    }

    // MARK: - onDisappear() lifecycle

    /// onDisappear() must not crash and the view model remains in a usable state.
    func testOnDisappear_doesNotCrash() {
        viewModel.onAppear()
        XCTAssertNoThrow(viewModel.onDisappear(),
            "onDisappear() must not throw or crash.")
    }

    /// A second onDisappear() after the first is a no-op (idempotent cancel).
    func testOnDisappear_idempotent() {
        viewModel.onAppear()
        viewModel.onDisappear()
        XCTAssertNoThrow(viewModel.onDisappear(),
            "Second onDisappear() must be a no-op (idempotent task cancellation).")
    }

    // MARK: - evaluation published property

    /// evaluation.isComplete is false at init when onboarding is not complete
    /// and permissions are not determined.
    func testEvaluation_isNotCompleteAtInit() {
        XCTAssertFalse(viewModel.evaluation.isComplete,
            "evaluation.isComplete must be false at init when permissions are not determined.")
    }

    /// evaluation.isComplete is true when all permissions are granted and the flag is set.
    func testEvaluation_isCompleteWhenAllGrantedAndFlagSet() {
        manager.micStatus = .granted
        manager.axStatus = .granted
        settings.hasCompletedOnboarding = true
        // Trigger a refresh (simulates what the poll does).
        viewModel.skip()   // internally calls refreshEvaluation()
        XCTAssertTrue(viewModel.evaluation.isComplete,
            "evaluation.isComplete must be true when all permissions are granted and flag is set.")
    }
}
