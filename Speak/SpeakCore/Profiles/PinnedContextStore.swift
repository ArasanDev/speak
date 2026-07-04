// SpeakCore/Profiles/PinnedContextStore.swift
//
// PE-3.2 — Pin-to-context: per-app sticky destination/category store.
//
// Persists a mapping of frontmost bundle ID → pinned (destination, category?) so the
// live panel can auto-select the right destination on future dictation sessions without
// the user re-picking it every time.
//
// DESIGN:
//   Mirrors ProfileStore's stateless-decode/encode-per-call shape — no cached state means
//   no lock is needed and `@unchecked Sendable` is honest: the only shared mutable resource
//   is UserDefaults, which is documented thread-safe by Apple.
//   Foundation-only (no AppKit / SwiftUI) — lives in SpeakCore, the portability seam.

import Foundation
import os

// MARK: - PinnedContextStore

/// Persists per-app "pinned" destination + category so the live panel auto-selects
/// them on future dictation sessions.
public final class PinnedContextStore: @unchecked Sendable {

    // MARK: - PinnedContext

    /// The pinned destination + optional Agent category for one app.
    public struct PinnedContext: Codable, Sendable {
        /// Stable id of the pinned destination profile.
        public let destinationID: UUID
        /// The pinned Agent sub-category. `nil` for non-Agent destinations.
        public let category: AgentCategory?

        public init(destinationID: UUID, category: AgentCategory?) {
            self.destinationID = destinationID
            self.category = category
        }
    }

    // MARK: - Persistence key

    @ObservationIgnored private let defaults: UserDefaults

    private enum Keys {
        // [decision PE-3.2] one JSON blob: [bundleID: PinnedContext]
        static let pinnedContexts = "speak.pinnedContexts"
    }

    // MARK: - Init

    /// - Parameter userDefaults: Inject a private suite in tests; production uses `.standard`.
    public init(userDefaults: UserDefaults = .standard) {
        self.defaults = userDefaults
    }

    // MARK: - Public API

    /// The pinned context for `bundleID`, or `nil` if none has been set.
    public func pinned(for bundleID: String) -> PinnedContext? {
        decode()[bundleID]
    }

    /// Pin `context` for `bundleID`, replacing any prior pin for the same bundle.
    public func pin(_ context: PinnedContext, for bundleID: String) {
        var map = decode()
        map[bundleID] = context
        persist(map)
    }

    /// Remove the pin for `bundleID`. No-op if no pin exists.
    public func unpin(for bundleID: String) {
        var map = decode()
        map.removeValue(forKey: bundleID)
        persist(map)
    }

    /// All pinned contexts — used by the Settings UI to display and manage pins.
    public var allPinned: [String: PinnedContext] {
        decode()
    }

    // MARK: - Persistence helpers

    private func decode() -> [String: PinnedContext] {
        guard let data = defaults.data(forKey: Keys.pinnedContexts),
              let decoded = try? JSONDecoder().decode([String: PinnedContext].self, from: data) else {
            return [:]
        }
        return decoded
    }

    private func persist(_ map: [String: PinnedContext]) {
        guard let data = try? JSONEncoder().encode(map) else {
            SpeakLog.storage.error("PinnedContextStore: failed to encode pinned contexts — not persisted.")
            return
        }
        defaults.set(data, forKey: Keys.pinnedContexts)
    }
}
