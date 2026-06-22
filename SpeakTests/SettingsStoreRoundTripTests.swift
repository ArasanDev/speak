// SpeakTests/SettingsStoreRoundTripTests.swift
//
// 1C coverage-gap round-trip tests for `triggerMode`, `cleanupStyle`, and
// `cleanupEngine.mlx(model:)` — identified in Phase 1C as missing from the
// main `SettingsStoreTests` battery.
//
// PURPOSE:
//   A key-name change in `SettingsStore.Keys` (e.g. renaming `triggerMode` →
//   `trigger`) would silently break persistence without these tests. Each test
//   writes via one store instance, reads via a SECOND instance on the same
//   UserDefaults suite (simulating relaunch), and asserts equality.
//
// ISOLATION CONTRACT:
//   Every test creates its own named UserDefaults suite and removes it on teardown.
//   `.standard` is NEVER touched. Tests can run in any order without interference.

import XCTest
@testable import SpeakCore

@available(macOS 26.0, *)
final class SettingsStoreRoundTripTests: XCTestCase {

    // MARK: - Helpers

    private func makeIsolatedDefaults() throws -> UserDefaults {
        let name = "SettingsStoreRoundTripTests.\(UUID().uuidString)"
        let ud = try XCTUnwrap(
            UserDefaults(suiteName: name),
            "UserDefaults(suiteName:) returned nil — UUID-based name must always succeed."
        )
        addTeardownBlock {
            ud.removePersistentDomain(forName: name)
        }
        return ud
    }

    private func freshStore(on defaults: UserDefaults) -> SettingsStore {
        SettingsStore(defaults: defaults)
    }

    // MARK: - triggerMode (Phase B — 1C coverage gap)
    //
    // This round-trip battery catches a key-name change: a rename of
    // `Keys.triggerMode` would silently break persistence without these tests.

    func testTriggerModeDefaultIsDoubleTap() throws {
        let store = freshStore(on: try makeIsolatedDefaults())
        XCTAssertEqual(store.triggerMode, .doubleTap,
            "triggerMode default must be .doubleTap.")
    }

    func testTriggerModeDoubleTapRoundTrips() throws {
        let defaults = try makeIsolatedDefaults()
        let store = freshStore(on: defaults)
        store.triggerMode = .hold
        store.triggerMode = .doubleTap   // overwrite back

        let reloaded = freshStore(on: defaults)
        XCTAssertEqual(reloaded.triggerMode, .doubleTap,
            ".doubleTap must round-trip after overwriting .hold.")
    }

    func testTriggerModeHoldRoundTrips() throws {
        let defaults = try makeIsolatedDefaults()
        let store = freshStore(on: defaults)
        store.triggerMode = .hold

        let reloaded = freshStore(on: defaults)
        XCTAssertEqual(reloaded.triggerMode, .hold,
            ".hold must survive a SettingsStore reload on the same defaults.")
    }

    // MARK: - cleanupStyle (Phase B — 1C coverage gap)

    func testCleanupStyleDefaultIsDefault() throws {
        let store = freshStore(on: try makeIsolatedDefaults())
        XCTAssertEqual(store.cleanupStyle, .default,
            "cleanupStyle default must be .default.")
    }

    func testCleanupStyleProfessionalRoundTrips() throws {
        let defaults = try makeIsolatedDefaults()
        let store = freshStore(on: defaults)
        store.cleanupStyle = .professional

        let reloaded = freshStore(on: defaults)
        XCTAssertEqual(reloaded.cleanupStyle, .professional,
            ".professional must survive a SettingsStore reload.")
    }

    func testCleanupStyleCasualRoundTrips() throws {
        let defaults = try makeIsolatedDefaults()
        let store = freshStore(on: defaults)
        store.cleanupStyle = .casual

        let reloaded = freshStore(on: defaults)
        XCTAssertEqual(reloaded.cleanupStyle, .casual,
            ".casual must survive a SettingsStore reload.")
    }

    func testCleanupStyleCodeRoundTrips() throws {
        let defaults = try makeIsolatedDefaults()
        let store = freshStore(on: defaults)
        store.cleanupStyle = .code

        let reloaded = freshStore(on: defaults)
        XCTAssertEqual(reloaded.cleanupStyle, .code,
            ".code must survive a SettingsStore reload.")
    }

    func testCleanupStyleEmailRoundTrips() throws {
        let defaults = try makeIsolatedDefaults()
        let store = freshStore(on: defaults)
        store.cleanupStyle = .email

        let reloaded = freshStore(on: defaults)
        XCTAssertEqual(reloaded.cleanupStyle, .email,
            ".email must survive a SettingsStore reload.")
    }

    // MARK: - cleanupEngine .mlx (Wave 2.1 — 1C coverage gap)
    //
    // `.mlx(model:)` is a Codable enum-with-associated-value. This test catches a
    // Codable round-trip failure (e.g. a label rename, missing CodingKey) that would
    // silently drop the model string and reset the picker on relaunch.

    func testCleanupEngineMlxRoundTripsWithAssociatedValue() throws {
        let defaults = try makeIsolatedDefaults()
        let store = freshStore(on: defaults)
        store.cleanupEngine = .mlx(model: "mlx-community/Qwen2.5-3B-Instruct-4bit")

        let reloaded = freshStore(on: defaults)
        XCTAssertEqual(
            reloaded.cleanupEngine,
            .mlx(model: "mlx-community/Qwen2.5-3B-Instruct-4bit"),
            ".mlx(model:) including the associated model string must round-trip through " +
            "JSON encoding. A failure here means the Codable label or CodingKey changed."
        )
    }

    func testCleanupEngineMlxEmptyModelRoundTrips() throws {
        let defaults = try makeIsolatedDefaults()
        let store = freshStore(on: defaults)
        store.cleanupEngine = .mlx(model: "")

        let reloaded = freshStore(on: defaults)
        XCTAssertEqual(reloaded.cleanupEngine, .mlx(model: ""),
            ".mlx(model: \"\") must round-trip (empty model is a valid placeholder state).")
    }

    func testCleanupEngineMlxOverwrittenByFoundationModels() throws {
        let defaults = try makeIsolatedDefaults()
        let store = freshStore(on: defaults)
        store.cleanupEngine = .mlx(model: "mlx-community/phi-4")
        store.cleanupEngine = .foundationModels

        let reloaded = freshStore(on: defaults)
        XCTAssertEqual(reloaded.cleanupEngine, .foundationModels,
            "Overwriting .mlx with .foundationModels must persist correctly.")
    }
}
