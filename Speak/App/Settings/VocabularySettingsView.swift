// App/Settings/VocabularySettingsView.swift
//
// "Vocabulary & Jargon" — the fourth Settings category. Two cards:
//   - Custom Vocabulary: terms fed to SpeechAnalyzer as contextual hints
//     (same `SettingsStore.customVocabulary` seam as the Dictionary pane).
//   - Snippets: trigger → expansion pairs applied before AI cleanup
//     (same `SnippetStore` seam as the Snippets pane).
//
// The dashboard Dictionary/Snippets panes remain the roomy editors; this
// category keeps the same data editable from Settings without duplicating
// storage logic.

import SpeakCore
import SwiftUI

// MARK: - VocabularySettingsView

@MainActor
struct VocabularySettingsView: View {
    let context: DashboardContext

    var body: some View {
        VStack(alignment: .leading, spacing: SpeakSpacing.lg) {
            CustomVocabularyCard(store: context.settingsStore)
            SnippetsCard(store: context.snippetStore)
        }
    }
}

// MARK: - CustomVocabularyCard

private struct CustomVocabularyCard: View {
    let store: SettingsStore
    @State private var newTerm = ""

    var body: some View {
        SettingsSectionCard(title: "Custom Vocabulary", systemImage: "character.book.closed") {
            VStack(alignment: .leading, spacing: SpeakSpacing.sm) {
                HStack(spacing: SpeakSpacing.sm) {
                    TextField("Add a word or name…", text: $newTerm)
                        .textFieldStyle(.plain)
                        .font(.speakMonoBody)
                        .onSubmit(addTerm)
                    Button("Add", action: addTerm)
                        .disabled(newTerm.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                Text("Fed to the speech recognizer as contextual hints so names and jargon spell correctly.")
                    .font(.speakBody(.caption))
                    .foregroundStyle(.secondary)

                let terms = store.customVocabulary
                if !terms.isEmpty {
                    Divider()
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
                    }
                }
            }
            .padding(.horizontal, SpeakSpacing.md)
            .padding(.vertical, SpeakSpacing.sm + 4)
        }
    }

    private func addTerm() {
        store.customVocabulary = CustomVocabulary.adding(newTerm, to: store.customVocabulary)
        newTerm = ""
    }

    private func removeTerm(_ term: String) {
        store.customVocabulary = CustomVocabulary.removing(term, from: store.customVocabulary)
    }
}

// MARK: - SnippetsCard

private struct SnippetsCard: View {
    let store: SnippetStore
    @State private var trigger = ""
    @State private var expansion = ""

    var body: some View {
        SettingsSectionCard(title: "Snippets", systemImage: "text.append") {
            VStack(alignment: .leading, spacing: SpeakSpacing.sm) {
                HStack(spacing: SpeakSpacing.sm) {
                    TextField("Trigger (what you say)", text: $trigger)
                        .textFieldStyle(.plain)
                        .font(.speakMonoBody)
                        .frame(width: 180)
                    Image(systemName: "arrow.right")
                        .foregroundStyle(.tertiary)
                    TextField("Expansion (what's inserted)", text: $expansion)
                        .textFieldStyle(.plain)
                        .font(.speakMonoBody)
                    Button("Add", action: addSnippet)
                        .disabled(!canAdd)
                }

                Text("Say a short trigger, get the full text — expanded before AI cleanup.")
                    .font(.speakBody(.caption))
                    .foregroundStyle(.secondary)

                if !store.snippets.isEmpty {
                    Divider()
                    ForEach(store.snippets) { snippet in
                        HStack(spacing: SpeakSpacing.sm) {
                            Text(snippet.trigger)
                                .font(.speakMonoBody)
                                .foregroundStyle(Color.speakAccent)
                            Image(systemName: "arrow.right")
                                .font(.speakMonoCaption)
                                .foregroundStyle(.tertiary)
                            Text(snippet.expansion)
                                .font(.speakMonoBody)
                                .lineLimit(2)
                            Spacer()
                            Button {
                                store.remove(id: snippet.id)
                            } label: {
                                Image(systemName: "trash")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.borderless)
                            .help("Remove snippet")
                        }
                    }
                }
            }
            .padding(.horizontal, SpeakSpacing.md)
            .padding(.vertical, SpeakSpacing.sm + 4)
        }
    }

    private var canAdd: Bool {
        !trigger.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !expansion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func addSnippet() {
        if store.add(trigger: trigger, expansion: expansion) {
            trigger = ""
            expansion = ""
        }
    }
}
