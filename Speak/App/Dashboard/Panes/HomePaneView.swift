// App/Dashboard/Panes/HomePaneView.swift
//
// The Home pane — the daily-open dashboard surface. Per the locked design spec
// (speak-ui-design-final-2026-06-28.md §Dashboard Home Pane), shows:
// 1. Hotkey Status (top) — green/red indicator + quick link to grant permissions
// 2. [Start Dictation] button (prominent blue CTA)
// 3. Today's Quick Stats (words, sessions, engine badge)
// 4. Recent Dictations (last 5 entries with time, raw/cleaned preview, engine)
//
// Content is Monaco 13pt; chrome/labels use the system font.
// Reads `SettingsStore` reactively (cleanup status) and fetches history via `.task`.

import Foundation
import os
import SpeakCore
import SwiftUI

// MARK: - HomePaneView

struct HomePaneView: View {
    let context: DashboardContext

    @State private var entries: [HistoryEntry] = []
    @State private var loaded = false
    @State private var micPermissionStatus: PermissionState = .notDetermined
    @State private var accPermissionStatus: PermissionState = .notDetermined

    init(context: DashboardContext) {
        self.context = context
    }

    var body: some View {
        let contentView = ScrollView {
            VStack(alignment: .leading, spacing: SpeakSpacing.lg) {
                // Hotkey status
                hotkeyStatusSection
                    .padding(.horizontal, SpeakSpacing.lg)
                    .padding(.vertical, SpeakSpacing.md)

                // Start button (prominent CTA)
                startDictationButton
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, SpeakSpacing.lg)

                Divider()
                    .padding(.vertical, SpeakSpacing.md)

                // Today's stats
                todayStatsSection
                    .padding(.horizontal, SpeakSpacing.lg)

                Divider()
                    .padding(.vertical, SpeakSpacing.md)

                // Recent dictations
                recentDictationsSection
                    .padding(.horizontal, SpeakSpacing.lg)
                    .padding(.bottom, SpeakSpacing.lg)

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .task { await loadInitialData() }
        .onAppear { updatePermissionStatus() }

        // P11-c: Subscribe to completion notifications if publisher is available,
        // so recent dictations refresh if the dashboard is open while dictating.
        if let publisher = context.dictationCompletedPublisher {
            contentView
                .onReceive(publisher) { _ in
                    Task { await loadInitialData() }
                }
        } else {
            contentView
        }
    }

    // MARK: - Hotkey Status (top)

    private var hotkeyStatusSection: some View {
        VStack(alignment: .leading, spacing: SpeakSpacing.sm) {
            let ready = micPermissionStatus == .granted && accPermissionStatus == .granted

            HStack(alignment: .center, spacing: SpeakSpacing.sm) {
                Image(systemName: ready ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundStyle(ready ? Color(nsColor: .systemGreen) : Color(nsColor: .systemRed))
                    .font(.system(size: 16))

                VStack(alignment: .leading, spacing: 2) {
                    Text(ready ? "Ready to dictate" : "Missing permissions")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text(ready
                        ? "Double-tap Fn to start"
                        : "Grant microphone & accessibility access")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)

                if !ready {
                    NavigationLink(destination: { /* Navigate to Settings */ }) {
                        Text("Fix →")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Color(nsColor: .systemBlue))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(SpeakSpacing.md)
            .background(Color.speakSurface)
            .cornerRadius(6)
        }
    }

    // MARK: - [Start Dictation] button

    private var startDictationButton: some View {
        Button(action: { startDictation() }) {
            HStack(spacing: SpeakSpacing.sm) {
                Image(systemName: "mic.fill")
                Text("Start Dictation")
                    .font(.system(size: 13, weight: .semibold))
            }
            .frame(maxWidth: .infinity)
            .frame(height: 40)
            .foregroundStyle(.white)
            .background(Color(nsColor: .systemBlue))
            .cornerRadius(6)
        }
        .buttonStyle(.plain)
    }

    private func startDictation() {
        // [unverified: integration point, pending engine wiring in P11-c phase 3]
        guard let engine = context.speakEngine else { return }
        Task {
            do {
                _ = try await engine.beginDictation()
            } catch {
                os.Logger(subsystem: "speak", category: "dashboard").error("Start dictation failed: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Today's Quick Stats

    private var todayStatsSection: some View {
        VStack(alignment: .leading, spacing: SpeakSpacing.md) {
            Text("Today's Quick Stats")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.primary)

            VStack(alignment: .leading, spacing: SpeakSpacing.sm) {
                let stats = InsightsStats(entries: todayEntries, now: Date(), calendar: .current)

                HStack(spacing: SpeakSpacing.lg) {
                    statCard(value: "\(stats.totalWords)", label: "Words")
                    statCard(value: "\(todayEntries.count)", label: "Sessions")
                    Spacer(minLength: 0)
                }

                if context.settingsStore.cleanupEnabled {
                    HStack(spacing: SpeakSpacing.sm) {
                        Image(systemName: "wand.and.stars")
                            .foregroundStyle(Color.speakAccent)
                            .font(.system(size: 11))
                        Text("Foundation Models")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func statCard(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: SpeakSpacing.xs) {
            Text(value)
                .font(.speakMonoBody)
                .foregroundStyle(Color.speakAccent)
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Recent Dictations (last 5)

    private var recentDictationsSection: some View {
        VStack(alignment: .leading, spacing: SpeakSpacing.md) {
            HStack {
                Text("Recent Dictations")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
                Spacer(minLength: 0)
                // [decision: View All navigation to History pane deferred to P11-c phase 2]
                Text("View All →")
                    .font(.system(size: 11))
                    .foregroundStyle(Color(nsColor: .systemBlue))
            }

            if todayEntries.isEmpty {
                emptyState
            } else {
                VStack(alignment: .leading, spacing: SpeakSpacing.sm) {
                    ForEach(Array(todayEntries.prefix(5)), id: \.id) { entry in
                        RecentEntryRow(entry: entry)
                        if entry.id != todayEntries.prefix(5).last?.id {
                            Divider()
                                .padding(.vertical, SpeakSpacing.xs)
                        }
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .center, spacing: SpeakSpacing.md) {
            Image(systemName: "waveform")
                .font(.system(size: 20))
                .foregroundStyle(.secondary)
            Text("No dictations yet. Double-tap Fn and start talking.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(SpeakSpacing.lg)
    }

    // MARK: - Data loading

    private func loadInitialData() async {
        do {
            let all = try await context.historyStore.recent(limit: 100)
            let calendar = Calendar.current
            let today = calendar.startOfDay(for: Date())
            entries = all.filter { calendar.startOfDay(for: $0.createdAt) == today }
                .sorted { $0.createdAt > $1.createdAt }
        } catch {
            entries = []
        }
        loaded = true
    }

    private func updatePermissionStatus() {
        guard let pm = context.permissionManager else { return }
        micPermissionStatus = pm.status(.microphone)
        accPermissionStatus = pm.status(.accessibility)
    }

    private var todayEntries: [HistoryEntry] {
        entries
    }
}

// MARK: - RecentEntryRow

/// A single recent dictation row: time | raw preview | cleaned preview.
private struct RecentEntryRow: View {
    let entry: HistoryEntry

    var body: some View {
        VStack(alignment: .leading, spacing: SpeakSpacing.xs) {
            HStack(alignment: .center, spacing: SpeakSpacing.sm) {
                Text(entry.createdAt, format: .dateTime.hour().minute())
                    .font(.speakMonoCaption)
                    .foregroundStyle(.secondary)
                    .frame(width: 48, alignment: .leading)

                Text(truncatePreview(entry.rawText, maxChars: 40))
                    .font(.speakMonoCaption)
                    .foregroundStyle(Color(nsColor: .systemBlue))
                    .lineLimit(1)

                Spacer(minLength: 0)
            }

            if let cleaned = entry.cleanedText {
                HStack(alignment: .center, spacing: SpeakSpacing.sm) {
                    Spacer(minLength: 48)

                    Text(truncatePreview(cleaned, maxChars: 40))
                        .font(.speakMonoCaption)
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Spacer(minLength: 0)
                }
            }
        }
        .padding(.vertical, SpeakSpacing.xs)
    }

    private func truncatePreview(_ text: String, maxChars: Int) -> String {
        if text.count > maxChars {
            return String(text.prefix(maxChars - 1)) + "…"
        }
        return text
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

#Preview("Home — with dictations") {
    HomePaneView(context: DashboardContext(
        settingsStore: SettingsStore(),
        historyStore: PreviewNullHistoryStore(),
        hotkeyCombo: ["Fn", "Fn"]
    ))
    .frame(width: 820, height: 560)
}
#endif
