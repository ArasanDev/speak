// App/Settings/BorderStyleSection.swift
//
// The "Animated Border" section of the General settings tab.
// Split out of SettingsView.swift to maintain modularity and keep file length low.

import SpeakCore
import SwiftUI

/// Picker for overlay panel border animation style (.none, .fullGlow, .edgeFlow)
/// and configurable controls for speed and light count when EdgeFlow is active.
struct BorderStyleSection: View {
    let store: SettingsStore

    var body: some View {
        Section {
            Picker("Border Animation", selection: Binding(
                get: { store.borderAnimationStyle },
                set: { store.borderAnimationStyle = $0 }
            )) {
                Text("None (default)").tag(BorderAnimationStyle.none)
                Text("Full Glow").tag(BorderAnimationStyle.fullGlow)
                Text("Edge Flow").tag(BorderAnimationStyle.edgeFlow)
            }
            .pickerStyle(.menu)

            if store.borderAnimationStyle == .edgeFlow {
                Picker("Flow Speed", selection: Binding(
                    get: { store.borderFlowSpeed },
                    set: { store.borderFlowSpeed = $0 }
                )) {
                    Text("Slow (6s)").tag(BorderFlowSpeed.slow)
                    Text("Medium (3s)").tag(BorderFlowSpeed.medium)
                    Text("Fast (1.5s)").tag(BorderFlowSpeed.fast)
                }
                .pickerStyle(.menu)

                Stepper(
                    "Flowing lights: \(store.borderFlowCount)",
                    value: Binding(
                        get: { store.borderFlowCount },
                        set: { store.borderFlowCount = $0 }
                    ),
                    in: 1...3
                )
            }

            Text(captionText)
                .font(.caption)
                .foregroundStyle(Color.speakMica)
        } header: {
            Text("Animated Border")
        }
    }

    private var captionText: String {
        switch store.borderAnimationStyle {
        case .none:
            return "No border animation — plain panel edges."
        case .fullGlow:
            return "Full-panel rotating conic gradient glow around HUD edges."
        case .edgeFlow:
            return "Traveling neon color lights that move continuously around the border perimeter."
        }
    }
}
