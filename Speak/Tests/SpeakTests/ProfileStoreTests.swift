// SpeakTests/ProfileStoreTests.swift
//
// PE-2a — ProfileStore: the persistence + customization seam. Verifies the merge
// model (built-ins always present, overrides layered on), round-trip across a fresh
// store (= relaunch), reset-to-default, and the built-in-vs-custom delete rule.
//
// Each test uses a private UserDefaults suite (UUID name) so there is no .standard
// pollution and tests are independent — the same idiom as SettingsStoreTests.

@testable import SpeakCore
import XCTest

final class ProfileStoreTests: XCTestCase {

    /// A ProfileStore over a fresh, isolated UserDefaults suite.
    private func makeStore() throws -> (ProfileStore, UserDefaults) {
        let name = "test.profilestore.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name), "suite \(name) returned nil")
        defaults.removePersistentDomain(forName: name)
        return (ProfileStore(defaults: defaults), defaults)
    }

    // MARK: - Merge model

    func testFreshStoreExposesAllBuiltIns() throws {
        let (store, _) = try makeStore()
        XCTAssertEqual(store.profiles.map(\.id), DefaultProfiles.all.map(\.id),
                       "A fresh store is exactly the shipped built-ins, in order.")
    }

    func testFreshStoreDefaultIsWrite() throws {
        let (store, _) = try makeStore()
        XCTAssertEqual(store.defaultProfile.id, DefaultProfiles.defaultProfile.id,
                       "The shipped default is Write.")
    }

    // MARK: - Editing a built-in

    func testEditBuiltInOverridesItButKeepsPositionAndCount() throws {
        let (store, _) = try makeStore()
        var agent = try XCTUnwrap(store.profiles.first { $0.name == "Agent" })
        agent.systemPrompt = "EDITED PROMPT"
        store.save(agent)

        XCTAssertEqual(store.profiles.count, DefaultProfiles.all.count,
                       "Editing a built-in must not add a profile.")
        XCTAssertEqual(store.profile(id: agent.id)?.systemPrompt, "EDITED PROMPT")
        XCTAssertEqual(store.profiles.map(\.id), DefaultProfiles.all.map(\.id),
                       "Order is preserved after editing a built-in.")
        XCTAssertTrue(store.isCustomized(id: agent.id), "An edited built-in reports customized.")
    }

    func testEditPersistsAcrossFreshStore() throws {
        let name = "test.profilestore.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defaults.removePersistentDomain(forName: name)

        let store1 = ProfileStore(defaults: defaults)
        var write = try XCTUnwrap(store1.profiles.first { $0.name == "Write" })
        write.systemPrompt = "PERSISTED EDIT"
        store1.save(write)

        // A second store over the same suite = an app relaunch.
        let store2 = ProfileStore(defaults: defaults)
        XCTAssertEqual(store2.profile(id: write.id)?.systemPrompt, "PERSISTED EDIT",
                       "Edits survive a relaunch.")
    }

    // MARK: - Reset

    func testResetToDefaultRevertsBuiltIn() throws {
        let (store, _) = try makeStore()
        let original = try XCTUnwrap(store.profiles.first { $0.name == "Note" })
        var edited = original
        edited.systemPrompt = "EDITED"
        store.save(edited)
        XCTAssertTrue(store.isCustomized(id: original.id))

        store.resetToDefault(id: original.id)
        XCTAssertFalse(store.isCustomized(id: original.id), "Reset clears the override.")
        XCTAssertEqual(store.profile(id: original.id)?.systemPrompt, original.systemPrompt,
                       "Reset restores the shipped prompt.")
    }

    // MARK: - User-created profiles

    func testCreateAndDeleteUserProfile() throws {
        let (store, _) = try makeStore()
        let custom = Profile(name: "MyProfile", icon: "star", isBuiltIn: false,
                             systemPrompt: "do a thing")
        store.save(custom)
        XCTAssertEqual(store.profiles.count, DefaultProfiles.all.count + 1,
                       "A user profile is appended after the built-ins.")
        XCTAssertEqual(store.profiles.last?.id, custom.id, "User profiles come after built-ins.")

        store.delete(id: custom.id)
        XCTAssertNil(store.profile(id: custom.id), "A user profile is deletable.")
        XCTAssertEqual(store.profiles.count, DefaultProfiles.all.count)
    }

    func testDeleteBuiltInIsRefused() throws {
        let (store, _) = try makeStore()
        let write = try XCTUnwrap(store.profiles.first { $0.name == "Write" })
        store.delete(id: write.id)
        XCTAssertNotNil(store.profile(id: write.id), "Built-ins are never deletable.")
        XCTAssertEqual(store.profiles.count, DefaultProfiles.all.count)
    }

    // MARK: - Default selection

    func testDefaultProfileIDPersistsAndResolves() throws {
        let (store, _) = try makeStore()
        let agent = try XCTUnwrap(store.profiles.first { $0.name == "Agent" })
        store.defaultProfileID = agent.id
        XCTAssertEqual(store.defaultProfile.id, agent.id, "Default selection resolves to the chosen profile.")
    }

    func testDeletingTheDefaultProfileFallsBackToWrite() throws {
        let (store, _) = try makeStore()
        let custom = Profile(name: "Temp", icon: "star", systemPrompt: "x")
        store.save(custom)
        store.defaultProfileID = custom.id
        XCTAssertEqual(store.defaultProfile.id, custom.id)

        store.delete(id: custom.id)
        XCTAssertEqual(store.defaultProfileID, DefaultProfiles.defaultProfile.id,
                       "Deleting the default profile reverts the selection to Write.")
    }

    func testStaleDefaultIDFallsBackToShippedDefault() throws {
        let (store, _) = try makeStore()
        store.defaultProfileID = UUID()   // never-existed id
        XCTAssertEqual(store.defaultProfile.id, DefaultProfiles.defaultProfile.id,
                       "A stale default id resolves to the shipped default, never nil.")
    }
}
