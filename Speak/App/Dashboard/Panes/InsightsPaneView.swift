// App/Dashboard/Panes/InsightsPaneView.swift
//
// The Insights pane — aggregated usage statistics derived from the dictation
// history: total words, total dictations, average words per session, daily
// streak, and a 7-day activity bar chart (acceleration-plan.md Wave A.2).
//
// Stats are computed by the pure `InsightsStats` value type (SpeakCore/Insights/).
// Fetching is done via `.task` (off-main, idiomatic SwiftUI async), matching the
// approach used in `HistoryViewModel` but without the debounce/search overhead.

import SpeakCore
import SwiftUI

// MARK: - InsightsPaneView

struct InsightsPaneView: View {
    let context: DashboardContext

    // History is fetched once on appear and cached here until the view disappears.
    @State private var stats: InsightsStats?
    @State private var latency: LatencyStats?
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
                if let latency {
                    latencySection(latency)
                }
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
                StatCard(value: "\(stats.wordsPerMinute)", label: "words / min")
                StatCard(value: "\(stats.averageWordsPerDictation)", label: "avg words / session")
            }
            HStack(spacing: SpeakSpacing.sm) {
                StatCard(value: "\(stats.currentStreakDays)", label: "day streak")
                Color.clear.frame(maxWidth: .infinity)   // keep the 2-column grid aligned
            }
        }
    }

    // MARK: - Latency section (benchmark.md §7 L_e2e)

    /// Stop→paste latency cards. Thresholds come from benchmark.md §7 — no bare literals.
    private func latencySection(_ latency: LatencyStats) -> some View {
        VStack(alignment: .leading, spacing: SpeakSpacing.sm) {
            Text("Stop → paste latency")
                .font(.speakMonoBody)

            HStack(spacing: SpeakSpacing.sm) {
                LatencyCard(
                    label: "raw median",
                    valueSeconds: latency.rawMedian,
                    budgetSeconds: latencyBudgetRawMedianSeconds,
                    sampleCount: latency.rawSampleCount
                )
                LatencyCard(
                    label: "cleanup median",
                    valueSeconds: latency.cleanupMedian,
                    budgetSeconds: latencyBudgetCleanupMedianSeconds,
                    sampleCount: latency.cleanupSampleCount
                )
            }

            if latency.rawSampleCount > 0 || latency.cleanupSampleCount > 0 {
                HStack(spacing: SpeakSpacing.sm) {
                    if let p95 = latency.rawP95 {
                        LatencyCard(
                            label: "raw p95",
                            valueSeconds: p95,
                            budgetSeconds: latencyBudgetRawMedianSeconds * 2,
                            sampleCount: latency.rawSampleCount
                        )
                    }
                    if let p95 = latency.cleanupP95 {
                        LatencyCard(
                            label: "cleanup p95",
                            valueSeconds: p95,
                            budgetSeconds: latencyBudgetCleanupMedianSeconds * 2,
                            sampleCount: latency.cleanupSampleCount
                        )
                    }
                    // Fill trailing space if only one p95 card is shown.
                    if (latency.rawP95 != nil) != (latency.cleanupP95 != nil) {
                        Color.clear.frame(maxWidth: .infinity)
                    }
                }
            }
        }
        .padding(SpeakSpacing.md)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.speakSurface))
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
            latency = LatencyStats(entries: entries)
        } catch {
            // Store errors surface as an empty state (stats stays nil → placeholder shown).
            stats = InsightsStats(entries: [], now: Date(), calendar: .current)
            latency = LatencyStats(entries: [])
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

// MARK: - LatencyCard

/// A compact latency metric card showing a value in milliseconds with a budget indicator.
///
/// Color semantics (no magic numbers — thresholds from benchmark.md §7 via `budgetSeconds`):
///   • Green (speakStateDone):    value ≤ budget — within target.
///   • Red (speakStateError):     value > budget — over target.
///   • Secondary (neutral):       no data yet (value is nil).
private struct LatencyCard: View {
    let label: String
    /// The measured value in seconds. `nil` when no samples exist yet.
    let valueSeconds: Double?
    /// Budget threshold in seconds (from benchmark.md §7 via a named constant).
    let budgetSeconds: Double
    /// Number of samples this value is derived from.
    let sampleCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: SpeakSpacing.xs) {
            if let valueSeconds {
                let withinBudget = valueSeconds <= budgetSeconds
                Text(formattedMs(valueSeconds))
                    .font(.speakMonoStat)
                    .foregroundStyle(withinBudget ? Color.speakStateDone : Color.speakStateError)
                Text(label)
                    .font(.speakMonoCaption)
                    .foregroundStyle(.secondary)
                Text("n=\(sampleCount)")
                    .font(.speakMonoCaption)
                    .foregroundStyle(.tertiary)
            } else {
                Text("—")
                    .font(.speakMonoStat)
                    .foregroundStyle(.secondary)
                Text(label)
                    .font(.speakMonoCaption)
                    .foregroundStyle(.secondary)
                Text("no data")
                    .font(.speakMonoCaption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(SpeakSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.speakSurface))
    }

    /// Format seconds as milliseconds with one decimal, e.g. "342.1ms".
    private func formattedMs(_ seconds: Double) -> String {
        String(format: "%.0fms", seconds * 1000)
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
