// App/Dashboard/Panes/StylePaneView.swift
//
// The Style pane — choose the neat-writing voice (Default/Professional/Casual/Code/Email)
// and the cleanup level (Basic/Balanced/Thorough). Binds to the new `CleanupMode` +
// cleanup-level settings on `SettingsStore`; the per-mode prompt lives in
// FoundationModelsCleaner (acceleration-plan.md Wave B — the neat-writing moat).
//
// SCAFFOLD: owned by Wave B.1 (builder-cleanup). Replace the placeholder body with the
// mode picker + level picker + live preview; keep the PaneHeader.

import SwiftUI
import SpeakCore

// MARK: - StylePaneView

struct StylePaneView: View {
    let context: DashboardContext

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PaneHeader(
                title: "Style",
                subtitle: "Choose how speak rewrites your words — the voice and the polish level."
            )
            PanePlaceholder(
                systemImage: "wand.and.stars",
                message: "Style modes + cleanup level — coming in this build."
            )
        }
    }
}
