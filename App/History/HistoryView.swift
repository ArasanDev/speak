// App/History/HistoryView.swift
//
// The History window content (roadmap P9): a searchable list of past dictations
// with Clear and Export actions. Surfaces the store layer that was already built
// and unit-tested (`HistoryStore`, `HistoryStoreTests`).
//
// DESIGN:
//   - A search field at the top binds to `viewModel.searchText` (live substring
//     search via the store).
//   - A scrolling list of entries: cleaned text (or raw when cleanup was off),
//     with the timestamp + engine id as secondary metadata.
//   - A toolbar footer with "Export…" and "Clear History" (destructive).
//   - Empty state when there are no entries (or no search matches).
//
// HONESTY BOUNDARY:
//   Rendered/interactive behavior is [deferred — human verification §4.5].

import SwiftUI
import SpeakCore

// MARK: - HistoryView

struct HistoryView: View {
    @ObservedObject var viewModel: HistoryViewModel

    var body: some View {
        VStack(spacing: 0) {
            searchBar
            Divider()
            content
            Divider()
            footer
        }
        .frame(minWidth: 480, minHeight: 420)
        .onAppear { viewModel.onAppear() }
    }

    // MARK: - Search bar

    private var searchBar: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search dictations", text: $viewModel.searchText)
                .textFieldStyle(.plain)
            if viewModel.isLoading {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .padding(10)
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if viewModel.entries.isEmpty {
            emptyState
        } else {
            List(viewModel.entries) { entry in
                HistoryRow(entry: entry)
            }
            .listStyle(.inset)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "text.bubble")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text(viewModel.searchText.isEmpty
                 ? "No dictations yet"
                 : "No matches")
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Button("Export\u{2026}") { viewModel.exportToFile() }
                .disabled(viewModel.entries.isEmpty)
            Spacer()
            Button("Clear History", role: .destructive) { viewModel.clearAll() }
                .disabled(viewModel.entries.isEmpty)
        }
        .padding(10)
    }
}

// MARK: - HistoryRow

private struct HistoryRow: View {
    let entry: HistoryEntry

    /// The text to show: cleaned output when cleanup ran, else the raw transcript.
    private var displayText: String {
        entry.cleanedText ?? entry.rawText
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(displayText)
                .lineLimit(3)
            HStack(spacing: 6) {
                Text(entry.createdAt, style: .date)
                Text(entry.createdAt, style: .time)
                Text("·")
                Text(entry.engineId)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Preview

#if DEBUG
#Preview {
    HistoryView(viewModel: HistoryViewModel(store: PreviewHistoryStore()))
}

/// A tiny in-memory store for SwiftUI previews only.
private final class PreviewHistoryStore: HistoryStoring, @unchecked Sendable {
    func save(_ entry: HistoryEntry) throws {}
    func recent(limit: Int) throws -> [HistoryEntry] {
        [
            HistoryEntry(rawText: "hello world this is a test",
                         cleanedText: "Hello world, this is a test.",
                         engineId: "apple-speech-en-US+foundation-models"),
            HistoryEntry(rawText: "raw only no cleanup",
                         cleanedText: nil,
                         engineId: "apple-speech-en-US")
        ]
    }
    func search(_ substring: String) throws -> [HistoryEntry] { [] }
    func clear() throws {}
    func export() throws -> String { "[]" }
}
#endif
