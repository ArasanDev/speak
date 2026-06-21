// App/Dashboard/Panes/HomePaneView.swift
//
// The Home pane — the daily-open landing surface (acceleration-plan.md Wave A).
// Shows the dictation hotkey as a keycap combo, the live cleanup status, and the
// three most-recent dictations (Wave A.2 enrichment).
//
// Reads `SettingsStore` reactively via `@ObservedObject` so the cleanup status
// reflects changes made in the Style pane without a refresh.
//
// Recent entries are fetched off-main via `.task` (same pattern as HistoryViewModel)
// and stored in `@State` — no extra ObservableObject needed for a read-only display.

import SwiftUI
import SpeakCore

// MARK: - HomePaneView

struct HomePaneView: View {
    let context: DashboardContext

    @ObservedObject private var settings: SettingsStore

    // [decision: 3 recent entries — enough for a quick "what did I just say" glance
    // without making the pane feel like a history window]
    @State private var recentEntries: [HistoryEntry] = []

    init(context: DashboardContext) {
        self.context = context
        self.settings = context.settingsStore
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PaneHeader(title: "speak", subtitle: "Local-first voice dictation, neat-written on-device.")

            ScrollView {
                VStack(alignment: .leading, spacing: SpeakSpacing.lg) {
                    hotkeyCard
                    statusCard
                    recentSection
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, SpeakSpacing.lg)
                .padding(.bottom, SpeakSpacing.lg)
            }
        }
        .task {
            await loadRecent()
        }
    }

    // MARK: - Hotkey card

    private var hotkeyCard: some View {
        VStack(alignment: .leading, spacing: SpeakSpacing.sm) {
            Text("Start dictating")
                .font(.speakMonoBody)
            HStack(spacing: SpeakSpacing.sm) {
                KeyComboView(keys: context.hotkeyCombo)
                Text("to talk — text is neat-written and pasted at your cursor.")
                    .font(.speakMonoCaption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(SpeakSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.speakSurface))
    }

    // MARK: - Status card

    private var statusCard: some View {
        HStack(spacing: SpeakSpacing.md) {
            Image(systemName: settings.cleanupEnabled ? "wand.and.stars" : "text.alignleft")
                .font(.system(size: 22))
                .foregroundStyle(settings.cleanupEnabled ? Color.speakAccent : Color.secondary)
            VStack(alignment: .leading, spacing: SpeakSpacing.xs) {
                Text(settings.cleanupEnabled ? "AI neat-writing is on" : "Raw transcript mode")
                    .font(.speakMonoBody)
                Text(settings.cleanupEnabled
                     ? "Foundation Models cleans your dictation on-device before pasting."
                     : "Text is pasted exactly as transcribed, with no AI pass.")
                    .font(.speakMonoCaption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(SpeakSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.speakSurface))
    }

    // MARK: - Recent dictations

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: SpeakSpacing.sm) {
            Text("Recent")
                .font(.speakMonoBody)

            if recentEntries.isEmpty {
                Text("No dictations yet — try your first one.")
                    .font(.speakMonoCaption)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, SpeakSpacing.xs)
            } else {
                VStack(spacing: SpeakSpacing.xs) {
                    ForEach(recentEntries) { entry in
                        RecentEntryRow(entry: entry)
                    }
                }
            }
        }
    }

    // MARK: - Async fetch

    private func loadRecent() async {
        do {
            // [decision: fetch 3 — matches the "Recent" section's display limit]
            recentEntries = try await context.historyStore.recent(limit: 3)
        } catch {
            recentEntries = []
        }
    }
}

// MARK: - RecentEntryRow

/// A compact row showing a truncated preview of a single dictation entry.
private struct RecentEntryRow: View {
    let entry: HistoryEntry

    // [decision: 2 lines of text — enough to recognise the dictation without taking
    // vertical space away from the rest of the Home pane]
    private static let lineLimit = 2

    var body: some View {
        HStack(alignment: .top, spacing: SpeakSpacing.sm) {
            VStack(alignment: .leading, spacing: SpeakSpacing.xs) {
                Text(entry.cleanedText ?? entry.rawText)
                    .font(.speakMonoCaption)
                    .lineLimit(Self.lineLimit)
                    .truncationMode(.tail)
                Text(entry.createdAt, format: .dateTime.month().day().hour().minute())
                    .font(.speakMonoCaption)
                    .foregroundStyle(.tertiary)
            }
            Spacer(minLength: 0)
        }
        .padding(SpeakSpacing.sm)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.speakSurface))
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
    .frame(width: 360, height: 520)
}
#endif
