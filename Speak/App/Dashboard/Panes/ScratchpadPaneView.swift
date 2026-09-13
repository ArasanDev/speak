// App/Dashboard/Panes/ScratchpadPaneView.swift
//
// The Scratchpad pane — a free-form local note you can type or review text in,
// serving as a safety buffer when an accessibility paste target is unavailable.
//
// v0: a single persistent pad backed by `@AppStorage` (UserDefaults) so the note
// survives relaunch — no cloud, no account (the local-first moat). Multi-tab notes are a
// later enhancement. The text is SF Mono (data voice); chrome is the SF Pro body scale.

import SpeakCore
import SwiftUI

// MARK: - ScratchpadPaneView

struct ScratchpadPaneView: View {
    let context: DashboardContext

    /// Persisted locally in UserDefaults — the scratchpad is a single on-device note in v0.
    /// Shares `Scratchpad.defaultsKey` with the paste-failure fallback, so failed text
    /// appears here live.
    @AppStorage(Scratchpad.defaultsKey) private var text: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TextEditor(text: $text)
                .font(.speakMonoFace(.base))
                .scrollContentBackground(.hidden)
                .padding(SpeakSpacing.sm)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.speakSurface))
                .overlay(alignment: .topLeading) {
                    if text.isEmpty {
                        Text("Start typing…")
                            .font(.speakBody(.base))
                            .foregroundStyle(.tertiary)
                            .padding(SpeakSpacing.md)
                            .allowsHitTesting(false)
                    }
                }
                .padding(.horizontal, SpeakSpacing.lg)

            footer
        }
    }

    private var footer: some View {
        HStack(spacing: SpeakSpacing.md) {
            Text("\(wordCount) words")
                .font(.speakBody(.caption))
                .foregroundStyle(.secondary)
            Spacer()
            Button("Copy") {
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setString(text, forType: .string)
            }
            .disabled(text.isEmpty)
            Button("Clear", role: .destructive) { text = "" }
                .disabled(text.isEmpty)
        }
        .padding(.horizontal, SpeakSpacing.lg)
        .padding(.vertical, SpeakSpacing.md)
    }

    private var wordCount: Int {
        text.split(whereSeparator: \.isWhitespace).count
    }
}

// MARK: - Preview

#if DEBUG
#Preview("Scratchpad") {
    ScratchpadPaneView(context: DashboardContext(
        settingsStore: SettingsStore(),
        historyStore: PreviewNullHistoryStore(),
        hotkeyCombo: ["Fn", "Fn"]
    ))
    .frame(width: 620, height: 520)
}
#endif
