// App/History/HistoryView.swift
//
// The History pane (P11-c) — a searchable, filterable, expandable list of past
// dictations. Surfaces the store layer (`HistoryStore`, `HistoryStoreTests`) with
// date grouping, engine filtering, side-by-side diff view, and action buttons.
//
// DESIGN (from specs/speak-ui-design-final-2026-06-28.md §History Pane):
//   - **Search bar** + date/engine filters (top, persistent)
//   - **Grouped list**: Today / This Week / Earlier
//   - **Collapsed entry**: time | raw preview | cleaned preview | engine badge
//   - **Expanded view** (click to toggle):
//       - Side-by-side / inline diff via CleanupDiffView
//       - Metadata: duration, stop→paste latency, cleanup time
//       - Actions: [Copy Raw] [Copy Cleaned] [Export] [Retry] [Delete]
//   - **Batch actions** (footer): [Export All] [Clear All — confirmed destructive]
//   - Text uses the FE-1 faces: speakBody chrome, speakMonoFace for data
//     (timestamps, transcripts, stats), Color.speak* tokens only.
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
    @State private var showClearConfirmation = false

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
        .confirmationDialog(
            "Clear all dictation history?",
            isPresented: $showClearConfirmation,
            titleVisibility: .visible
        ) {
            Button("Clear History", role: .destructive) {
                viewModel.clearAll()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently deletes every stored dictation. This can't be undone.")
        }
    }

    // MARK: - Search bar and filters

    private var searchBarAndFilters: some View {
        VStack(spacing: SpeakSpacing.sm) {
            // Search bar — a recessed well so the field reads as a control.
            HStack(spacing: SpeakSpacing.sm) {
                Image(systemName: "magnifyingglass")
                    .font(.speakBody(.base))
                    .foregroundStyle(Color.speakMica)
                    .accessibilityHidden(true)

                TextField("Search dictations", text: $viewModel.searchText)
                    .textFieldStyle(.plain)
                    .font(.speakBody(.base))
                    .foregroundStyle(Color.speakBone)

                if viewModel.isLoading {
                    ProgressView()
                        .controlSize(.small)
                } else if !viewModel.searchText.isEmpty {
                    Button(
                        action: { viewModel.searchText = "" },
                        label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.speakBody(.base))
                                .foregroundStyle(Color.speakMica)
                        }
                    )
                    .buttonStyle(.plain)
                    .help("Clear search")
                }
            }
            .padding(.horizontal, SpeakSpacing.sm + SpeakSpacing.xs)
            .padding(.vertical, SpeakSpacing.sm)
            .speakInset(cornerRadius: 10)
            .padding(.horizontal, SpeakSpacing.md)
            .padding(.top, SpeakSpacing.md)

            // Filters row — labeled menus + a live result count.
            HStack(spacing: SpeakSpacing.sm) {
                Text("Date")
                    .font(.speakBody(.caption))
                    .foregroundStyle(Color.speakMica)
                Picker("Date", selection: $selectedDateFilter) {
                    ForEach(DateFilter.allCases, id: \.self) { filter in
                        Text(filter.label).tag(filter)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .fixedSize()

                Text("Engine")
                    .font(.speakBody(.caption))
                    .foregroundStyle(Color.speakMica)
                    .padding(.leading, SpeakSpacing.xs)
                Picker("Engine", selection: $selectedEngineFilter) {
                    ForEach(availableEngines, id: \.self) { engine in
                        Text(engine == "all" ? "All engines" : engine).tag(engine)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .fixedSize()

                Spacer()

                Text(resultCountLabel)
                    .font(.speakMonoFace(.caption))
                    .foregroundStyle(Color.speakMica)
            }
            .padding(.horizontal, SpeakSpacing.md)
            .padding(.bottom, SpeakSpacing.sm)
        }
    }

    /// Live count of what the list is showing after filters — keeps the
    /// result set legible when a search or filter narrows it.
    private var resultCountLabel: String {
        let count = groupedAndFilteredEntries.reduce(0) { $0 + $1.entries.count }
        return count == 1 ? "1 dictation" : "\(count) dictations"
    }

    // MARK: - Content (grouped list)

    /// Always-mounted List with empty overlay — prevents VStack ↔ List
    /// view-type switch that triggers XOJIT diffRows crash on async reloads. [decision]
    private var content: some View {
        List {
            ForEach(groupedAndFilteredEntries, id: \.id) { group in
                Section(header: sectionHeader(for: group)) {
                    ForEach(group.entries, id: \.id) { entry in
                        historyRowWithExpand(entry: entry)
                    }
                }
            }
        }
        .listStyle(.inset)
        .scrollContentBackground(.hidden)
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

    private func sectionHeader(for group: HistoryGroup) -> some View {
        HStack {
            Text(group.period.label)
                .font(.speakBody(.caption, semibold: true))
                .foregroundStyle(Color.speakMica)
            Spacer()
            Text("\(group.entries.count)")
                .font(.speakMonoFace(.caption))
                .foregroundStyle(Color.speakMica)
        }
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
        HStack(spacing: SpeakSpacing.md) {
            Button(
                action: { viewModel.exportToFile() },
                label: {
                    Text("Export\u{2026}")
                        .font(.speakBody(.caption))
                        .foregroundStyle(Color.speakBone)
                }
            )
            .disabled(viewModel.entries.isEmpty)
            .help("Export all dictations to a JSON file")

            Spacer()

            Text(historySummaryLabel)
                .font(.speakMonoFace(.caption))
                .foregroundStyle(Color.speakMica)

            Button(
                role: .destructive,
                action: { showClearConfirmation = true },
                label: {
                    Text("Clear History")
                        .font(.speakBody(.caption))
                        .foregroundStyle(Color.speakError)
                }
            )
            .disabled(viewModel.entries.isEmpty)
            .help("Permanently delete all stored dictations")
        }
        .padding(SpeakSpacing.md)
    }

    private var historySummaryLabel: String {
        let count = viewModel.entries.count
        return count == 1 ? "1 stored" : "\(count) stored"
    }

    // MARK: - Empty state

    /// Two honest variants: nothing recorded yet, or the current
    /// search/filters match nothing (with a one-tap way out).
    private var isFiltering: Bool {
        !viewModel.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || selectedDateFilter != .allTime
            || selectedEngineFilter != "all"
    }

    private var emptyState: some View {
        VStack(spacing: SpeakSpacing.md) {
            Image(systemName: isFiltering ? "magnifyingglass" : "waveform")
                .font(.system(size: 34))
                .foregroundStyle(Color.speakMica.opacity(0.6))
                .accessibilityHidden(true)

            Text(isFiltering ? "No matches" : "No dictations yet")
                .font(.speakBody(.body, semibold: true))
                .foregroundStyle(Color.speakBone)

            Text(isFiltering
                 ? "Try a different search, or widen the date and engine filters."
                 : "Everything you dictate lands here — searchable, expandable, exportable.")
                .font(.speakBody(.caption))
                .foregroundStyle(Color.speakMica)
                .multilineTextAlignment(.center)

            if isFiltering {
                Button(action: resetFilters) {
                    Text("Clear Search & Filters")
                        .font(.speakBody(.caption, semibold: true))
                }
                .buttonStyle(.bordered)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(SpeakSpacing.xl)
    }

    private func resetFilters() {
        viewModel.searchText = ""
        selectedDateFilter = .allTime
        selectedEngineFilter = "all"
    }

    // MARK: - Helpers

    private func openExpanded(_ id: UUID) {
        withAnimation(.easeInOut(duration: SpeakMotion.microDuration)) {
            expandedEntryId = id
        }
    }

    private func closeExpanded() {
        withAnimation(.easeInOut(duration: SpeakMotion.microDuration)) {
            expandedEntryId = nil
        }
    }

    private func copyToClipboard(_ text: String) {
        guard !text.isEmpty else { return }
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

    /// Title-case labels — the FE-1 type charter allows no ALL-CAPS labels
    /// except two-letter status tags (spec §3).
    var label: String {
        switch self {
        case .today:
            return "Today"

        case .thisWeek:
            return "This Week"

        case .earlier:
            return "Earlier"
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

/// One collapsed history row: timestamp + engine badge on the meta line, the
/// raw transcript as the headline, and the AI-cleaned text as a secondary line.
/// The whole row is the expand affordance; hover gives a soft highlight.
private struct CollapsedHistoryEntryView: View {
    let entry: HistoryEntry
    let onTap: () -> Void

    @State private var isHovered = false

    var body: some View {
        // The whole row is the expand affordance — a real Button so keyboard
        // and VoiceOver can activate it, styled plain to keep the custom look.
        Button(action: onTap) {
            HStack(alignment: .top, spacing: SpeakSpacing.sm) {
                Image(systemName: "chevron.right")
                    .font(.speakBody(.caption, semibold: true))
                    .foregroundStyle(Color.speakMica)
                    .frame(width: 12)
                    // Optical alignment with the first line of text.
                    .padding(.top, SpeakSpacing.xs)

                VStack(alignment: .leading, spacing: SpeakSpacing.xs) {
                    HStack(spacing: SpeakSpacing.sm) {
                        Text(entry.createdAt, style: .time)
                            .font(.speakMonoFace(.caption))
                            .foregroundStyle(Color.speakMica)
                        Spacer(minLength: 0)
                        if !entry.engineId.isEmpty {
                            engineBadge(entry.engineId)
                        }
                    }

                    Text(primaryText)
                        .font(.speakBody(.base))
                        .foregroundStyle(primaryIsPlaceholder ? Color.speakMica : Color.speakBone)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    if let cleaned = entry.cleanedText, cleaned != entry.rawText, !cleaned.isEmpty {
                        HStack(spacing: SpeakSpacing.xs) {
                            Image(systemName: "wand.and.stars")
                                .font(.speakBody(.caption))
                            Text(cleaned)
                                .font(.speakBody(.caption))
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                        .foregroundStyle(Color.speakMica)
                    }
                }
            }
            .padding(.horizontal, SpeakSpacing.sm)
            .padding(.vertical, SpeakSpacing.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.speakMica.opacity(isHovered ? 0.08 : 0.0))
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: SpeakMotion.microDuration)) {
                isHovered = hovering
            }
        }
        .help("Click to expand")
    }

    /// Headline text: raw transcript, cleaned fallback, or an honest
    /// placeholder when the row carries neither.
    private var primaryText: String {
        if !entry.rawText.isEmpty { return entry.rawText }
        if let cleaned = entry.cleanedText, !cleaned.isEmpty { return cleaned }
        return "Empty transcription"
    }

    private var primaryIsPlaceholder: Bool {
        entry.rawText.isEmpty && (entry.cleanedText?.isEmpty ?? true)
    }

    private func engineBadge(_ engineId: String) -> some View {
        Text(engineId)
            .font(.speakMonoFace(.caption))
            .foregroundStyle(Color.speakMica)
            .padding(.horizontal, SpeakSpacing.sm)
            .padding(.vertical, SpeakSpacing.xs)
            .speakInset(cornerRadius: 6)
    }
}

// MARK: - Expanded entry view

/// The expanded row: collapse header, the raw→cleaned diff, mono metadata,
/// and the action row. Delete/Retry stay visible but disabled — the store
/// has no per-entry delete seam and no retry pipeline yet (see file header).
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
                // Hairline so the diff's own surface reads on the card.
                .overlay(
                    RoundedRectangle(cornerRadius: SpeakSpacing.sm, style: .continuous)
                        .stroke(Color.speakCardBorder, lineWidth: 1)
                )
                .frame(maxHeight: 300)
            expandedMetadata
            expandedActions
        }
        .padding(SpeakSpacing.md)
        .speakCard()
    }

    private var expandedHeader: some View {
        HStack(spacing: SpeakSpacing.sm) {
            Button(action: onClose) {
                HStack(spacing: SpeakSpacing.sm) {
                    Image(systemName: "chevron.down")
                        .font(.speakBody(.caption, semibold: true))
                        .foregroundStyle(Color.speakMica)
                        .frame(width: 12)
                    Text(entry.createdAt, format: .dateTime.month(.abbreviated).day().hour().minute())
                        .font(.speakMonoFace(.caption))
                        .foregroundStyle(Color.speakMica)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Collapse")

            if !entry.engineId.isEmpty {
                engineBadge
            }

            Spacer()

            Button(action: onClose) {
                Image(systemName: "xmark.circle.fill")
                    .font(.speakBody(.body))
                    .foregroundStyle(Color.speakMica)
            }
            .buttonStyle(.plain)
            .help("Close")
        }
    }

    private var engineBadge: some View {
        Text(entry.engineId)
            .font(.speakMonoFace(.caption))
            .foregroundStyle(Color.speakMica)
            .padding(.horizontal, SpeakSpacing.sm)
            .padding(.vertical, SpeakSpacing.xs)
            .speakInset(cornerRadius: 6)
    }

    @ViewBuilder
    private var expandedMetadata: some View {
        let hasMetrics = entry.duration > 0 || entry.stopToPasteSeconds > 0 || entry.cleanupSeconds > 0
        if hasMetrics {
            HStack(spacing: SpeakSpacing.lg) {
                if entry.duration > 0 {
                    metadataMetric(label: "Duration", value: formatDuration(entry.duration))
                }
                if entry.stopToPasteSeconds > 0 {
                    metadataMetric(label: "Stop→Paste", value: String(format: "%.2fs", entry.stopToPasteSeconds))
                }
                if entry.cleanupSeconds > 0 {
                    metadataMetric(label: "Cleanup", value: String(format: "%.2fs", entry.cleanupSeconds))
                }
                Spacer(minLength: 0)
            }
        }
    }

    private func metadataMetric(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: SpeakSpacing.xs) {
            Text(label)
                .font(.speakBody(.caption))
                .foregroundStyle(Color.speakMica)
            Text(value)
                .font(.speakMonoFace(.base))
                .foregroundStyle(Color.speakBone)
        }
    }

    private var expandedActions: some View {
        HStack(spacing: SpeakSpacing.sm) {
            Button(action: onCopyRaw) {
                Label("Copy Raw", systemImage: "doc.on.doc")
                    .font(.speakBody(.caption))
            }
            .buttonStyle(.bordered)
            .disabled(entry.rawText.isEmpty)

            if entry.cleanedText != nil {
                Button(action: onCopyClean) {
                    Label("Copy Cleaned", systemImage: "doc.on.doc")
                        .font(.speakBody(.caption))
                }
                .buttonStyle(.bordered)
            }

            Button(action: onExport) {
                Label("Export", systemImage: "arrow.up.doc")
                    .font(.speakBody(.caption))
            }
            .buttonStyle(.bordered)

            Spacer()

            Button(
                action: {},
                label: {
                    Label("Delete", systemImage: "trash")
                        .font(.speakBody(.caption))
                }
            )
            .buttonStyle(.bordered)
            .disabled(true)
            .help("Delete action not yet implemented")

            Button(
                action: {},
                label: {
                    Label("Retry", systemImage: "arrow.clockwise")
                        .font(.speakBody(.caption))
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
