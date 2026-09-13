// App/Dashboard/Panes/InsightsPaneView.swift
//
// The Insights pane — aggregated usage statistics derived from the dictation
// history: total words, total dictations, average words per session, daily
// streak, stop→paste latency, and a 7-day activity bar chart
// (acceleration-plan.md Wave A.2).
//
// This is a DATA surface: numerals are system-rounded speakBone at display
// scale, unit labels are speakMica, and color is reserved for semantics —
// `ok` for within-budget latency, `warning` for degraded. Stat numerals are
// never tinted.
//
// Stats are computed by the pure `InsightsStats`/`LatencyStats` value types
// (SpeakCore/Insights/). Fetching is done via `.task` (off-main, idiomatic
// SwiftUI async), matching the approach used in `HistoryViewModel` but without
// the debounce/search overhead.

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
            if let stats, stats.totalDictations > 0 {
                statsBody(stats)
            } else if stats != nil, !isLoading {
                // Loaded successfully but the store is empty — real empty state.
                emptyState
            } else {
                loadingView
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task {
            await loadStats()
        }
    }

    // MARK: - Stats body

    @ViewBuilder
    private func statsBody(_ stats: InsightsStats) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SpeakSpacing.lg) {
                VStack(alignment: .leading, spacing: SpeakSpacing.sm) {
                    sectionHeader("Overview")
                    statCardGrid(stats)
                }
                if let latency {
                    latencySection(latency)
                }
                activityChart(stats)
            }
            .padding(.top, SpeakSpacing.sm)
            .padding(.horizontal, SpeakSpacing.lg)
            .padding(.bottom, SpeakSpacing.lg)
        }
    }

    // MARK: - Section header chrome

    /// Dashboard chrome per the design contract: 16pt semibold bone on canvas.
    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(Color.speakBone)
    }

    // MARK: - Stat card grid

    private func statCardGrid(_ stats: InsightsStats) -> some View {
        // [decision: 2-column grid, fits the 360pt pane width without overflow;
        //  the streak card spans both columns so the grid never dead-ends.]
        let columns = [
            GridItem(.flexible(), spacing: SpeakSpacing.sm),
            GridItem(.flexible(), spacing: SpeakSpacing.sm)
        ]
        return LazyVGrid(columns: columns, spacing: SpeakSpacing.sm) {
            StatCard(value: "\(stats.totalDictations)", label: "dictations", systemImage: "waveform")
            StatCard(value: "\(stats.totalWords)", label: "total words", systemImage: "text.word.spacing")
            StatCard(value: "\(stats.wordsPerMinute)", label: "words / min", systemImage: "speedometer")
            StatCard(value: "\(stats.averageWordsPerDictation)", label: "avg words / session", systemImage: "chart.line.uptrend.xyaxis")
            StatCard(
                value: "\(stats.currentStreakDays)",
                label: "day streak",
                systemImage: "flame"
            )
            .gridCellColumns(2)
        }
    }

    // MARK: - Latency section (benchmark.md §7 L_e2e)

    /// Stop→paste latency cards. Thresholds come from benchmark.md §7 — no bare literals.
    private func latencySection(_ latency: LatencyStats) -> some View {
        VStack(alignment: .leading, spacing: SpeakSpacing.sm) {
            sectionHeader("Stop → Paste Latency")
            Text("Median time from stopping dictation to text landing at the cursor.")
                .font(.speakBody(.caption))
                .foregroundStyle(Color.speakMica)

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
    }

    // MARK: - 7-day activity bar chart (plain SwiftUI — no Charts dep)

    private func activityChart(_ stats: InsightsStats) -> some View {
        VStack(alignment: .leading, spacing: SpeakSpacing.sm) {
            sectionHeader("Last 7 Days")

            ActivityBarChart(dataPoints: stats.dictationsPerDay)
        }
        .padding(SpeakSpacing.md)
        .speakCard()
    }

    // MARK: - Loading view

    private var loadingView: some View {
        VStack(spacing: SpeakSpacing.sm) {
            ProgressView()
                .progressViewStyle(.circular)
            Text("Loading insights…")
                .font(.speakBody(.caption))
                .foregroundStyle(Color.speakMica)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(SpeakSpacing.xl)
    }

    // MARK: - Empty state

    /// Nothing recorded yet — icon + line + an honest hint, not a blank pane.
    private var emptyState: some View {
        VStack(spacing: SpeakSpacing.md) {
            Image(systemName: "chart.bar")
                .font(.system(size: 34))
                .foregroundStyle(Color.speakMica.opacity(0.6))
                .accessibilityHidden(true)
            Text("No insights yet")
                .font(.speakBody(.body, semibold: true))
                .foregroundStyle(Color.speakBone)
            Text("Dictate once — words, pace, streaks, and latency appear here.")
                .font(.speakBody(.caption))
                .foregroundStyle(Color.speakMica)
                .multilineTextAlignment(.center)
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
            // Store errors surface as the empty state — honest, not a crash.
            stats = InsightsStats(entries: [], now: Date(), calendar: .current)
            latency = LatencyStats(entries: [])
        }
    }
}

// MARK: - StatCard

/// A compact card displaying a large numeric value, a mica icon, and a
/// caption label. Same visual recipe as Home's Activity Overview cards so the
/// desk reads as one system.
private struct StatCard: View {
    let value: String
    let label: String
    let systemImage: String

    var body: some View {
        VStack(alignment: .leading, spacing: SpeakSpacing.sm + SpeakSpacing.xs) {
            Image(systemName: systemImage)
                .font(.speakBody(.base, semibold: true))
                .foregroundStyle(Color.speakMica)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: SpeakSpacing.xs) {
                Text(value)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.speakBone)
                Text(label)
                    .font(.speakBody(.caption))
                    .foregroundStyle(Color.speakMica)
            }
        }
        .padding(SpeakSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .speakCard()
    }
}

// MARK: - LatencyCard

/// A compact latency metric card showing a value in milliseconds with a
/// budget indicator.
///
/// Color semantics (no magic numbers — thresholds from benchmark.md §7 via `budgetSeconds`):
///   • `speakOK` (healthy):     value ≤ budget — within target.
///   • `speakWarning` (degraded): value > budget — over target, actionable but
///     not a failure (dictation still landed).
///   • `speakMica` (neutral):   no data yet (value is nil).
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
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(withinBudget ? Color.speakOK : Color.speakWarning)
                Text(label)
                    .font(.speakBody(.caption))
                    .foregroundStyle(Color.speakMica)
                Text("n=\(sampleCount) · target ≤ \(formattedBudget)")
                    .font(.speakMonoFace(.caption))
                    .foregroundStyle(Color.speakMica)
            } else {
                Text("—")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.speakMica)
                Text(label)
                    .font(.speakBody(.caption))
                    .foregroundStyle(Color.speakMica)
                Text("no data")
                    .font(.speakBody(.caption))
                    .foregroundStyle(Color.speakMica)
            }
        }
        .padding(SpeakSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .speakCard()
    }

    /// Format seconds as whole milliseconds, e.g. "342ms".
    private func formattedMs(_ seconds: Double) -> String {
        String(format: "%.0fms", seconds * 1000)
    }

    /// The budget rendered in its native unit, e.g. "1.0s" / "4.0s".
    private var formattedBudget: String {
        String(format: "%.1fs", budgetSeconds)
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
                let isToday = Calendar.current.isDateInToday(point.day)
                VStack(spacing: SpeakSpacing.xs) {
                    // Count above the bar — data, so mono. Always rendered at
                    // zero opacity when empty so every column stays aligned.
                    Text("\(dictations)")
                        .font(.speakMonoFace(.caption))
                        .foregroundStyle(Color.speakMica)
                        .opacity(dictations > 0 ? 1 : 0)

                    GeometryReader { geo in
                        VStack(spacing: 0) {
                            Spacer(minLength: 0)
                            let fraction: CGFloat = maxDictations > 0
                                ? CGFloat(dictations) / CGFloat(maxDictations)
                                : 0
                            RoundedRectangle(cornerRadius: 3)
                                .fill(dictations > 0 ? Color.speakUIAccent : Color.speakUIAccent.opacity(0.15))
                                // Minimum 2pt bar so the track is always visible.
                                .frame(height: max(2, fraction * geo.size.height))
                        }
                    }
                    .frame(height: Self.barAreaHeight)

                    Text(dayLabel(point.day))
                        .font(.speakBody(.caption, semibold: isToday))
                        .foregroundStyle(isToday ? Color.speakBone : Color.speakMica)
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(dayLabel(point.day)): \(dictations) dictations")
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
