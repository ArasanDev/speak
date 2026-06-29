// App/DictationController+LivePanel.swift
//
// PE-3 live-panel shaping: per-dictation destination/category overrides driven by the
// overlay's profile-selector card. Extracted into its own extension (matching the
// +CLI / +ErrorHandling split) to keep the DictationController class body within the
// type_body_length budget. All members are @MainActor (the extension inherits it from
// the type) and `internal` so the overlay wiring + sibling extensions can call them.
//
// Reversible by design: these mutate only the controller's observable shaping state and
// the OverlayViewModel; the saved default (ProfileStore) is never touched. The chosen
// override is applied to the engine ONCE, at stop, in +ErrorHandling.endDictation().
// See specs/live-panel-prompt-shaper.md.

import Foundation
import SpeakCore

extension DictationController {

    /// Switch the active destination for THIS dictation. Updates the observable state the
    /// panel highlights and flags the session as overridden so the stop-time apply runs.
    /// `profile` should be a destination built-in (Agent/Write/Note), resolved by the caller
    /// against `profileStore` so a user-edited prompt is honored.
    func selectDestination(_ profile: Profile) {
        activeDestination = profile
        didOverrideThisSession = true
        SpeakLog.engine.info("DictationController: live-panel destination → '\(profile.name, privacy: .public)'.")
    }

    /// Handle a destination selection from the live-panel card: update the highlighted choice
    /// and flag the per-dictation override. `Raw` means AI off for this dictation (routed to
    /// `applyRawOverride` at stop); any other maps to the user's (possibly AI-Studio-edited)
    /// profile. Does NOT change the saved default.
    func selectDestinationChoice(_ choice: OverlayDestinationChoice) {
        if choice.isRaw {
            overrodeToRaw = true
            didOverrideThisSession = true
            SpeakLog.engine.info("DictationController: live-panel destination → Raw (AI off this dictation).")
        } else {
            overrodeToRaw = false
            let profile = profileStore.profiles.first { $0.id == choice.profileID } ?? choice.fallbackProfile
            selectDestination(profile)
        }
        overlayController.setActiveDestinationChoice(choice)
    }

    /// Switch the Agent sub-category for THIS dictation (Agent only).
    func selectCategory(_ category: AgentCategory) {
        activeCategory = category
        didOverrideThisSession = true
        SpeakLog.engine.info("DictationController: live-panel category → '\(category.rawValue, privacy: .public)'.")
    }

    /// Resolve the destination for the current/next dictation from the frontmost app and
    /// seed the per-dictation shaping state. Called at `beginDictation`. Resolution mirrors
    /// `SpeakEngine.newSession` (same `ProfileResolver` over the same profile set) so the
    /// panel shows exactly what the engine would apply. Pure read — no side effects beyond
    /// the observable state.
    func resolveActiveDestination(frontmostBundleID: String?) {
        let resolved = ProfileResolver.resolve(
            frontmostBundleID: frontmostBundleID,
            profiles: profileStore.profiles,
            default: DefaultProfiles.defaultProfile
        )
        activeDestination = resolved
        activeCategory = .task
        didOverrideThisSession = false
        overrodeToRaw = false
    }
}
