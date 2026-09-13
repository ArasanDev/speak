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
//
// LAYOUT (shared by all three cards): a helper caption up top, the list —
// hairline-separated rows, or an inset empty-state when there's nothing —
// then the add-well at the bottom, where an editable list's controls live on
// macOS. Single-token rows (corrections, terms) delete instantly — they're
// re-typed in one keystroke, same as System Settings' text replacements.
// Snippet deletions confirm first: an expansion is authored content that
// can't be re-entered that casually. [decision: confirm only where loss is real]

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
    @FocusState private var focus: Field?

    private enum Field { case heard, typed }

    var body: some View {
        SettingsSectionCard(title: "Acoustic Corrections") {
            VStack(alignment: .leading, spacing: 0) {
                Text("What the recognizer hears → what gets typed. Runs before snippets and AI cleanup — "
                     + "each correction also biases the recognizer toward the right spelling.")
                    .font(.speakBody(.caption))
                    .foregroundStyle(Color.speakMica)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, SpeakSpacing.md)
                    .padding(.top, SpeakSpacing.sm + 4)
                    .padding(.bottom, SpeakSpacing.sm)

                let rows = store.acousticCorrections
                if rows.isEmpty {
                    ListEmptyHint(
                        systemImage: "waveform",
                        title: "No custom corrections",
                        detail: "When speak mishears a word — “cubectl” for “kubectl” — add the pair below. "
                            + "\(AcousticCorrections.builtIn.count) built-in fixes already run."
                    )
                    .padding(.horizontal, SpeakSpacing.md)
                    .padding(.bottom, SpeakSpacing.sm)
                } else {
                    SettingsRowSeparator()

                    // Column header — the row grid's labels. The hidden arrow
                    // and trailing slot mirror the row's metrics so the
                    // columns line up exactly.
                    HStack(spacing: SpeakSpacing.sm) {
                        Text("You say")
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Image(systemName: "arrow.right")
                            .hidden()
                        Text("Gets typed")
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Color.clear.frame(width: 22, height: 1)
                    }
                    .font(.speakBody(.caption))
                    .foregroundStyle(Color.speakMica)
                    .padding(.horizontal, SpeakSpacing.md)
                    .padding(.vertical, SpeakSpacing.xs)

                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, correction in
                        if index > 0 { SettingsRowSeparator() }
                        correctionRow(correction)
                    }
                }

                SettingsRowSeparator()

                addRow
                    .padding(.horizontal, SpeakSpacing.md)
                    .padding(.vertical, SpeakSpacing.sm)

                Text("\(AcousticCorrections.builtIn.count) built-in fixes are always on — e.g. “cloth code” → “Claude Code”. "
                     + "Re-add the same “You say” to override one; map it to itself to disable it.")
                    .font(.speakBody(.caption))
                    .foregroundStyle(Color.speakMica)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, SpeakSpacing.md)
                    .padding(.bottom, SpeakSpacing.sm + 4)
            }
        }
    }

    /// One mapping row: heard (mono) → typed (mono), an "Override" pill when
    /// the entry shadows a built-in fix, and the hover-tinted remove button.
    /// [decision: the override badge makes an invisible precedence rule visible]
    private func correctionRow(_ correction: AcousticCorrection) -> some View {
        HStack(spacing: SpeakSpacing.sm) {
            Text(correction.heard)
                .font(.speakMonoFace(.base))
                .foregroundStyle(Color.speakBone)
                .frame(maxWidth: .infinity, alignment: .leading)

            Image(systemName: "arrow.right")
                .font(.speakBody(.caption))
                .foregroundStyle(Color.speakMica)

            HStack(spacing: SpeakSpacing.xs) {
                Text(correction.typed)
                    .font(.speakMonoFace(.base))
                    .foregroundStyle(Color.speakBone)
                if overridesBuiltIn(correction) {
                    SettingsStatusPill(text: "Override", tint: .speakMica)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            RowRemoveButton(help: "Remove “\(correction.heard)” → “\(correction.typed)”") {
                remove(correction)
            }
        }
        .padding(.horizontal, SpeakSpacing.md)
        .padding(.vertical, SpeakSpacing.xs + 2)
    }

    /// The add-well: both fields inside one recessed surface (the well is the
    /// field chrome — the fields themselves stay plain), Return chains
    /// heard → typed → add → back to heard so a batch of entries never
    /// touches the mouse.
    private var addRow: some View {
        HStack(spacing: SpeakSpacing.sm) {
            HStack(spacing: SpeakSpacing.sm) {
                TextField("You say — e.g. “cubectl”", text: $heard)
                    .textFieldStyle(.plain)
                    .font(.speakBody(.base))
                    .tint(.speakUIAccent)
                    .frame(maxWidth: .infinity)
                    .focused($focus, equals: .heard)
                    .onSubmit { focus = .typed }
                Image(systemName: "arrow.right")
                    .font(.speakBody(.caption))
                    .foregroundStyle(Color.speakMica)
                TextField("Gets typed — e.g. “kubectl”", text: $typed)
                    .textFieldStyle(.plain)
                    .font(.speakBody(.base))
                    .tint(.speakUIAccent)
                    .frame(maxWidth: .infinity)
                    .focused($focus, equals: .typed)
                    .onSubmit(addCorrection)
            }
            .padding(.horizontal, SpeakSpacing.sm + 2)
            .padding(.vertical, SpeakSpacing.sm - 2)
            .speakInset()

            AddButton(action: addCorrection, isEnabled: canAdd)
        }
    }

    private var canAdd: Bool {
        !heard.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !typed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func overridesBuiltIn(_ correction: AcousticCorrection) -> Bool {
        AcousticCorrections.builtIn.contains {
            $0.heard.caseInsensitiveCompare(correction.heard) == .orderedSame
        }
    }

    private func addCorrection() {
        guard canAdd else { return }
        store.acousticCorrections = AcousticCorrections.upsert(
            heard: heard,
            typed: typed,
            in: store.acousticCorrections
        )
        heard = ""
        typed = ""
        focus = .heard
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
    /// Set when an add attempt was a case-insensitive duplicate — the store
    /// rule (`CustomVocabulary.adding`) silently no-ops on dupes, so the UI
    /// owns telling the user nothing happened.
    @State private var duplicateTerm: String?

    var body: some View {
        SettingsSectionCard(title: "Custom Vocabulary") {
            VStack(alignment: .leading, spacing: 0) {
                Text("Names and jargon the recognizer should expect — fed in as hints, and also passed to AI cleanup so spellings survive rewriting.")
                    .font(.speakBody(.caption))
                    .foregroundStyle(Color.speakMica)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, SpeakSpacing.md)
                    .padding(.top, SpeakSpacing.sm + 4)
                    .padding(.bottom, SpeakSpacing.sm)

                let terms = store.customVocabulary
                if terms.isEmpty {
                    ListEmptyHint(
                        systemImage: "character.book.closed",
                        title: "No custom terms",
                        detail: "A built-in developer dictionary is always on — add the teammates, projects, and jargon it doesn't know."
                    )
                    .padding(.horizontal, SpeakSpacing.md)
                    .padding(.bottom, SpeakSpacing.sm)
                } else {
                    SettingsRowSeparator()

                    ForEach(Array(terms.enumerated()), id: \.element) { index, term in
                        if index > 0 { SettingsRowSeparator() }
                        HStack(spacing: SpeakSpacing.sm) {
                            Text(term)
                                .font(.speakMonoFace(.base))
                                .foregroundStyle(Color.speakBone)
                            Spacer(minLength: 0)
                            RowRemoveButton(help: "Remove “\(term)”") {
                                removeTerm(term)
                            }
                        }
                        .padding(.horizontal, SpeakSpacing.md)
                        .padding(.vertical, SpeakSpacing.xs + 2)
                    }
                }

                SettingsRowSeparator()

                addRow
                    .padding(.horizontal, SpeakSpacing.md)
                    .padding(.vertical, SpeakSpacing.sm)

                if let duplicateTerm {
                    HStack(spacing: SpeakSpacing.xs) {
                        Image(systemName: "info.circle")
                        Text("“\(duplicateTerm)” is already in your vocabulary.")
                    }
                    .font(.speakBody(.caption))
                    .foregroundStyle(Color.speakMica)
                    .padding(.horizontal, SpeakSpacing.md)
                    .padding(.bottom, SpeakSpacing.sm + 4)
                    .transition(.opacity)
                } else {
                    Spacer(minLength: SpeakSpacing.xs)
                }
            }
        }
    }

    private var addRow: some View {
        HStack(spacing: SpeakSpacing.sm) {
            TextField("Add a word or name — e.g. “Karthik”", text: $newTerm)
                .textFieldStyle(.plain)
                .font(.speakBody(.base))
                .tint(.speakUIAccent)
                .onSubmit(addTerm)
                .onChange(of: newTerm) { _, _ in duplicateTerm = nil }
                .padding(.horizontal, SpeakSpacing.sm + 2)
                .padding(.vertical, SpeakSpacing.sm - 2)
                .speakInset()

            AddButton(action: addTerm, isEnabled: canAdd)
        }
    }

    private var canAdd: Bool {
        !newTerm.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func addTerm() {
        guard canAdd else { return }
        let before = store.customVocabulary
        let after = CustomVocabulary.adding(newTerm, to: before)
        if after.count == before.count {
            // Blank is gated by canAdd, so an unchanged list means a
            // case-insensitive duplicate — say so instead of no-oping.
            duplicateTerm = newTerm.trimmingCharacters(in: .whitespacesAndNewlines)
            return
        }
        store.customVocabulary = after
        newTerm = ""
        duplicateTerm = nil
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
    /// Set when the user hits remove — the row's expansion is authored text,
    /// so the delete confirms instead of firing instantly.
    @State private var pendingRemoval: Snippet?
    @FocusState private var focus: Field?

    private enum Field { case trigger, expansion }

    var body: some View {
        SettingsSectionCard(title: "Snippets") {
            VStack(alignment: .leading, spacing: 0) {
                Text("Say a short trigger, get the full text — expanded before AI cleanup. Adding an existing trigger updates its expansion.")
                    .font(.speakBody(.caption))
                    .foregroundStyle(Color.speakMica)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, SpeakSpacing.md)
                    .padding(.top, SpeakSpacing.sm + 4)
                    .padding(.bottom, SpeakSpacing.sm)

                let snippets = store.snippets
                if snippets.isEmpty {
                    ListEmptyHint(
                        systemImage: "wand.and.stars",
                        title: "No snippets",
                        detail: "Add a trigger like “my email” that expands to your full address — signatures, links, canned replies."
                    )
                    .padding(.horizontal, SpeakSpacing.md)
                    .padding(.bottom, SpeakSpacing.sm)
                } else {
                    SettingsRowSeparator()

                    HStack(spacing: SpeakSpacing.sm) {
                        Text("Trigger")
                            .frame(width: 150, alignment: .leading)
                        Image(systemName: "arrow.right")
                            .hidden()
                        Text("Expands to")
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Color.clear.frame(width: 22, height: 1)
                    }
                    .font(.speakBody(.caption))
                    .foregroundStyle(Color.speakMica)
                    .padding(.horizontal, SpeakSpacing.md)
                    .padding(.vertical, SpeakSpacing.xs)

                    ForEach(Array(snippets.enumerated()), id: \.element.id) { index, snippet in
                        if index > 0 { SettingsRowSeparator() }
                        snippetRow(snippet)
                    }
                }

                SettingsRowSeparator()

                addRow
                    .padding(.horizontal, SpeakSpacing.md)
                    .padding(.vertical, SpeakSpacing.sm)

                Spacer(minLength: SpeakSpacing.xs)
            }
        }
        .alert(
            "Remove this snippet?",
            isPresented: Binding(
                get: { pendingRemoval != nil },
                set: { if !$0 { pendingRemoval = nil } }
            ),
            presenting: pendingRemoval
        ) { snippet in
            Button("Remove", role: .destructive) {
                store.remove(id: snippet.id)
            }
            Button("Cancel", role: .cancel) {}
        } message: { snippet in
            Text("“\(snippet.trigger)” will no longer expand.")
        }
    }

    private func snippetRow(_ snippet: Snippet) -> some View {
        HStack(alignment: .top, spacing: SpeakSpacing.sm) {
            Text(snippet.trigger)
                .font(.speakMonoFace(.base))
                .foregroundStyle(Color.speakBone)
                .frame(width: 150, alignment: .leading)
                .lineLimit(1)
            Image(systemName: "arrow.right")
                .font(.speakBody(.caption))
                .foregroundStyle(Color.speakMica)
                .padding(.top, 2)
            Text(snippet.expansion)
                .font(.speakMonoFace(.base))
                .foregroundStyle(Color.speakBone)
                .lineLimit(2)
                .help(snippet.expansion)
            Spacer(minLength: 0)
            RowRemoveButton(help: "Remove “\(snippet.trigger)”") {
                pendingRemoval = snippet
            }
        }
        .padding(.horizontal, SpeakSpacing.md)
        .padding(.vertical, SpeakSpacing.xs + 2)
    }

    private var addRow: some View {
        HStack(spacing: SpeakSpacing.sm) {
            HStack(spacing: SpeakSpacing.sm) {
                TextField("Trigger — e.g. “my email”", text: $trigger)
                    .textFieldStyle(.plain)
                    .font(.speakBody(.base))
                    .tint(.speakUIAccent)
                    .frame(width: 150)
                    .focused($focus, equals: .trigger)
                    .onSubmit { focus = .expansion }
                Image(systemName: "arrow.right")
                    .font(.speakBody(.caption))
                    .foregroundStyle(Color.speakMica)
                TextField("Expands to — e.g. “tamil@example.com”", text: $expansion)
                    .textFieldStyle(.plain)
                    .font(.speakBody(.base))
                    .tint(.speakUIAccent)
                    .frame(maxWidth: .infinity)
                    .focused($focus, equals: .expansion)
                    .onSubmit(addSnippet)
            }
            .padding(.horizontal, SpeakSpacing.sm + 2)
            .padding(.vertical, SpeakSpacing.sm - 2)
            .speakInset()

            AddButton(action: addSnippet, isEnabled: canAdd)
        }
    }

    private var canAdd: Bool {
        !trigger.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !expansion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// One trigger maps to one expansion — `SnippetStore.add` always appends,
    /// so an existing row with the same trigger (any case) is removed first,
    /// matching `AcousticCorrections.upsert` semantics. [decision]
    private func addSnippet() {
        guard canAdd else { return }
        let trimmedTrigger = trigger.trimmingCharacters(in: .whitespacesAndNewlines)
        for existing in store.snippets
        where existing.trigger.caseInsensitiveCompare(trimmedTrigger) == .orderedSame {
            store.remove(id: existing.id)
        }
        if store.add(trigger: trigger, expansion: expansion) {
            trigger = ""
            expansion = ""
            focus = .trigger
        }
    }
}

// MARK: - Shared pieces

/// "+ Add" — the primary action of each card's add-well. Prominent so the
/// well's fields have a visible commit path beyond Return.
private struct AddButton: View {
    let action: () -> Void
    let isEnabled: Bool

    var body: some View {
        Button(action: action) {
            Label("Add", systemImage: "plus")
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.small)
        .tint(.speakUIAccent)
        .disabled(!isEnabled)
    }
}

/// The trash affordance on a list row — mica at rest, error-tinted on hover
/// so the destructive edge shows before the click lands.
private struct RowRemoveButton: View {
    let help: String
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "trash")
                .font(.speakBody(.caption))
                .foregroundStyle(hovering ? Color.speakError : Color.speakMica)
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(help)
        .accessibilityLabel(help)
    }
}

/// A real empty state — tinted glyph tile + one line of guidance — rendered
/// in place of the list so an empty card still teaches the feature.
private struct ListEmptyHint: View {
    let systemImage: String
    let title: String
    let detail: String

    var body: some View {
        HStack(spacing: SpeakSpacing.sm + 2) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.speakMica)
                .frame(width: 26, height: 26)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Color.speakSurface)
                        .overlay(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .stroke(Color.speakCardBorder, lineWidth: 1)
                        )
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.speakBody(.base, semibold: true))
                    .foregroundStyle(Color.speakBone)
                Text(detail)
                    .font(.speakBody(.caption))
                    .foregroundStyle(Color.speakMica)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(SpeakSpacing.sm + 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .speakInset(cornerRadius: 10)
    }
}

// MARK: - Preview

#if DEBUG
#Preview("Vocabulary") {
    VocabularySettingsView(context: DashboardContext(
        settingsStore: SettingsStore(),
        historyStore: PreviewNullHistoryStore(),
        hotkeyCombo: ["Fn", "Fn"]
    ))
    .padding(SpeakSpacing.lg)
    .frame(width: 720)
    .background(Color.speakWindowCanvas)
}
#endif
