// App/Overlay/OverlayRootView.swift
//
// H-UI: the single content root hosted by `TranscriptOverlayPanel`. Switches
// between the classic bar-waveform HUD and the Aurora ambient-orb HUD based
// on `SettingsStore.hudStyle`.
//
// Reading `settingsStore.hudStyle` inside `body` subscribes this view to
// `SettingsStore`'s `@Observable` change tracking, so toggling the setting in
// `SettingsView` swaps the HUD content live — no relaunch, no panel
// recreation (the panel + `NSHostingView` are created once and retained per
// `TranscriptOverlayPanel`'s existing contract).
//
// [decision H-UI: default `.classic` in SettingsStore means this switch is a
//  no-op for every existing user until they opt in — zero regression risk.]

import SpeakCore
import SwiftUI

struct OverlayRootView: View {
    let model: OverlayViewModel
    let settingsStore: SettingsStore

    var body: some View {
        switch settingsStore.hudStyle {
        case .classic:
            TranscriptOverlayView(model: model)

        case .aurora:
            AuroraOverlayView(model: model)
        }
    }
}
