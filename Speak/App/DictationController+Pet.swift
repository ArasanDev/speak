// App/DictationController+Pet.swift
//
// FE-1 (specs/frontend-identity.md §5): live-apply wiring for Pip, the
// floating pet panel. Split out of `DictationController.swift` to hold
// SwiftLint's type_body_length cap — same pattern as `+VoiceOut`/`+CLI`.
// `petWiring`'s three fields are grouped into one struct (`PetWiring`) so
// `DictationController` itself only grows by a single stored property.
//
// `petEnabled` defaults to `false` (opt-in until dogfooded, zero regression
// for existing users). This file:
//   - `configurePetPanel()`: called once from `init()` — constructs
//     `petPanelController` if already on at launch, then arms the observer.
//   - `startObservingPetEnabled()`: `withObservationTracking` loop (same
//     pattern as `startObservingAppearance`/`startObservingTriggerMode`) that
//     constructs/tears down `petPanelController` live, no relaunch required.

import Foundation
import Observation
import SpeakCore

/// The three pieces of Pip live-toggle state, grouped into one struct so
/// `DictationController`'s stored-property list grows by exactly one entry.
@MainActor
struct PetWiring {
    /// Nil when `petEnabled == false` (the default).
    var petPanelController: PetPanelController?
    var petEnabledObserverTask: Task<Void, Never>?
    var lastAppliedPetEnabled = false
}

extension DictationController {

    /// Called once from `init()`. Constructs the panel immediately if
    /// `petEnabled` was already true at launch, then arms the live-toggle
    /// observer for the rest of the app's lifetime.
    func configurePetPanel() {
        if settingsStore.petEnabled {
            petWiring.petPanelController = PetPanelController(
                dictationController: self,
                settingsStore: settingsStore,
                permissionManager: permissionManager,
                agentSpeechQueue: agentSpeechQueue
            )
        }
        petWiring.lastAppliedPetEnabled = settingsStore.petEnabled
        startObservingPetEnabled()
    }

    /// Re-arming observation loop: tracks `settingsStore.petEnabled` via
    /// `withObservationTracking` and constructs/tears down `petPanelController`
    /// live — no relaunch required (same pattern as `startObservingAppearance`).
    func startObservingPetEnabled() {
        petWiring.petEnabledObserverTask?.cancel()
        petWiring.petEnabledObserverTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self else { break }
                await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                    withObservationTracking {
                        _ = self.settingsStore.petEnabled
                    } onChange: {
                        continuation.resume()
                    }
                }
                guard !Task.isCancelled else { break }
                let newValue = self.settingsStore.petEnabled
                guard newValue != self.petWiring.lastAppliedPetEnabled else { continue }
                self.petWiring.lastAppliedPetEnabled = newValue
                if newValue {
                    self.petWiring.petPanelController = PetPanelController(
                        dictationController: self,
                        settingsStore: self.settingsStore,
                        permissionManager: self.permissionManager,
                        agentSpeechQueue: self.agentSpeechQueue
                    )
                } else {
                    self.petWiring.petPanelController?.tearDown()
                    self.petWiring.petPanelController = nil
                }
                SpeakLog.app.info(
                    "DictationController: petEnabled changed — \(newValue, privacy: .public)"
                )
            }
        }
    }
}
