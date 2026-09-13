// App/Settings/VocabularySettingsView.swift
//
// "Vocabulary" — a CONTROL category of the dedicated Settings experience.
// Three cards: acoustic corrections (heard → typed), custom vocabulary (terms
// fed to SpeechAnalyzer as contextual hints), and snippets (trigger →
// expansion pairs applied before AI cleanup).
//
// This is the single home for vocabulary config — the desk's old Dictionary/
// Snippets panes were removed (one home per capability: config lives in
// Settings, workspaces live on the dashboard).

import SpeakCore
import SwiftUI

// MARK: - VocabularySettingsView

@MainActor
struct VocabularySettingsView: View {
    let context: DashboardContext

    var body: some View {
        VStack(alignment: .leading, spacing: SpeakSpacing.lg) {
            AcousticCorrectionsCard(store: context.settingsStore)
            CustomVocabularyCard(store: context.settingsStore)
            SnippetsCard(store: context.snippetStore)
        }
    }
}

// MARK: - AcousticCorrectionsCard

/// The "what you say → what gets typed" table. Corrections run as a whole-word
/// replacement pass on the raw transcript BEFORE snippets and AI cleanup, and
/// each `typed` term is also fed to the recognizer + cleanup prompt as a
/// contextual hint (`SettingsStore.effectiveVocabulary`). [decision]
private struct AcousticCorrectionsCard: View {
    let store: SettingsStore
    @State private var heard = ""
    @State private var typed = ""

    var body: some View {
        SettingsSectionCard(title: "Acoustic Corrections") {
            VStack(alignment: .leading, spacing: SpeakSpacing.sm) {
                HStack(spacing: SpeakSpacing.sm) {
                    TextField("What you say (e.g. “cubectl”)", text: $heard)
                        .textFieldStyle(.plain)
                        .font(.speakBody(.base))
                        .frame(width: 190)
                        .onSubmit(addCorrection)
                    Image(systemName: "arrow.right")
                        .foregroundStyle(Color.speakMica)
                    TextField("What gets typed (e.g. “kubectl”)", text: $typed)
                        .textFieldStyle(.plain)
                        .font(.speakBody(.base))
                        .onSubmit(addCorrection)
                    Spacer(minLength: 0)
                    AddButton(action: addCorrection, isEnabled: canAdd)
                }

                Text("Fixes systematic mishearings before cleanup — and biases the recognizer toward the corrected term. Applies to the next dictation.")
                    .font(.speakBody(.caption))
                    .foregroundStyle(Color.speakMica)

                let rows = store.acousticCorrections
                if !rows.isEmpty {
                    Divider()
                        .overlay(Color.speakCardBorder.opacity(0.6))

                    // Column header — t3code-style table chrome.
                    HStack(spacing: SpeakSpacing.sm) {
                        Text("You say")
                            .frame(width: 190, alignment: .leading)
                        Image(systemName: "arrow.right")
                            .font(.speakBody(.caption))
                        Text("Gets typed")
                        Spacer()
                    }
                    .font(.speakBody(.caption))
                    .foregroundStyle(Color.speakMica)

                    ForEach(rows) { correction in
                        HStack(spacing: SpeakSpacing.sm) {
                            Text(correction.heard)
                                .font(.speakMonoFace(.base))
                                .foregroundStyle(Color.speakBone)
                                .frame(width: 190, alignment: .leading)
                            Image(systemName: "arrow.right")
                                .font(.speakBody(.caption))
                                .foregroundStyle(Color.speakMica)
                            Text(correction.typed)
                                .font(.speakMonoFace(.base))
                                .foregroundStyle(Color.speakBone)
                            Spacer()
                            Button {
                                remove(correction)
                            } label: {
                                Image(systemName: "trash")
                                    .foregroundStyle(Color.speakMica)
                            }
                            .buttonStyle(.borderless)
                            .help("Remove \(correction.heard) → \(correction.typed)")
                        }
                    }
                }
            }
            .padding(.horizontal, SpeakSpacing.md)
            .padding(.vertical, SpeakSpacing.sm + 4)
        }
    }

    private var canAdd: Bool {
        !heard.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !typed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func addCorrection() {
        store.acousticCorrections = AcousticCorrections.upsert(
            heard: heard,
            typed: typed,
            in: store.acousticCorrections
        )
        heard = ""
        typed = ""
    }

    private func remove(_ correction: AcousticCorrection) {
        store.acousticCorrections = AcousticCorrections.removing(
            heard: correction.heard,
            from: store.acousticCorrections
        )
    }
}

// MARK: - CustomVocabularyCard

private struct CustomVocabularyCard: View {
    let store: SettingsStore
    @State private var newTerm = ""

    var body: some View {
        SettingsSectionCard(title: "Custom Vocabulary") {
            VStack(alignment: .leading, spacing: SpeakSpacing.sm) {
                HStack(spacing: SpeakSpacing.sm) {
                    TextField("Add a word or name…", text: $newTerm)
                        .textFieldStyle(.plain)
                        .font(.speakBody(.base))
                        .onSubmit(addTerm)
                    Spacer(minLength: 0)
                    AddButton(action: addTerm, isEnabled: !newTerm.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                Text("Fed to the speech recognizer as contextual hints so names and jargon spell correctly.")
                    .font(.speakBody(.caption))
                    .foregroundStyle(Color.speakMica)

                let terms = store.customVocabulary
                if !terms.isEmpty {
                    Divider()
                        .overlay(Color.speakCardBorder.opacity(0.6))
                    ForEach(terms, id: \.self) { term in
                        HStack {
                            Text(term)
                                .font(.speakMonoFace(.base))
                                .foregroundStyle(Color.speakBone)
                            Spacer()
                            Button {
                                removeTerm(term)
                            } label: {
                                Image(systemName: "trash")
                                    .foregroundStyle(Color.speakMica)
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
        SettingsSectionCard(title: "Snippets") {
            VStack(alignment: .leading, spacing: SpeakSpacing.sm) {
                HStack(spacing: SpeakSpacing.sm) {
                    TextField("Trigger (what you say)", text: $trigger)
                        .textFieldStyle(.plain)
                        .font(.speakBody(.base))
                        .frame(width: 180)
                        .onSubmit(addSnippet)
                    Image(systemName: "arrow.right")
                        .foregroundStyle(Color.speakMica)
                    TextField("Expansion (what's inserted)", text: $expansion)
                        .textFieldStyle(.plain)
                        .font(.speakBody(.base))
                        .onSubmit(addSnippet)
                    Spacer(minLength: 0)
                    AddButton(action: addSnippet, isEnabled: canAdd)
                }

                Text("Say a short trigger, get the full text — expanded before AI cleanup.")
                    .font(.speakBody(.caption))
                    .foregroundStyle(Color.speakMica)

                if !store.snippets.isEmpty {
                    Divider()
                        .overlay(Color.speakCardBorder.opacity(0.6))
                    ForEach(store.snippets) { snippet in
                        HStack(spacing: SpeakSpacing.sm) {
                            Text(snippet.trigger)
                                .font(.speakMonoFace(.base))
                                .foregroundStyle(Color.speakBone)
                            Image(systemName: "arrow.right")
                                .font(.speakBody(.caption))
                                .foregroundStyle(Color.speakMica)
                            Text(snippet.expansion)
                                .font(.speakMonoFace(.base))
                                .foregroundStyle(Color.speakBone)
                                .lineLimit(2)
                            Spacer()
                            Button {
                                store.remove(id: snippet.id)
                            } label: {
                                Image(systemName: "trash")
                                    .foregroundStyle(Color.speakMica)
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

// MARK: - Add button

/// Shared "+ Add" affordance used by all three vocabulary cards.
private struct AddButton: View {
    let action: () -> Void
    let isEnabled: Bool

    var body: some View {
        Button(action: action) {
            Label("Add", systemImage: "plus")
        }
        .disabled(!isEnabled)
        .controlSize(.small)
        .tint(.speakUIAccent)
    }
}
