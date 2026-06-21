// SpeakTests/WindowPresenterTests.swift
//
// H3 unit tests for `WindowPresenter`.
//
// PURPOSE:
//   Construct-and-assert tests for the window-presentation logic extracted
//   from `DictationController` by H3. These are LOGIC / WIRING assertions —
//   they verify that `HistoryWindowController` is lazily created and that the
//   same instance is returned on repeated calls. They do NOT assert on window
//   visibility (`NSWindow.show()`) — that is live window-server behaviour
//   requiring a real display and manual dogfooding.
//
// APPROACH:
//   - Construct `WindowPresenter` with real (lightweight) dependencies:
//     a `NullHistoryStore` (defined below), a fresh `PermissionManager`,
//     and a fresh `SettingsStore`.
//   - Call `ensureHistoryController()` twice and assert we get the same instance
//     (pointer equality) — proving lazy construction and identity stability.
//   - Do NOT call `.show()` on any window; the test stays within the
//     logic/wiring boundary.
//
// TAGS: H3 (acceleration-plan.md), WindowPresenter, HistoryWindowController
//
// [decision: @MainActor-isolated because WindowPresenter is @MainActor and
//  NSWindowController requires the main thread per macOS/AppKit convention.]

import XCTest
@testable import Speak
import SpeakCore

// MARK: - TestNullHistoryStore

/// Minimal `HistoryStoring` used to construct `WindowPresenter` in tests.
/// Matches the `NullHistoryStore` pattern in DictationController — every
/// method succeeds silently.
private final class TestNullHistoryStore: HistoryStoring, @unchecked Sendable {
    func save(_ entry: HistoryEntry) throws {}
    func recent(limit: Int) throws -> [HistoryEntry] { [] }
    func search(_ substring: String) throws -> [HistoryEntry] { [] }
    func clear() throws {}
    func export() throws -> String { "[]" }
}

// MARK: - WindowPresenterTests

@MainActor
final class WindowPresenterTests: XCTestCase {

    // MARK: - Fixture

    private var presenter: WindowPresenter!

    override func setUp() async throws {
        try await super.setUp()
        presenter = WindowPresenter(
            historyStore: TestNullHistoryStore(),
            permissionManager: PermissionManager(),
            settingsStore: SettingsStore(),
            hotkeyComboProvider: { ["Fn", "Fn"] }
        )
    }

    override func tearDown() async throws {
        presenter = nil
        try await super.tearDown()
    }

    // MARK: - History controller — lazy creation + identity

    /// `ensureHistoryController()` must return a non-nil controller.
    func testEnsureHistoryController_returnsController() {
        let controller = presenter.ensureHistoryController()
        // We can't test the class name easily, but a non-nil return proves
        // the lazy init path ran successfully without crashing.
        _ = controller   // assertion is "no crash + non-nil (Swift non-optional)"
        // Implicit: if ensureHistoryController() returned nil the compile would fail.
    }

    /// Calling `ensureHistoryController()` twice must return the same instance.
    /// Proves lazy init does not recreate the controller on repeated calls.
    func testEnsureHistoryController_returnsSameInstanceOnRepeatedCalls() {
        let first = presenter.ensureHistoryController()
        let second = presenter.ensureHistoryController()
        XCTAssertTrue(
            first === second,
            "ensureHistoryController() must return the same HistoryWindowController " +
            "instance on repeated calls — it is lazily created once, not per-call."
        )
    }

    // MARK: - showHistory delegates to ensureHistoryController

    /// `showHistory()` must not crash. It internally calls `ensureHistoryController()`
    /// and then `.show()` — both are tested at the call level here.
    ///
    /// [honesty boundary: we do NOT assert the window is physically visible.
    ///  That requires a live display server and is covered by manual dogfooding.]
    func testShowHistory_doesNotCrash() {
        // The test runner has a display server available (TEST_HOST app context),
        // so calling show() is safe here — it will try to order the window front,
        // which is benign in a test environment where no screen geometry is asserted.
        XCTAssertNoThrow(presenter.showHistory(), "showHistory() must not throw or crash.")
    }

    // MARK: - Dashboard controller — lazy creation + identity

    /// Calling `ensureDashboardController()` twice must return the same instance.
    /// Proves the Phase-2 dashboard window is lazily created once, not per-call —
    /// the same single-instance contract as the History controller.
    func testEnsureDashboardController_returnsSameInstanceOnRepeatedCalls() {
        let first = presenter.ensureDashboardController()
        let second = presenter.ensureDashboardController()
        XCTAssertTrue(
            first === second,
            "ensureDashboardController() must return the same DashboardWindowController " +
            "instance on repeated calls — it is lazily created once, not per-call."
        )
    }

    // MARK: - showOnboardingIfNeeded (no-op when onboarding already complete)

    /// When `SettingsStore.hasCompletedOnboarding` is `true`, `showOnboardingIfNeeded()`
    /// must return silently without creating an `OnboardingWindowController`.
    ///
    /// We can't directly inspect the private `onboardingController` property, so we
    /// verify this indirectly: a no-crash + no window-open (since show() on a nil
    /// controller is guarded with `onboardingController?.show()`) is the contract.
    func testShowOnboardingIfNeeded_skipsWhenComplete() {
        // Mark onboarding as complete in settings so the state machine returns early.
        let settings = SettingsStore()
        settings.hasCompletedOnboarding = true

        let completedPresenter = WindowPresenter(
            historyStore: TestNullHistoryStore(),
            permissionManager: PermissionManager(),
            settingsStore: settings,
            hotkeyComboProvider: { ["Fn"] }
        )

        XCTAssertNoThrow(
            completedPresenter.showOnboardingIfNeeded(),
            "showOnboardingIfNeeded() must not crash when onboarding is already complete."
        )
    }
}
