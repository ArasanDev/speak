// SpeakTests/PinnedContextStoreTests.swift
//
// PE-3.2 — PinnedContextStore: per-app pinned destination+category persistence.
// Each test uses a private UserDefaults suite (UUID name) to avoid .standard pollution.

@testable import SpeakCore
import XCTest

final class PinnedContextStoreTests: XCTestCase {

    private func makeStore() throws -> (PinnedContextStore, UserDefaults) {
        let name = "test.pinnedcontextstore.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name), "suite returned nil")
        defaults.removePersistentDomain(forName: name)
        return (PinnedContextStore(userDefaults: defaults), defaults)
    }

    // MARK: - Fresh store

    func testFreshStoreHasNoPins() throws {
        let (store, _) = try makeStore()
        XCTAssertNil(store.pinned(for: "com.example.app"))
        XCTAssertTrue(store.allPinned.isEmpty)
    }

    // MARK: - Pin and retrieve

    func testPinAndRetrieveWriteDestination() throws {
        let (store, _) = try makeStore()
        let ctx = PinnedContextStore.PinnedContext(
            destinationID: DefaultProfiles.write.id,
            category: nil
        )
        store.pin(ctx, for: "com.example.mail")

        let retrieved = try XCTUnwrap(store.pinned(for: "com.example.mail"))
        XCTAssertEqual(retrieved.destinationID, DefaultProfiles.write.id)
        XCTAssertNil(retrieved.category)
    }

    func testPinAndRetrieveAgentWithCategory() throws {
        let (store, _) = try makeStore()
        let ctx = PinnedContextStore.PinnedContext(
            destinationID: DefaultProfiles.agent.id,
            category: .fix
        )
        store.pin(ctx, for: "com.anthropic.claudecode")

        let retrieved = try XCTUnwrap(store.pinned(for: "com.anthropic.claudecode"))
        XCTAssertEqual(retrieved.destinationID, DefaultProfiles.agent.id)
        XCTAssertEqual(retrieved.category, .fix)
    }

    // MARK: - Overwrite (same bundle ID)

    func testPinOverwritesExistingPin() throws {
        let (store, _) = try makeStore()
        store.pin(PinnedContextStore.PinnedContext(destinationID: DefaultProfiles.write.id, category: nil), for: "com.example.app")
        store.pin(PinnedContextStore.PinnedContext(destinationID: DefaultProfiles.note.id, category: nil), for: "com.example.app")

        let retrieved = try XCTUnwrap(store.pinned(for: "com.example.app"))
        XCTAssertEqual(retrieved.destinationID, DefaultProfiles.note.id,
                       "Second pin should replace the first for the same bundle ID.")
    }

    // MARK: - Unpin

    func testUnpinRemovesEntry() throws {
        let (store, _) = try makeStore()
        store.pin(PinnedContextStore.PinnedContext(destinationID: DefaultProfiles.write.id, category: nil), for: "com.example.app")
        store.unpin(for: "com.example.app")

        XCTAssertNil(store.pinned(for: "com.example.app"), "Unpin should remove the entry.")
        XCTAssertTrue(store.allPinned.isEmpty)
    }

    func testUnpinNonExistentIsNoOp() throws {
        let (store, _) = try makeStore()
        store.unpin(for: "com.example.nonexistent")   // must not throw or crash
        XCTAssertTrue(store.allPinned.isEmpty)
    }

    // MARK: - Persistence across store instances

    func testPersistsAcrossStoreInstances() throws {
        let name = "test.pinnedcontextstore.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defaults.removePersistentDomain(forName: name)

        let store1 = PinnedContextStore(userDefaults: defaults)
        store1.pin(
            PinnedContextStore.PinnedContext(destinationID: DefaultProfiles.agent.id, category: .task),
            for: "com.microsoft.VSCode"
        )

        // Simulate relaunch by creating a new store over the same UserDefaults suite.
        let store2 = PinnedContextStore(userDefaults: defaults)
        let retrieved = try XCTUnwrap(store2.pinned(for: "com.microsoft.VSCode"))
        XCTAssertEqual(retrieved.destinationID, DefaultProfiles.agent.id)
        XCTAssertEqual(retrieved.category, .task)
    }

    // MARK: - allPinned

    func testAllPinnedReturnsAllEntries() throws {
        let (store, _) = try makeStore()
        store.pin(PinnedContextStore.PinnedContext(destinationID: DefaultProfiles.write.id, category: nil), for: "com.apple.mail")
        store.pin(PinnedContextStore.PinnedContext(destinationID: DefaultProfiles.agent.id, category: .commit), for: "com.microsoft.VSCode")

        let all = store.allPinned
        XCTAssertEqual(all.count, 2)
        XCTAssertEqual(all["com.apple.mail"]?.destinationID, DefaultProfiles.write.id)
        XCTAssertEqual(all["com.microsoft.VSCode"]?.category, .commit)
    }
}
