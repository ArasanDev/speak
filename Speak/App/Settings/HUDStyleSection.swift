// App/Settings/HUDStyleSection.swift
//
// The "Recording HUD" section of the General settings tab (H-UI).
// Split out of SettingsView.swift to keep that file under SwiftLint's
// file_length cap — same pattern as ExtraBindingsSection.

import SpeakCore
import SwiftUI

/// Picker between the classic 15-bar HUD and the opt-in Aurora orb HUD.
/// Writes through to `SettingsStore.hudStyle`; the live overlay switches
/// styles reactively via `OverlayRootView`'s observation of the store.
struct HUDStyleSection: View {
    let store: SettingsStore

    var body: some View {
        Section {
            Picker("HUD Style", selection: Binding(
                get: { store.hudStyle },
                set: { store.hudStyle = $0 }
            )) {
                Text("Classic (default)").tag(HUDStyle.classic)
                Text("Aurora").tag(HUDStyle.aurora)
            }
            .pickerStyle(.menu)
            Text("Aurora is an ambient, orb-based HUD with live materializing transcript words.")
                .font(.caption)
                .foregroundStyle(Color.speakMica)
        } header: {
            Text("Recording HUD")
        }
    }
}
