// App/Dashboard/Panes/SnippetsPaneView.swift
//
// The Snippets pane — manage trigger→expansion text snippets applied to a transcript
// BEFORE the LLM cleanup pass (verified Wispr behavior). Binds to the shared
// `SnippetStore`; the engine reads it at dictation start (SpeakEngine.newSession).
//
// Matches the verified Wispr Snippets screen: a trigger field + an expansion field +
// the list of saved snippets with delete.

import SpeakCore
import SwiftUI

// MARK: - SnippetsPaneView

struct SnippetsPaneView: View {
    let context: DashboardContext

    @ObservedObject private var store: SnippetStore
    @State private var trigger: String = ""
    @State private var expansion: String = ""

    init(context: DashboardContext) {
        self.context = context
        self.store = context.snippetStore
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PaneHeader(
                title: "Snippets",
                subtitle: "Say a short trigger, get the full text — expanded before AI cleanup."
            )
            editor
            content
        }
    }

    // MARK: - Editor

    private var editor: some View {
        VStack(spacing: SpeakSpacing.sm) {
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
            }
            HStack {
                Spacer()
                Button("Add snippet", action: addSnippet)
                    .disabled(!canAdd)
            }
        }
        .padding(SpeakSpacing.md)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.speakSurface))
        .padding(.horizontal, SpeakSpacing.lg)
        .padding(.bottom, SpeakSpacing.md)
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if store.snippets.isEmpty {
            PanePlaceholder(
                systemImage: "text.append",
                message: "No snippets yet. Add one above — e.g. \"my email\" → your full address."
            )
        } else {
            List {
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
                            Image(systemName: "trash").foregroundStyle(.secondary)
                        }
                        .buttonStyle(.borderless)
                        .help("Remove snippet")
                    }
                    .padding(.vertical, SpeakSpacing.xs)
                }
            }
            .listStyle(.inset)
        }
    }

    // MARK: - Actions

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

// MARK: - Preview

#if DEBUG
#Preview("Snippets") {
    SnippetsPaneView(context: DashboardContext(
        settingsStore: SettingsStore(),
        historyStore: PreviewNullHistoryStore(),
        hotkeyCombo: ["Fn", "Fn"]
    ))
    .frame(width: 620, height: 520)
}
#endif
