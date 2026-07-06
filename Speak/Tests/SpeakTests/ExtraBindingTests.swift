// SpeakTests/ExtraBindingTests.swift
//
// Pure-logic and persistence coverage for V01-5 (multiple hotkey bindings per
// action). Tap-level dispatch (CGEventTap mask, live event matching in
// HotkeyMonitor.handle()) is [deferred — needs human verification]; this suite
// covers everything reachable without a live tap:
//   - ExtraBindingSet.adding/removing/action(for:) pure logic
//   - max-4-per-action enforcement
//   - duplicate-source rejection
//   - mouse-button range validation (4...10)
//   - Codable round-trip (ExtraBinding, ExtraBindingSet)
//   - UserDefaultsBindingStore extra-bindings persistence round-trip
//   - SettingsStore.extraBindings persistence round-trip + default

@testable import SpeakCore
import XCTest

// MARK: - ExtraBindingSet.adding

final class ExtraBindingSetAddingTests: XCTestCase {

    func testAddingFirstBindingSucceeds() {
        let set = ExtraBindingSet.empty
        let binding = ExtraBinding(source: .modifierKey(63), action: .activate)
        let updated = set.adding(binding)
        XCTAssertNotNil(updated)
        XCTAssertEqual(updated?.bindings.count, 1)
    }

    func testAddingUpToMaxPerActionSucceeds() {
        var set = ExtraBindingSet.empty
        // 4 distinct mouse buttons, all mapped to .activate.
        for button in 4...7 {
            let binding = ExtraBinding(source: .mouseButton(button), action: .activate)
            guard let updated = set.adding(binding) else {
                return XCTFail("Expected binding \(button) to be added (under the max-4 cap)")
            }
            set = updated
        }
        XCTAssertEqual(set.activateBindings.count, ExtraBindingSet.maxPerAction)
    }

    func testAddingBeyondMaxPerActionFails() throws {
        var set = ExtraBindingSet.empty
        for button in 4...7 {
            set = try XCTUnwrap(set.adding(ExtraBinding(source: .mouseButton(button), action: .activate)))
        }
        // A 5th distinct source for the same action must be rejected.
        let fifth = ExtraBinding(source: .mouseButton(8), action: .activate)
        XCTAssertNil(set.adding(fifth), "A 5th .activate binding must be rejected — max is \(ExtraBindingSet.maxPerAction)")
    }

    func testDifferentActionsHaveIndependentCaps() throws {
        var set = ExtraBindingSet.empty
        for button in 4...7 {
            set = try XCTUnwrap(set.adding(ExtraBinding(source: .mouseButton(button), action: .activate)))
        }
        // .stop has its own independent cap — a .stop binding should still succeed
        // even though .activate is already at the max.
        let stopBinding = ExtraBinding(source: .mouseButton(8), action: .stop)
        XCTAssertNotNil(set.adding(stopBinding))
    }

    func testDuplicateSourceIsRejectedRegardlessOfAction() {
        let set = ExtraBindingSet(bindings: [ExtraBinding(source: .modifierKey(54), action: .activate)])
        // Same source, different action — still a duplicate (one binding per source).
        let duplicate = ExtraBinding(source: .modifierKey(54), action: .stop)
        XCTAssertNil(set.adding(duplicate))
    }

    func testMouseButtonOutsideSupportedRangeIsRejected() {
        let set = ExtraBindingSet.empty
        XCTAssertNil(set.adding(ExtraBinding(source: .mouseButton(0), action: .activate)), "Button 0 (primary click) must never be bindable")
        XCTAssertNil(set.adding(ExtraBinding(source: .mouseButton(2), action: .activate)), "Button 2 (middle click) must never be bindable")
        XCTAssertNil(set.adding(ExtraBinding(source: .mouseButton(11), action: .activate)), "Button 11 is outside the 4...10 range")
        XCTAssertNotNil(set.adding(ExtraBinding(source: .mouseButton(4), action: .activate)), "Button 4 is the lower bound of the supported range")
        XCTAssertNotNil(set.adding(ExtraBinding(source: .mouseButton(10), action: .activate)), "Button 10 is the upper bound of the supported range")
    }
}

// MARK: - ExtraBindingSet.removing / action(for:)

final class ExtraBindingSetLookupTests: XCTestCase {

    func testRemovingByIdDropsOnlyThatBinding() {
        let keep = ExtraBinding(source: .modifierKey(58), action: .activate)
        let drop = ExtraBinding(source: .mouseButton(4), action: .stop)
        let set = ExtraBindingSet(bindings: [keep, drop])

        let updated = set.removing(id: drop.id)
        XCTAssertEqual(updated.bindings, [keep])
    }

    func testRemovingAbsentIdIsANoOp() {
        let binding = ExtraBinding(source: .modifierKey(58), action: .activate)
        let set = ExtraBindingSet(bindings: [binding])
        let updated = set.removing(id: UUID())
        XCTAssertEqual(updated, set)
    }

    func testActionForSourceReturnsMatch() {
        let binding = ExtraBinding(source: .mouseButton(5), action: .stop)
        let set = ExtraBindingSet(bindings: [binding])
        XCTAssertEqual(set.action(for: .mouseButton(5)), .stop)
    }

    func testActionForSourceReturnsNilWhenUnbound() {
        let set = ExtraBindingSet.empty
        XCTAssertNil(set.action(for: .mouseButton(5)))
    }

    func testHasMouseBindingReflectsContents() {
        XCTAssertFalse(ExtraBindingSet.empty.hasMouseBinding)
        let keyboardOnly = ExtraBindingSet(bindings: [ExtraBinding(source: .modifierKey(63), action: .activate)])
        XCTAssertFalse(keyboardOnly.hasMouseBinding)
        let withMouse = ExtraBindingSet(bindings: [ExtraBinding(source: .mouseButton(4), action: .activate)])
        XCTAssertTrue(withMouse.hasMouseBinding)
    }
}

// MARK: - Codable round-trip

final class ExtraBindingCodableTests: XCTestCase {

    func testExtraBindingSetRoundTripsThroughJSON() throws {
        let set = ExtraBindingSet(bindings: [
            ExtraBinding(source: .modifierKey(63), action: .activate),
            ExtraBinding(source: .mouseButton(4), action: .stop)
        ])
        let data = try JSONEncoder().encode(set)
        let decoded = try JSONDecoder().decode(ExtraBindingSet.self, from: data)
        XCTAssertEqual(decoded, set)
    }

    func testEmptySetRoundTrips() throws {
        let data = try JSONEncoder().encode(ExtraBindingSet.empty)
        let decoded = try JSONDecoder().decode(ExtraBindingSet.self, from: data)
        XCTAssertEqual(decoded, ExtraBindingSet.empty)
    }
}

// MARK: - UserDefaultsBindingStore extra-bindings persistence

final class BindingStoreExtraBindingsTests: XCTestCase {

    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: "com.speak.extraHotkeyBindings")
    }

    func testSaveAndLoadRoundTrip() throws {
        let store = UserDefaultsBindingStore()
        let set = ExtraBindingSet(bindings: [ExtraBinding(source: .modifierKey(63), action: .activate)])
        store.saveExtraBindings(set)

        let loaded = try XCTUnwrap(store.loadExtraBindings())
        XCTAssertEqual(loaded, set)
    }

    func testLoadReturnsNilWhenNothingStored() {
        let store = UserDefaultsBindingStore()
        XCTAssertNil(store.loadExtraBindings())
    }
}

// MARK: - SettingsStore.extraBindings persistence

final class SettingsStoreExtraBindingsTests: XCTestCase {

    /// `throws` so callers propagate via `try` — avoids force-unwrap in test code
    /// (same pattern as `SettingsStoreTests.makeIsolatedDefaults()`).
    private func makeStore() throws -> SettingsStore {
        let name = "SettingsStoreExtraBindingsTests.\(UUID().uuidString)"
        let ud = try XCTUnwrap(
            UserDefaults(suiteName: name),
            "UserDefaults(suiteName:) returned nil — this should be impossible for a UUID-based name."
        )
        addTeardownBlock {
            ud.removePersistentDomain(forName: name)
        }
        return SettingsStore(defaults: ud)
    }

    func testDefaultsToEmpty() throws {
        let store = try makeStore()
        XCTAssertEqual(store.extraBindings, .empty)
    }

    func testRoundTripsThroughUserDefaults() throws {
        let store = try makeStore()
        let set = ExtraBindingSet(bindings: [
            ExtraBinding(source: .mouseButton(6), action: .stop)
        ])
        store.extraBindings = set
        XCTAssertEqual(store.extraBindings, set)
    }
}
