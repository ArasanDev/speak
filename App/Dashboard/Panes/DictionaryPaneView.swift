// App/Dashboard/Panes/DictionaryPaneView.swift
//
// The Dictionary pane — manage the custom vocabulary fed to the STT recognizer as
// contextual hints so speak spells your names/terms correctly. Binds to
// `SettingsStore.customVocabulary` (the H4 seam, already wired into
// AppleSpeechTranscriber.AnalysisContext.contextualStrings); edit rules live in the
// pure `CustomVocabulary` helper (unit-tested).
//
// Matches the verified Wispr Dictionary: add a term, see the list, delete a term.
// (Auto-learned ✨ words are a future enhancement once STT surfaces them.)

import SpeakCore
import SwiftUI

// MARK: - DictionaryPaneView

struct DictionaryPaneView: View {
    let context: DashboardContext

    @ObservedObject private var settings: SettingsStore
    @State private var newTerm: String = ""

    init(context: DashboardContext) {
        self.context = context
        self.settings = context.settingsStore
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PaneHeader(
                title: "Dictionary",
                subtitle: "Teach speak names and terms it should always spell correctly."
            )
            addBar
            content
        }
    }

    // MARK: - Add bar

    private var addBar: some View {
        HStack(spacing: SpeakSpacing.sm) {
            TextField("Add a word or name…", text: $newTerm)
                .textFieldStyle(.plain)
                .font(.speakMonoBody)
                .onSubmit(addTerm)
            Button("Add", action: addTerm)
                .disabled(newTerm.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(SpeakSpacing.md)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.speakSurface))
        .padding(.horizontal, SpeakSpacing.lg)
        .padding(.bottom, SpeakSpacing.md)
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        let terms = settings.customVocabulary
        if terms.isEmpty {
            PanePlaceholder(
                systemImage: "character.book.closed",
                message: "No custom words yet. Add names, jargon, or acronyms speak should get right."
            )
        } else {
            List {
                ForEach(terms, id: \.self) { term in
                    HStack {
                        Text(term)
                            .font(.speakMonoBody)
                        Spacer()
                        Button {
                            removeTerm(term)
                        } label: {
                            Image(systemName: "trash")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.borderless)
                        .help("Remove \(term)")
                    }
                    .padding(.vertical, SpeakSpacing.xs)
                }
            }
            .listStyle(.inset)
        }
    }

    // MARK: - Actions

    private func addTerm() {
        let updated = CustomVocabulary.adding(newTerm, to: settings.customVocabulary)
        settings.customVocabulary = updated
        newTerm = ""
    }

    private func removeTerm(_ term: String) {
        settings.customVocabulary = CustomVocabulary.removing(term, from: settings.customVocabulary)
    }
}

// MARK: - Preview

#if DEBUG
#Preview("Dictionary") {
    DictionaryPaneView(context: DashboardContext(
        settingsStore: SettingsStore(),
        historyStore: PreviewNullHistoryStore(),
        hotkeyCombo: ["Fn", "Fn"]
    ))
    .frame(width: 620, height: 520)
}
#endif
