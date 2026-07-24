// App/Settings/PetSection.swift
//
// FE-1 (specs/frontend-identity.md §5): the "Voice Desktop Pet" section of the General
// settings tab. Split out of SettingsView.swift to keep that file under
// SwiftLint's file_length cap — same pattern as `HUDStyleSection`.

import SpeakCore
import SwiftUI

/// Master opt-in toggle for Voice Desktop Pet, the floating pet panel. Default off
/// (`SettingsStore.petEnabled` defaults to `false`) — this is a v-next
/// opt-in extension (spec §5), not a v0 behavior change.
struct PetSection: View {
    let store: SettingsStore

    var body: some View {
        Section {
            Toggle("Show Voice Robotic Pet on screen", isOn: Binding(
                get: { store.petEnabled },
                set: { store.petEnabled = $0 }
            ))
            Text("Voice Robotic Pet is a floating companion panel that displays live audio signals and agent activity at a glance. Click it to start or stop dictation — the same as the hotkey.")
                .font(.caption)
                .foregroundStyle(.secondary)
        } header: {
            Text("Voice Robotic Pet")
        }}
}
