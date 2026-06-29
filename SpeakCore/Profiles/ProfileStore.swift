// SpeakCore/Profiles/ProfileStore.swift
//
// Persistence + customization layer for the Profile Engine (specs/profile-engine.md
// §4.1). PE-0 shipped the data model (`Profile`) and PE-1 wired resolution against the
// hardcoded `DefaultProfiles.all`. This store is the missing seam: it lets AI Studio
// edit built-ins and create user profiles, persists those edits, and feeds the edited
// set back into resolution — so a prompt the user changes in AI Studio actually changes
// the next dictation.
//
// DESIGN (mirrors SettingsStore exactly — see its header):
//   - `@unchecked Sendable` (NOT `@MainActor`): the merged `profiles` and `defaultProfile`
//     are read by `SpeakEngine` (an actor) at `newSession()` time, synchronously, with no
//     cross-actor await. UserDefaults is documented thread-safe by Apple.
//   - `@Observable`: AI Studio binds directly; the computed `profiles`/`defaultProfileID`
//     are manually instrumented with `access`/`withMutation` so SwiftUI tracks them.
//   - Testable via injection: `init(defaults:)` accepts any `UserDefaults`.
//
// MERGE MODEL (the heart):
//   We persist only the *overrides* — edited built-ins and user-created profiles — as a
//   JSON `[Profile]`. The public `profiles` list is computed by layering those overrides
//   on top of `DefaultProfiles.all`:
//     • Each built-in appears once, in DefaultProfiles order, replaced by its persisted
//       edit if one exists.
//     • User profiles (ids not in the built-in set) are appended.
//   Consequences (deliberate):
//     • "Reset to default" = drop a built-in's override → it reverts to the shipped value.
//     • A built-in added in a FUTURE release appears automatically (it's in DefaultProfiles
//       and has no override). [tradeoff, logged] A shipped *prompt improvement* to an
//       already-edited built-in does NOT reach a user who customized it — their override
//       wins. Acceptable: their edits are sacred; Reset recovers the new default.

import Foundation
import Observation
import os

// MARK: - ProfileStore

/// The persistent set of profiles (edited built-ins + user-created) plus the global
/// default selection. Built-ins are always present and resettable; only user-created
/// profiles are deletable.
@Observable
public final class ProfileStore: @unchecked Sendable {

    @ObservationIgnored private let defaults: UserDefaults

    private enum Keys {
        /// JSON `[Profile]` of overrides: edited built-ins + user-created profiles.
        static let overrides = "speak.profiles.overrides"
        /// The chosen global default profile id (UUID string). Ships as `Clean`.
        static let defaultProfileID = "speak.profiles.defaultID"
    }

    /// - Parameter defaults: inject a private suite in tests; production uses `.standard`.
    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    // MARK: - The merged profile set

    /// All profiles in display order: built-ins (edited where overridden) then user
    /// profiles. This is what AI Studio lists and what resolution runs against.
    public var profiles: [Profile] {
        access(keyPath: \.profiles)
        let overrides = decodeOverrides()
        let overrideByID = Dictionary(overrides.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        // Built-ins, each replaced by its persisted edit if present.
        let builtIns = DefaultProfiles.all.map { overrideByID[$0.id] ?? $0 }
        // User-created profiles: any override whose id is not a built-in.
        let builtInIDs = Set(DefaultProfiles.all.map(\.id))
        let userProfiles = overrides.filter { !builtInIDs.contains($0.id) }
        return builtIns + userProfiles
    }

    /// The global default profile (ships as `Clean`). Falls back to the shipped default
    /// if the persisted id is missing/stale — resolution is never left without a profile.
    public var defaultProfile: Profile {
        let id = defaultProfileID
        return profiles.first { $0.id == id } ?? DefaultProfiles.defaultProfile
    }

    /// The chosen global-default profile id. Defaults to the shipped `Clean` id.
    public var defaultProfileID: UUID {
        get {
            access(keyPath: \.defaultProfileID)
            guard let raw = defaults.string(forKey: Keys.defaultProfileID),
                  let id = UUID(uuidString: raw) else {
                return DefaultProfiles.defaultProfile.id
            }
            return id
        }
        set {
            withMutation(keyPath: \.defaultProfileID) {
                defaults.set(newValue.uuidString, forKey: Keys.defaultProfileID)
            }
        }
    }

    // MARK: - Lookups

    /// The profile with `id`, or `nil` if neither a built-in nor a user profile matches.
    public func profile(id: UUID) -> Profile? {
        profiles.first { $0.id == id }
    }

    /// Whether a built-in currently has user edits (drives the Reset button's enabled
    /// state). Always `false` for user-created profiles (they have nothing to reset to).
    public func isCustomized(id: UUID) -> Bool {
        guard DefaultProfiles.all.contains(where: { $0.id == id }) else { return false }
        return decodeOverrides().contains { $0.id == id }
    }

    // MARK: - Mutations

    /// Create or update a profile. For a built-in this records an override (its edited
    /// form); for a user profile it inserts/updates the persisted entry. Idempotent by id.
    public func save(_ profile: Profile) {
        var overrides = decodeOverrides()
        if let index = overrides.firstIndex(where: { $0.id == profile.id }) {
            overrides[index] = profile
        } else {
            overrides.append(profile)
        }
        persist(overrides)
    }

    /// Delete a profile. Only user-created profiles are deletable; built-ins are never
    /// removed (use `resetToDefault` to discard edits). Deleting the current default
    /// falls the default selection back to the shipped `Clean`.
    public func delete(id: UUID) {
        guard !DefaultProfiles.all.contains(where: { $0.id == id }) else {
            SpeakLog.storage.warning("ProfileStore: refusing to delete built-in profile \(id, privacy: .public).")
            return
        }
        var overrides = decodeOverrides()
        overrides.removeAll { $0.id == id }
        persist(overrides)
        if defaultProfileID == id {
            defaultProfileID = DefaultProfiles.defaultProfile.id
        }
    }

    /// Reset a built-in to its shipped value by dropping its override. No-op for user
    /// profiles (they have no shipped default).
    public func resetToDefault(id: UUID) {
        guard DefaultProfiles.all.contains(where: { $0.id == id }) else {
            SpeakLog.storage.warning("ProfileStore: resetToDefault called for non-built-in \(id, privacy: .public) — ignored.")
            return
        }
        var overrides = decodeOverrides()
        let before = overrides.count
        overrides.removeAll { $0.id == id }
        guard overrides.count != before else { return }   // nothing to reset
        persist(overrides)
    }

    // MARK: - Persistence helpers

    private func decodeOverrides() -> [Profile] {
        guard let data = defaults.data(forKey: Keys.overrides),
              let decoded = try? JSONDecoder().decode([Profile].self, from: data) else {
            return []
        }
        return decoded
    }

    private func persist(_ overrides: [Profile]) {
        withMutation(keyPath: \.profiles) {
            guard let data = try? JSONEncoder().encode(overrides) else {
                SpeakLog.storage.error("ProfileStore: failed to encode profile overrides — not persisted.")
                return
            }
            defaults.set(data, forKey: Keys.overrides)
        }
    }
}
