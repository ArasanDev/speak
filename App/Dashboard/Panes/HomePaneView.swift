// App/Dashboard/Panes/HomePaneView.swift
//
// The Home pane — the daily-open landing surface (acceleration-plan.md Wave A).
// Shows the dictation hotkey as a keycap combo, the live cleanup status, and a calm
// "ready" hero. Wave A.2 (builder-app) enriches this with recent dictations + quick stats.
//
// Reads `SettingsStore` reactively via `@ObservedObject` so the cleanup status reflects
// changes made in the Style pane without a refresh.

import SwiftUI
import SpeakCore

// MARK: - HomePaneView

struct HomePaneView: View {
    let context: DashboardContext

    @ObservedObject private var settings: SettingsStore

    init(context: DashboardContext) {
        self.context = context
        self.settings = context.settingsStore
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PaneHeader(title: "speak", subtitle: "Local-first voice dictation, neat-written on-device.")

            VStack(alignment: .leading, spacing: SpeakSpacing.lg) {
                hotkeyCard
                statusCard
                Spacer(minLength: 0)
            }
            .padding(.horizontal, SpeakSpacing.lg)
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
}
