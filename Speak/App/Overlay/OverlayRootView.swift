// App/Overlay/OverlayRootView.swift
//
// The single content root hosted by `TranscriptOverlayPanel`.
//
// v2 (2026-09-17): the classic/Aurora HUD styles UNIFIED on the minimal
// floating pill (`TranscriptOverlayView` → `HUDPill`). The Aurora
// differentiator was the animated border — that is now an orthogonal opt-in
// (`SettingsStore.borderAnimationStyle`), so a per-style layout fork no
// longer earns its keep. `hudStyle` remains a persisted setting (its tests
// still pin the round-trip) but no longer forks the view tree.
//
// [decision: one good design over two divergent ones — owner direction.]

import SpeakCore
import SwiftUI

struct OverlayRootView: View {
    let model: OverlayViewModel
    let settingsStore: SettingsStore

    var body: some View {
        TranscriptOverlayView(model: model, settingsStore: settingsStore)
    }
}
