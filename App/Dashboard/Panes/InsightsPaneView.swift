// App/Dashboard/Panes/InsightsPaneView.swift
//
// The Insights pane — usage stats computed from the dictation history: total words,
// average WPM, daily streak, and a simple activity chart (acceleration-plan.md Wave D).
//
// SCAFFOLD: owned by Wave A.2 (builder-app). Replace the placeholder body with the
// computed stats + chart; keep the PaneHeader. Stats are derived from `context.historyStore`.

import SwiftUI
import SpeakCore

// MARK: - InsightsPaneView

struct InsightsPaneView: View {
    let context: DashboardContext

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PaneHeader(
                title: "Insights",
                subtitle: "Your dictation at a glance — words, speed, and streak."
            )
            PanePlaceholder(
                systemImage: "chart.bar",
                message: "Usage insights — coming in this build."
            )
        }
    }
}
