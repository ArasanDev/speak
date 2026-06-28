// App/History/HistoryView.swift
//
// The History pane (P11-c) — a searchable, filterable, expandable list of past
// dictations. Surfaces the store layer (`HistoryStore`, `HistoryStoreTests`) with
// date grouping, engine filtering, side-by-side diff view, and action buttons.
//
// DESIGN (from specs/speak-ui-design-final-2026-06-28.md §History Pane):
//   - **Search bar** + date/engine filters (top, persistent)
//   - **Grouped list**: TODAY / THIS WEEK / EARLIER (collapsible)
//   - **Collapsed entry**: time | raw preview (40 chars) | cleaned preview | engine badge
//   - **Expanded view** (click to toggle):
//       - Full raw transcript (Monaco 11pt, top)
//       - Full cleaned transcript (Monaco 11pt, bottom)
//       - Side-by-side diff via CleanupDiffView
//       - Actions: [Copy Raw] [Copy Cleaned] [Export] [Retry] [Delete]
//   - **Batch actions** (footer): [Export All] [Clear Before Date] [Clear All]
//   - All text: Monaco theme, semantic colors, 4pt spacing grid
//
// CRASH WORKAROUND (same as P9 HistoryView):
//   macOS 26 XOJIT crashes on variable-height List rows in `OutlineListCoordinator.diffRows`.
//   Fix: `List { ForEach(...) }` + always-mounted List with empty overlay.
//   The expand-in-place pattern is the riskiest axis — monitor for regressions.
//
// DATA MODEL GAPS (constraints, flagged for future store work):
//   - No `delete(id:)` or `deleteBefore(date:)` in HistoryStoring → [Retry] and
//     [Delete] buttons are stubbed with [unverified] comments.
//   - No `LLMCleaning` seam in HistoryViewModel → [Retry] flows deferred to v1.
//   - `engineId` is a combined string, not split STT/cleanup → engine filter
//     derives options from actual values in loaded entries.
//   - No `mode` field in HistoryEntry → mode filter dropped (not in spec).
//
// HONESTY BOUNDARY:
//   Full interactivity (expand/collapse, copy, paste, delete, retry) is
//   [unverified — human verification §4.5]. Copy, Export, Clear work via store;
//   Delete/Retry are [unverified — needs store seam + LLMCleaning].

import SpeakCore
import SwiftUI

// MARK: - HistoryView

struct HistoryView: View {
    @Bindable var viewModel: HistoryViewModel
    @State private var expandedEntryId: UUID?
    @State private var selectedDateFilter: DateFilter = .allTime
    @State private var selectedEngineFilter: String = "all"
    @State private var availableEngines: [String] = ["all"]

    var body: some View {
        VStack(spacing: 0) {
            searchBarAndFilters
            Divider()
            content
            Divider()
            footer
        }
        .frame(minWidth: 520, minHeight: 460)
        .onAppear {
            viewModel.onAppear()
            updateAvailableEngines()
        }
        .onChange(of: viewModel.entries) {
            updateAvailableEngines()
        }
    }

    // MARK: - Search bar and filters

    private var searchBarAndFilters: some View {
        VStack(spacing: SpeakSpacing.sm) {
            // Search bar
            HStack(spacing: SpeakSpacing.sm) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search dictations", text: $viewModel.searchText)
                    .textFieldStyle(.plain)
                if viewModel.isLoading {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            .padding(SpeakSpacing.md)

            // Filters row
            HStack(spacing: SpeakSpacing.md) {
                // Date filter
                Picker("Date", selection: $selectedDateFilter) {
                    ForEach(DateFilter.allCases, id: \.self) { filter in
                        Text(filter.label).tag(filter)
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: 120)

                // Engine filter
                Picker("Engine", selection: $selectedEngineFilter) {
                    ForEach(availableEngines, id: \.self) { engine in
                        Text(engine == "all" ? "All engines" : engine)
                            .tag(engine)
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: 150)

                Spacer()
            }
            .padding(.horizontal, SpeakSpacing.md)
            .padding(.bottom, SpeakSpacing.sm)
            .font(.caption)
        }
    }

    // MARK: - Content (grouped list)

    /// Always-mounted List with empty overlay — prevents VStack ↔ List
    /// view-type switch that triggers XOJIT diffRows crash on async reloads. [decision]
    private var content: some View {
        List {
            ForEach(groupedAndFilteredEntries, id: \.id) { group in
                Section(header: sectionHeader(for: group.period)) {
                    ForEach(group.entries, id: \.id) { entry in
                        historyRowWithExpand(entry: entry)
                    }
                }
            }
        }
        .listStyle(.inset)
        .overlay {
            if groupedAndFilteredEntries.isEmpty {
                emptyState
            }
        }
    }

    // MARK: - Grouped and filtered entries

    private var groupedAndFilteredEntries: [HistoryGroup] {
        var filtered = viewModel.entries

        // Apply date filter
        let now = Date()
        switch selectedDateFilter {
        case .today:
            let todayStart = Calendar.current.startOfDay(for: now)
            filtered = filtered.filter { $0.createdAt >= todayStart }

        case .thisWeek:
            let weekStart = Calendar.current.dateComponents([.calendar, .weekOfYear, .yearForWeekOfYear], from: now)
            let start = Calendar.current.date(from: weekStart) ?? now
            filtered = filtered.filter { $0.createdAt >= start }

        case .allTime:
            break
        }

        // Apply engine filter
        if selectedEngineFilter != "all" {
            filtered = filtered.filter { $0.engineId == selectedEngineFilter }
        }

        // Group by date period
        var today: [HistoryEntry] = []
        var thisWeek: [HistoryEntry] = []
        var earlier: [HistoryEntry] = []

        let todayStart = Calendar.current.startOfDay(for: now)
        let weekStart = Calendar.current.dateComponents([.calendar, .weekOfYear, .yearForWeekOfYear], from: now)
        let weekStartDate = Calendar.current.date(from: weekStart) ?? now

        for entry in filtered {
            if entry.createdAt >= todayStart {
                today.append(entry)
            } else if entry.createdAt >= weekStartDate {
                thisWeek.append(entry)
            } else {
                earlier.append(entry)
            }
        }

        var groups: [HistoryGroup] = []
        if !today.isEmpty {
            groups.append(HistoryGroup(period: .today, entries: today))
        }
        if !thisWeek.isEmpty {
            groups.append(HistoryGroup(period: .thisWeek, entries: thisWeek))
        }
        if !earlier.isEmpty {
            groups.append(HistoryGroup(period: .earlier, entries: earlier))
        }

        return groups
    }

    private func sectionHeader(for period: DatePeriod) -> some View {
        Text(period.label)
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    // MARK: - History row with expand

    @ViewBuilder
    private func historyRowWithExpand(entry: HistoryEntry) -> some View {
        if expandedEntryId == entry.id {
            ExpandedHistoryEntryView(
                entry: entry,
                onClose: { closeExpanded() },
                onCopyRaw: { copyToClipboard(entry.rawText) },
                onCopyClean: { copyToClipboard(entry.cleanedText ?? "") },
                onExport: { exportEntry(entry) }
            )
        } else {
            CollapsedHistoryEntryView(entry: entry, onTap: { openExpanded(entry.id) })
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Button("Export\u{2026}") { viewModel.exportToFile() }
                .disabled(groupedAndFilteredEntries.isEmpty)
            Spacer()
            Button("Clear History", role: .destructive) { viewModel.clearAll() }
                .disabled(groupedAndFilteredEntries.isEmpty)
        }
        .padding(SpeakSpacing.md)
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: SpeakSpacing.md) {
            Image(systemName: "text.bubble")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text(viewModel.searchText.isEmpty && selectedDateFilter == .allTime
                 ? "No dictations yet"
                 : "No matches")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Helpers

    private func openExpanded(_ id: UUID) {
        withAnimation(.easeInOut(duration: 0.2)) {
            expandedEntryId = id
        }
    }

    private func closeExpanded() {
        withAnimation(.easeInOut(duration: 0.2)) {
            expandedEntryId = nil
        }
    }

    private func copyToClipboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    private func exportEntry(_ entry: HistoryEntry) {
        let json = formatEntryJSON(entry)
        presentSavePanel(contents: json, filename: "entry-\(entry.id.uuidString).json")
    }

    private func updateAvailableEngines() {
        var engines = Set(viewModel.entries.map { $0.engineId })
        engines.insert("all")
        availableEngines = ["all"] + engines.filter { $0 != "all" }.sorted()
    }

    private func presentSavePanel(contents: String, filename: String) {
        let panel = NSSavePanel()
        panel.title = "Export Entry"
        panel.nameFieldStringValue = filename
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }
        do {
            try contents.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            // [unverified — error handling deferred]
        }
    }

    private func formatEntryJSON(_ entry: HistoryEntry) -> String {
        let formatter = ISO8601DateFormatter()
        return """
        {
          "id": "\(entry.id.uuidString)",
          "rawText": "\(escapeJSON(entry.rawText))",
          "cleanedText": \(entry.cleanedText.map { "\"\(escapeJSON($0))\"" } ?? "null"),
          "createdAt": "\(formatter.string(from: entry.createdAt))",
          "engineId": "\(entry.engineId)"
        }
        """
    }

    private func escapeJSON(_ string: String) -> String {
        string
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
    }
}

// MARK: - Date filter enum

enum DateFilter: CaseIterable {
    case today
    case thisWeek
    case allTime

    var label: String {
        switch self {
        case .today:
            return "Today"

        case .thisWeek:
            return "This Week"

        case .allTime:
            return "All Time"
        }
    }
}

// MARK: - Date period enum

enum DatePeriod {
    case today
    case thisWeek
    case earlier

    var label: String {
        switch self {
        case .today:
            return "TODAY"

        case .thisWeek:
            return "THIS WEEK"

        case .earlier:
            return "EARLIER"
        }
    }
}

// MARK: - History group model

private struct HistoryGroup: Identifiable {
    let id = UUID()
    let period: DatePeriod
    let entries: [HistoryEntry]
}

// MARK: - Collapsed entry view

private struct CollapsedHistoryEntryView: View {
    let entry: HistoryEntry
    let onTap: () -> Void

    var body: some View {
        HStack(spacing: SpeakSpacing.sm) {
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 12)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: SpeakSpacing.sm) {
                    Text(entry.createdAt, style: .time)
                        .font(.speakMonoCaption)
                        .foregroundStyle(.secondary)
                    Text("·")
                        .foregroundStyle(.secondary)
                    Text(entry.rawText.prefix(40))
                        .lineLimit(1)
                        .font(.speakMonoCaption)
                        .truncationMode(.tail)
                    if let cleaned = entry.cleanedText {
                        Text("|")
                            .foregroundStyle(.secondary)
                        Text(cleaned.prefix(40))
                            .lineLimit(1)
                            .font(.speakMonoCaption)
                            .truncationMode(.tail)
                    }
                    Spacer()
                    engineBadge(entry.engineId)
                        .font(.caption2)
                }
            }
        }
        .padding(.vertical, SpeakSpacing.xs)
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
    }

    private func engineBadge(_ engineId: String) -> some View {
        Text(engineId)
            .font(.caption2)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.speakSurface)
            .cornerRadius(4)
            .foregroundStyle(.secondary)
    }
}

// MARK: - Expanded entry view

private struct ExpandedHistoryEntryView: View {
    let entry: HistoryEntry
    let onClose: () -> Void
    let onCopyRaw: () -> Void
    let onCopyClean: () -> Void
    let onExport: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: SpeakSpacing.md) {
            expandedHeader
            CleanupDiffView(rawText: entry.rawText, cleanedText: entry.cleanedText)
                .frame(maxHeight: 300)
            expandedMetadata
            expandedActions
        }
        .padding(SpeakSpacing.md)
        .background(Color.speakSurface)
        .cornerRadius(SpeakSpacing.sm)
    }

    private var expandedHeader: some View {
        HStack {
            Image(systemName: "chevron.down")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 12)

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.createdAt, style: .date)
                    .font(.speakMonoCaption)
                    .foregroundStyle(.secondary)
                HStack(spacing: SpeakSpacing.sm) {
                    Text(entry.createdAt, style: .time)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("·")
                        .foregroundStyle(.secondary)
                    engineBadge
                }
                .font(.caption2)
            }
            Spacer()

            Button(action: onClose) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.bottom, SpeakSpacing.sm)
    }

    private var engineBadge: some View {
        Text(entry.engineId)
            .font(.caption2)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.speakSurface)
            .cornerRadius(4)
            .foregroundStyle(.secondary)
    }

    private var expandedMetadata: some View {
        VStack(alignment: .leading, spacing: SpeakSpacing.xs) {
            if entry.duration > 0 {
                HStack {
                    Text("Duration:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(formatDuration(entry.duration))
                        .font(.speakMonoCaption)
                }
            }

            if entry.stopToPasteSeconds > 0 {
                HStack {
                    Text("Latency:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(String(format: "%.2fs", entry.stopToPasteSeconds))
                        .font(.speakMonoCaption)
                }
            }

            if entry.cleanupSeconds > 0 {
                HStack {
                    Text("Cleanup time:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(String(format: "%.2fs", entry.cleanupSeconds))
                        .font(.speakMonoCaption)
                }
            }
        }
    }

    private var expandedActions: some View {
        HStack(spacing: SpeakSpacing.sm) {
            Button(action: onCopyRaw) {
                Label("Copy Raw", systemImage: "doc.on.doc")
                    .font(.caption)
            }
            .buttonStyle(.bordered)

            if entry.cleanedText != nil {
                Button(action: onCopyClean) {
                    Label("Copy Cleaned", systemImage: "doc.on.doc")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
            }

            Button(action: onExport) {
                Label("Export", systemImage: "arrow.up.doc")
                    .font(.caption)
            }
            .buttonStyle(.bordered)

            Spacer()

            Button(
                action: {},
                label: {
                    Label("Delete", systemImage: "trash")
                        .font(.caption)
                }
            )
            .buttonStyle(.bordered)
            .disabled(true)
            .help("Delete action not yet implemented")

            Button(
                action: {},
                label: {
                    Label("Retry", systemImage: "arrow.clockwise")
                        .font(.caption)
                }
            )
            .buttonStyle(.bordered)
            .disabled(true)
            .help("Retry not yet implemented (v1+)")
        }
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds) / 60
        let secs = Int(seconds) % 60

        if minutes > 0 {
            return "\(minutes)m \(secs)s"
        }

        return "\(secs)s"
    }
}

// MARK: - Preview

#if DEBUG
/// "Empty state" preview — passes (zero rows skip the XOJIT diffRows crash).
/// Verifies: search bar, filters, "No dictations yet" placeholder, footer buttons.
#Preview("Empty state") {
    HistoryView(viewModel: HistoryViewModel(store: PreviewHistoryStore(empty: true)))
}

/// "With entries" preview — KNOWN CRASH under XOJIT on macOS 26 / Xcode 26.5.
/// Root cause: `OutlineListCoordinator.diffRows` assertion in NSOutlineView's
/// row-height estimation. This is preview-only; the real History window
/// (verified via --debug-open history) renders correctly.
/// Surfaced to orchestrator — do NOT degrade production List to fix a preview defect. [decision]
#Preview("With entries") {
    HistoryView(viewModel: HistoryViewModel(store: PreviewHistoryStore(empty: false)))
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
        let now = Date()
        let oneHourAgo = now.addingTimeInterval(-3600)
        let oneDayAgo = now.addingTimeInterval(-86400)

        return [
            HistoryEntry(
                rawText: "speaking into the api document generator code with keyboard shortcuts context",
                cleanedText: "Speaking into the API document generator code with keyboard shortcuts context.",
                createdAt: now,
                engineId: "apple-speech-en-US+foundation-models",
                duration: 5.2,
                stopToPasteSeconds: 1.5,
                cleanupSeconds: 0.8
            ),
            HistoryEntry(
                rawText: "raw only no cleanup applied to this one",
                cleanedText: nil,
                createdAt: oneHourAgo,
                engineId: "apple-speech-en-US",
                duration: 3.8,
                stopToPasteSeconds: 0.5,
                cleanupSeconds: 0
            ),
            HistoryEntry(
                rawText: "make sure the tests pass before pushing",
                cleanedText: "Make sure the tests pass before pushing.",
                createdAt: oneDayAgo,
                engineId: "apple-speech-en-US+foundation-models",
                duration: 4.1,
                stopToPasteSeconds: 1.8,
                cleanupSeconds: 0.9
            )
        ]
    }

    func search(_ substring: String) throws -> [HistoryEntry] { [] }
    func clear() throws {}
    func export() throws -> String { "[]" }
}
#endif
