// App/Dashboard/Panes/DictionaryPaneView.swift
//
// The Dictionary pane — manage the custom vocabulary fed to the STT recognizer as
// contextual hints. Binds to `SettingsStore.customVocabulary` (the H4 seam, already
// wired into AppleSpeechTranscriber.AnalysisContext.contextualStrings).
//
// SCAFFOLD: owned by Wave B.3 (builder-app / builder-audio-stt). Replace the placeholder
// body with the add/edit/delete term list; keep the PaneHeader.

import SwiftUI
import SpeakCore

// MARK: - DictionaryPaneView

struct DictionaryPaneView: View {
    let context: DashboardContext

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PaneHeader(
                title: "Dictionary",
                subtitle: "Teach speak names and terms it should always spell correctly."
            )
            PanePlaceholder(
                systemImage: "character.book.closed",
                message: "Custom vocabulary manager — coming in this build."
            )
        }
    }
}
