// App/DictationController+LivePanel.swift
//
// PE-3 live-panel shaping: per-dictation destination/category overrides driven by the
// overlay's profile-selector card. Extracted into its own extension (matching the
// +CLI / +ErrorHandling split) to keep the DictationController class body within the
// type_body_length budget. All members are @MainActor (the extension inherits it from
// the type) and `internal` so the overlay wiring + sibling extensions can call them.
//
// PE-3.2 additions: pin-to-context — sticky destination/category per app.
//   - `activeBundleID` is set here in `resolveActiveDestination`.
//   - A per-app override counter in `selectDestinationChoice` triggers `showPinPrompt`
//     after 2 consecutive first-override-per-dictation events for the same app.
//   - `pinCurrentContext` / `unpinContext` / `dismissPinPrompt` manage the store + UI.
//   - `syncPinPromptToOverlay` keeps `overlayController.overlayModel` in sync.
//
// Reversible by design: these mutate only the controller's observable shaping state and
// the OverlayViewModel; the saved default (ProfileStore) is never touched. The chosen
// override is applied to the engine ONCE, at stop, in +ErrorHandling.endDictation().
// See specs/live-panel-prompt-shaper.md.

import Foundation
import SpeakCore

extension DictationController {

    // MARK: - Destination / category selection (chip taps)

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
    ///
    /// PE-3.2: Counts the first non-Raw manual override per dictation per app toward the pin
    /// threshold. Raw overrides are excluded from counting (no Raw pinning supported).
    func selectDestinationChoice(_ choice: OverlayDestinationChoice) {
        // [PE-3.2] Capture before existing logic flips didOverrideThisSession.
        let firstThisSession = !didOverrideThisSession

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

        // [PE-3.2] Count the first non-Raw override per dictation toward the pin threshold.
        // Raw overrides are intentionally excluded — pinning Raw is not supported.
        if firstThisSession && !choice.isRaw {
            let bundleID = activeBundleID
            guard !bundleID.isEmpty else { return }
            overrideCountPerApp[bundleID, default: 0] += 1
            if overrideCountPerApp[bundleID, default: 0] >= 2 {
                showPinPrompt = true
                syncPinPromptToOverlay()
            }
        }
    }

    /// Switch the Agent sub-category for THIS dictation (Agent only).
    func selectCategory(_ category: AgentCategory) {
        activeCategory = category
        didOverrideThisSession = true
        SpeakLog.engine.info("DictationController: live-panel category → '\(category.rawValue, privacy: .public)'.")
    }

    /// Handle a category tap from the live-panel card: apply it and update the highlight.
    /// Picking a category implies the Agent destination is active (the category page is only
    /// reachable via Agent), so `overrodeToRaw` is cleared. (PE-3c-2.)
    ///
    /// PE-3.2: Category taps are always preceded by an Agent tap (`selectDestinationChoice`),
    /// which already increments the counter — no double-counting here.
    func selectCategoryChoice(_ category: AgentCategory) {
        overrodeToRaw = false
        selectCategory(category)
        overlayController.setActiveCategory(category)
    }

    // MARK: - Destination resolution (called at beginDictation)

    /// Resolve the destination for the current/next dictation from the frontmost app and
    /// seed the per-dictation shaping state. Called at `beginDictation`. Resolution mirrors
    /// `SpeakEngine.newSession` (same `ProfileResolver` over the same profile set) so the
    /// panel shows exactly what the engine would apply.
    ///
    /// PE-3.2: Sets `activeBundleID`, resets `showPinPrompt`, then applies any pinned context
    /// for this app (overriding the resolver result). When a pin is applied, `didOverrideThisSession`
    /// is set true so the stop-time engine override runs and delivers the pinned destination.
    func resolveActiveDestination(frontmostBundleID: String?) {
        // [PE-3.2] Store for pin tracking and pin-apply this session.
        activeBundleID = frontmostBundleID ?? ""
        showPinPrompt = false
        overlayController.hidePinBanner()

        // [PE-3.2] If a pin exists for this app, apply it instead of the resolver default.
        // Guard: the pinned profile must still exist in the store (user may have deleted it).
        if !activeBundleID.isEmpty,
           let pinned = pinnedContextStore.pinned(for: activeBundleID),
           let profile = profileStore.profile(id: pinned.destinationID) {
            activeDestination = profile
            activeCategory = pinned.category ?? .task
            didOverrideThisSession = true  // so stop-time apply delivers the pinned destination
            overrodeToRaw = false
            let bundleForLog = activeBundleID
            SpeakLog.engine.info(
                "DictationController: pinned context applied — '\(profile.name, privacy: .public)' for '\(bundleForLog, privacy: .public)'."
            )
            return
        }

        // Default resolution — same ProfileResolver the engine uses.
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

    // MARK: - PE-3.2 pin actions

    /// Pin the current active destination (+ Agent category if Agent) for `activeBundleID`.
    /// Resets the override counter and hides the prompt.
    func pinCurrentContext() {
        guard !activeBundleID.isEmpty else { return }
        let ctx = PinnedContextStore.PinnedContext(
            destinationID: activeDestination.id,
            category: activeDestination.id == DefaultProfiles.agent.id ? activeCategory : nil
        )
        pinnedContextStore.pin(ctx, for: activeBundleID)
        overrideCountPerApp[activeBundleID] = 0
        showPinPrompt = false
        syncPinPromptToOverlay()
        let destName = activeDestination.name
        let bundleForLog = activeBundleID
        SpeakLog.engine.info(
            "DictationController: context pinned — '\(destName, privacy: .public)' for '\(bundleForLog, privacy: .public)'."
        )
    }

    /// Remove the pin for `bundleID`. Resets the override counter so a fresh pin flow
    /// can begin. Callable from the Settings UI.
    func unpinContext(for bundleID: String) {
        pinnedContextStore.unpin(for: bundleID)
        overrideCountPerApp[bundleID] = 0
        SpeakLog.engine.info(
            "DictationController: context unpinned for '\(bundleID, privacy: .public)'."
        )
    }

    /// Dismiss the pin prompt without pinning. Resets the counter so the prompt won't
    /// immediately re-fire next session.
    func dismissPinPrompt() {
        overrideCountPerApp[activeBundleID] = 0
        showPinPrompt = false
        syncPinPromptToOverlay()
        let bundleForLog = activeBundleID
        SpeakLog.engine.info(
            "DictationController: pin prompt dismissed for '\(bundleForLog, privacy: .public)'."
        )
    }

    // MARK: - PE-3.2 overlay sync

    /// Push the current `showPinPrompt` state to the overlay model.
    /// Called whenever `showPinPrompt` changes so `overlayController.overlayModel` stays
    /// in sync. The view binds `overlayModel` (not `DictationController`) so mutations
    /// must route through here. [decision PE-3.2]
    func syncPinPromptToOverlay() {
        if showPinPrompt {
            let label: String
            if activeDestination.id == DefaultProfiles.agent.id {
                label = "Always Agent · \(activeCategory.displayName) here?"
            } else {
                label = "Always \(activeDestination.name) here?"
            }
            overlayController.showPinBanner(
                label: label,
                onPin: { [weak self] in self?.pinCurrentContext() },
                onDismissPin: { [weak self] in self?.dismissPinPrompt() }
            )
        } else {
            overlayController.hidePinBanner()
        }
    }
}
