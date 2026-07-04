// SpeakCore/Profiles/ProfileResolver.swift
//
// Profile resolution — which profile applies to a dictation (specs/profile-taxonomy.md §3).
// PURE function over an injected frontmost-app bundle ID, so it is fully unit-testable
// without AppKit. The impure read (`NSWorkspace.frontmostApplication`) happens at the
// app-layer call site (DictationController, @MainActor) and the bundle ID is passed in.
//
// "Frontmost app = the target app" is correct here BECAUSE the overlay is a
// non-activating panel — triggering dictation never changes which app is frontmost,
// so the app that had focus when the hotkey fired is the one the text will land in.
//
// PT-1 (Profile Taxonomy) resolution: maps app bundle IDs to DESTINATIONS (Agent/Write/Note).
// Each built-in profile's `targetApps` is pre-populated per the spec's resolution table.
// The AUTO-SELECT-BY-APP tier (priority 2) works the same as before; the overlay override
// (priority 1) and user-chosen global default (priority 3) arrive with the overlay control
// surface + AI Studio.

import Foundation

// MARK: - ProfileResolver

public enum ProfileResolver {

    /// Resolve the profile for a dictation given the frontmost app.
    ///
    /// - Parameters:
    ///   - frontmostBundleID: the frontmost app's bundle identifier at dictation
    ///     start, or `nil` (CLI path, or unavailable).
    ///   - profiles: the candidate profiles (built-ins for now; user profiles later).
    ///   - default: the global default profile, returned when no profile's
    ///     `targetApps` matches the frontmost app (ships as `Clean`).
    /// - Returns: the first profile whose `targetApps` contains `frontmostBundleID`,
    ///   else `default`. Never throws — resolution always yields a usable profile
    ///   (the base-core "never a dead end" guarantee).
    public static func resolve(
        frontmostBundleID: String?,
        profiles: [Profile],
        default defaultProfile: Profile
    ) -> Profile {
        guard let bundleID = frontmostBundleID, !bundleID.isEmpty else {
            return defaultProfile
        }
        return profiles.first { $0.targetApps.contains(bundleID) } ?? defaultProfile
    }
}
