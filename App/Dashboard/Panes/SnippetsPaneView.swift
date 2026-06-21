// App/Dashboard/Panes/SnippetsPaneView.swift
//
// The Snippets pane — manage trigger→expansion text snippets applied to a transcript
// BEFORE the LLM cleanup pass (acceleration-plan.md Wave B). Binds to the new
// `SnippetStore`.
//
// SCAFFOLD: owned by Wave B.2 (builder-cleanup / builder-engine). Replace the placeholder
// body with the snippet list (add/edit/delete trigger + expansion); keep the PaneHeader.

import SwiftUI
import SpeakCore

// MARK: - SnippetsPaneView

struct SnippetsPaneView: View {
    let context: DashboardContext

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PaneHeader(
                title: "Snippets",
                subtitle: "Expand short triggers into longer text — applied before AI cleanup."
            )
            PanePlaceholder(
                systemImage: "text.append",
                message: "Snippet manager — coming in this build."
            )
        }
    }
}
