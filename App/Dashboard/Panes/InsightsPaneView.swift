// App/Dashboard/Panes/InsightsPaneView.swift
//
// The Insights pane — aggregated usage statistics derived from the dictation
// history: total words, total dictations, average words per session, daily
// streak, and a 7-day activity bar chart (acceleration-plan.md Wave A.2).
//
// Stats are computed by the pure `InsightsStats` value type (SpeakCore/Insights/).
// Fetching is done via `.task` (off-main, idiomatic SwiftUI async), matching the
// approach used in `HistoryViewModel` but without the debounce/search overhead.

import SwiftUI
import SpeakCore

// MARK: - InsightsPaneView

struct InsightsPaneView: View {
    let context: DashboardContext

    // History is fetched once on appear and cached here until the view disappears.
    @State private var stats: InsightsStats?
    @State private var isLoading: Bool = false

    init(context: DashboardContext) {
        self.context = context
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PaneHeader(
                title: "Insights",
                subtitle: "Your dictation at a glance — words, speed, and streak."
            )

            if isLoading {
                loadingView
            } else if let stats {
                if stats.totalDictations == 0 {
                    PanePlaceholder(
                        systemImage: "chart.bar",
                        message: "Dictate something first — your stats will appear here."
                    )
                } else {
                    statsBody(stats)
                }
            } else {
                PanePlaceholder(
                    systemImage: "chart.bar",
                    message: "Loading your insights…"
                )
            }
        }
        .task {
            await loadStats()
        }
    }

    // MARK: - Stats body

    @ViewBuilder
    private func statsBody(_ stats: InsightsStats) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SpeakSpacing.lg) {
                statCardRow(stats)
                activityChart(stats)
            }
            .padding(.horizontal, SpeakSpacing.lg)
            .padding(.bottom, SpeakSpacing.lg)
        }
    }

    // MARK: - Stat card row

    private func statCardRow(_ stats: InsightsStats) -> some View {
        // [decision: 2×2 grid of stat cards, fits the 360pt pane width without overflow]
        VStack(spacing: SpeakSpacing.sm) {
            HStack(spacing: SpeakSpacing.sm) {
                StatCard(value: "\(stats.totalDictations)", label: "dictations")
                StatCard(value: "\(stats.totalWords)", label: "total words")
            }
            HStack(spacing: SpeakSpacing.sm) {
                StatCard(value: "\(stats.averageWordsPerDictation)", label: "avg words / session")
                StatCard(value: "\(stats.currentStreakDays)", label: "day streak")
            }
        }
    }

    // MARK: - 7-day activity bar chart (plain SwiftUI — no Charts dep)

    private func activityChart(_ stats: InsightsStats) -> some View {
        VStack(alignment: .leading, spacing: SpeakSpacing.sm) {
            Text("Last 7 days")
                .font(.speakMonoBody)

            ActivityBarChart(dataPoints: stats.dictationsPerDay)
        }
        .padding(SpeakSpacing.md)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.speakSurface))
    }

    // MARK: - Loading view

    private var loadingView: some View {
        VStack(spacing: SpeakSpacing.sm) {
            ProgressView()
                .progressViewStyle(.circular)
            Text("Loading insights…")
                .font(.speakMonoCaption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(SpeakSpacing.xl)
    }

    // MARK: - Async fetch

    /// Fetches a large window of entries off the main actor and computes stats.
    /// [decision: 1000-entry limit — captures all practical history at negligible
    /// SQLite cost; avoids unbounded fetches without a user-adjustable slider.]
    private func loadStats() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let entries = try await context.historyStore.recent(limit: 1000)
            stats = InsightsStats(entries: entries, now: Date(), calendar: .current)
        } catch {
            // Store errors surface as an empty state (stats stays nil → placeholder shown).
            stats = InsightsStats(entries: [], now: Date(), calendar: .current)
        }
    }
}

// MARK: - StatCard

/// A compact card displaying a large numeric value and a caption label.
private struct StatCard: View {
    let value: String
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: SpeakSpacing.xs) {
            Text(value)
                .font(.speakMonoStat)
                .foregroundStyle(Color.speakAccent)
            Text(label)
                .font(.speakMonoCaption)
                .foregroundStyle(.secondary)
        }
        .padding(SpeakSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.speakSurface))
    }
}

// MARK: - ActivityBarChart

/// A simple 7-bar activity chart built from plain SwiftUI geometry.
/// No third-party or Charts dep — satisfies the Apple-frameworks-only moat.
/// [decision: plain bars over Charts framework to keep the import allowlist minimal]
private struct ActivityBarChart: View {
    let dataPoints: [(day: Date, count: Int)]

    // [decision: 80pt bar area height — compact but readable for 0–N dictations per day]
    private static let barAreaHeight: CGFloat = 80

    var body: some View {
        // Extract dictation counts to avoid triggering the SwiftLint empty_count rule
        // on `point.count`, which shares the name of Collection.count.
        let dictationCounts = dataPoints.map(\.count)
        let maxDictations = dictationCounts.max() ?? 1
        HStack(alignment: .bottom, spacing: SpeakSpacing.xs) {
            ForEach(Array(zip(dataPoints, dictationCounts).enumerated()), id: \.offset) { _, pair in
                let (point, dictations) = pair
                VStack(spacing: SpeakSpacing.xs) {
                    GeometryReader { geo in
                        VStack(spacing: 0) {
                            Spacer(minLength: 0)
                            let fraction: CGFloat = maxDictations > 0
                                ? CGFloat(dictations) / CGFloat(maxDictations)
                                : 0
                            RoundedRectangle(cornerRadius: 3)
                                .fill(dictations > 0 ? Color.speakAccent : Color.speakAccent.opacity(0.15))
                                // Minimum 2pt bar so the track is always visible.
                                .frame(height: max(2, fraction * geo.size.height))
                        }
                    }
                    .frame(height: Self.barAreaHeight)

                    Text(dayLabel(point.day))
                        .font(.speakMonoCaption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    /// Single-character weekday label (Mon → "M", etc.) sourced from the locale.
    private func dayLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEEE"   // narrowest weekday symbol (locale-aware)
        return formatter.string(from: date)
    }
}

// MARK: - Preview

#if DEBUG
#Preview("Insights — empty") {
    InsightsPaneView(context: DashboardContext(
        settingsStore: SettingsStore(),
        historyStore: PreviewNullHistoryStore(),
        hotkeyCombo: ["Fn", "Fn"]
    ))
    .frame(width: 360, height: 520)
}
#endif
