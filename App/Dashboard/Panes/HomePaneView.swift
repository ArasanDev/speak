// App/Dashboard/Panes/HomePaneView.swift
//
// The Home pane — the daily-open landing surface. Per the verified Wispr layout
// (research/wispr-flow-ui-verified.md), Home IS the day-grouped dictation feed with a
// stats rail on the right — NOT a status page (History is the deeper searchable archive).
//
// Layout:
//   [ personalized greeting + TODAY/YESTERDAY feed ]   [ stats rail: words/avg/streak ]
//
// Reads `SettingsStore` reactively (cleanup status) and fetches history off-main via
// `.task`. Content is Monaco; chrome/labels use the system font.

import SpeakCore
import SwiftUI

// MARK: - HomePaneView

struct HomePaneView: View {
    let context: DashboardContext

    let settings: SettingsStore
    @State private var entries: [HistoryEntry] = []
    @State private var loaded = false

    init(context: DashboardContext) {
        self.context = context
        self.settings = context.settingsStore
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            greeting
            Divider()
            HStack(alignment: .top, spacing: 0) {
                feedColumn
                Divider()
                statsRail
                    // [decision: 260pt rail — fits the stat card + status without crowding the feed]
                    .frame(width: 260)
            }
        }
        .task { await loadEntries() }
    }

    // MARK: - Greeting (spans the full width at the top, Wispr-style)

    private var greeting: some View {
        HStack(spacing: SpeakSpacing.sm) {
            Text("Hey \(firstName), get back into the flow with")
                .font(.speakMonoTitle)
            KeyCapView(label: "fn", isAccented: true)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, SpeakSpacing.lg)
        .padding(.vertical, SpeakSpacing.md)
    }

    // MARK: - Feed column (day-grouped history)

    private var feedColumn: some View {
        Group {
            if loaded && entries.isEmpty {
                emptyFeed
            } else {
                feedList
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var feedList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: SpeakSpacing.lg) {
                ForEach(groupedEntries, id: \.title) { group in
                    VStack(alignment: .leading, spacing: SpeakSpacing.sm) {
                        Text(group.title)
                            .font(.speakMonoCaption)
                            .foregroundStyle(.secondary)
                        ForEach(group.entries) { entry in
                            FeedRow(entry: entry)
                        }
                    }
                }
            }
            .padding(.horizontal, SpeakSpacing.lg)
            .padding(.bottom, SpeakSpacing.lg)
        }
    }

    private var emptyFeed: some View {
        PanePlaceholder(
            systemImage: "waveform",
            message: "No dictations yet. Double-tap fn anywhere and start talking —\n"
                + "your words land here, neat-written."
        )
    }

    // MARK: - Stats rail

    private var statsRail: some View {
        let stats = InsightsStats(entries: entries, now: Date(), calendar: .current)
        return ScrollView {
            VStack(alignment: .leading, spacing: SpeakSpacing.md) {
                statRow(value: "\(stats.totalWords)", label: "total words")
                statRow(value: "\(stats.wordsPerMinute)", label: "words / min")
                statRow(value: "\(stats.averageWordsPerDictation)", label: "avg words / session")
                statRow(value: "\(stats.currentStreakDays)", label: "day streak")
                Divider().padding(.vertical, SpeakSpacing.xs)
                cleanupStatus
            }
            .padding(SpeakSpacing.lg)
        }
    }

    private func statRow(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: SpeakSpacing.xs) {
            Text(value)
                .font(.speakMonoStat)
                .foregroundStyle(Color.speakAccent)
            Text(label)
                .font(.speakMonoCaption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var cleanupStatus: some View {
        HStack(spacing: SpeakSpacing.sm) {
            Image(systemName: settings.cleanupEnabled ? "wand.and.stars" : "text.alignleft")
                .foregroundStyle(settings.cleanupEnabled ? Color.speakAccent : Color.secondary)
            Text(settings.cleanupEnabled ? "AI neat-writing on" : "Raw transcript mode")
                .font(.speakMonoCaption)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
    }

    // MARK: - Data

    /// The current user's first name for the greeting; falls back to "there".
    private var firstName: String {
        let full = NSFullUserName().split(separator: " ").first.map(String.init) ?? ""
        return full.isEmpty ? "there" : full
    }

    private func loadEntries() async {
        do {
            // [decision: 200 recent entries — plenty for the Home feed + stats rail at
            //  negligible SQLite cost; the full archive lives in the History pane.]
            entries = try await context.historyStore.recent(limit: 200)
        } catch {
            entries = []
        }
        loaded = true
    }

    /// Groups entries into day buckets labelled TODAY / YESTERDAY / a date, newest first.
    private var groupedEntries: [DayGroup] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let buckets = Dictionary(grouping: entries) { calendar.startOfDay(for: $0.createdAt) }
        return buckets.keys.sorted(by: >).map { day in
            DayGroup(day: day, title: label(for: day, today: today, calendar: calendar),
                     entries: (buckets[day] ?? []).sorted { $0.createdAt > $1.createdAt })
        }
    }

    private func label(for day: Date, today: Date, calendar: Calendar) -> String {
        if day == today { return "TODAY" }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: today), day == yesterday {
            return "YESTERDAY"
        }
        return day.formatted(.dateTime.weekday(.wide).month().day()).uppercased()
    }
}

// MARK: - DayGroup

private struct DayGroup {
    let day: Date
    let title: String
    let entries: [HistoryEntry]
}

// MARK: - FeedRow

/// A single dictation row: timestamp on the left, full neat-written text on the right.
private struct FeedRow: View {
    let entry: HistoryEntry

    var body: some View {
        HStack(alignment: .top, spacing: SpeakSpacing.md) {
            Text(entry.createdAt, format: .dateTime.hour().minute())
                // [decision: 72pt timestamp gutter — aligns the text column like Wispr's feed]
                .frame(width: 72, alignment: .leading)
                .font(.speakMonoCaption)
                .foregroundStyle(.secondary)
            Text(entry.cleanedText ?? entry.rawText)
                .font(.speakMonoBody)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, SpeakSpacing.xs)
    }
}

// MARK: - Preview

#if DEBUG
#Preview("Home — empty history") {
    HomePaneView(context: DashboardContext(
        settingsStore: SettingsStore(),
        historyStore: PreviewNullHistoryStore(),
        hotkeyCombo: ["Fn", "Fn"]
    ))
    .frame(width: 820, height: 560)
}
#endif
