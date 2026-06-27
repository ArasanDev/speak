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
//
// LIST / PREVIEW NOTE [decision]:
//   The populated-list preview crashes under the XOJIT preview harness (macOS 26)
//   in `OutlineListCoordinator.diffRows` / `ViewListTree.visitItem` — an assertion
//   in NSOutlineView's row-height estimation triggered during `viewDidMoveToWindow`.
//   Investigation confirmed this is PREVIEW-ONLY: the real History window (verified
//   via --debug-open history with seeded entries) renders and scrolls correctly.
//   The fix applied:
//     (1) `List { ForEach(...) }` instead of `List(_:) { }` — decouples container
//         identity from data, the standard macOS 26 workaround for diffRows crashes.
//     (2) Always-mounted List with an overlay for the empty state — eliminates the
//         view-type switch (VStack ↔ List) that could cause a second assertion path
//         during async [] → [N] updates.
//   The "With entries" preview STILL crashes (XOJIT platform defect; variable-height
//   rows in List remain broken in Xcode 26.5 XOJIT). The "Empty state" preview passes
//   (zero rows never touch the crashing diffRows path). This is surfaced to the
//   orchestrator as a preview-only, non-regression defect.

import SpeakCore
import SwiftUI

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

    /// Always-mounted List with empty overlay — eliminates the VStack ↔ List
    /// view-type switch that can trigger a second assertion path on async reloads.
    /// `List { ForEach(...) }` decouples container identity from data.
    /// See file-header note for the full investigation. [decision]
    private var content: some View {
        List {
            ForEach(viewModel.entries) { entry in
                HistoryRow(entry: entry)
            }
        }
        .listStyle(.inset)
        .overlay {
            if viewModel.entries.isEmpty {
                emptyState
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "text.bubble")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text(viewModel.searchText.isEmpty
                 ? "No dictations yet"
                 : "No matches")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
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
/// "With entries" preview — KNOWN CRASH under XOJIT on macOS 26 / Xcode 26.5.
/// Root cause: `OutlineListCoordinator.diffRows` / `ViewListTree.visitItem`
/// assertion in NSOutlineView row-height estimation during `viewDidMoveToWindow`.
/// This is preview-only; the real app renders correctly (verified via
/// --debug-open history). Surfaced to orchestrator — do NOT degrade the
/// production List to fix a preview tool defect. [decision]
#Preview("With entries") {
    HistoryView(viewModel: HistoryViewModel(store: PreviewHistoryStore(empty: false)))
}

/// "Empty state" preview — passes (zero rows skip the crashing diffRows path).
/// Verifies: search bar, "No dictations yet" placeholder, disabled Export/Clear footer.
#Preview("Empty state") {
    HistoryView(viewModel: HistoryViewModel(store: PreviewHistoryStore(empty: true)))
}

/// A tiny in-memory store for SwiftUI previews only.
private final class PreviewHistoryStore: HistoryStoring, @unchecked Sendable {
    private let empty: Bool

    init(empty: Bool) {
        self.empty = empty
    }

    func save(_ entry: HistoryEntry) throws {}
    func recent(limit: Int) throws -> [HistoryEntry] {
        guard !empty else { return [] }
        return [
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
