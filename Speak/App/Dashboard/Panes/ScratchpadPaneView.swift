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

    /// Brief "copied" confirmation on the Copy button — the swap reads a real
    /// signal (the write happened), so it earns its animation.
    @State private var didCopy = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TextEditor(text: $text)
                .font(.speakMonoFace(.base))
                .foregroundStyle(Color.speakBone)
                .scrollContentBackground(.hidden)
                .padding(SpeakSpacing.sm)
                // The pad is a data well — recessed canvas tone + hairline,
                // the same `speakInset` treatment code and JSON get.
                .speakInset(cornerRadius: 10)
                .overlay(alignment: .topLeading) {
                    if text.isEmpty {
                        Text("Type or drop text here — saved on this Mac only.")
                            .font(.speakBody(.base))
                            .foregroundStyle(Color.speakMica)
                            .padding(SpeakSpacing.md)
                            .allowsHitTesting(false)
                    }
                }
                .padding(.top, SpeakSpacing.sm)
                .padding(.horizontal, SpeakSpacing.lg)

            footer
        }
    }

    private var footer: some View {
        HStack(spacing: SpeakSpacing.md) {
            Text("\(wordCount) \(wordCount == 1 ? "word" : "words")")
                .font(.speakMonoFace(.caption))
                .foregroundStyle(Color.speakMica)
            Spacer()
            Button {
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setString(text, forType: .string)
                didCopy = true
                Task {
                    try? await Task.sleep(nanoseconds: 1_500_000_000)
                    didCopy = false
                }
            } label: {
                Label(didCopy ? "Copied" : "Copy", systemImage: didCopy ? "checkmark" : "doc.on.doc")
                    .font(.speakBody(.caption, semibold: true))
                    .foregroundStyle(didCopy ? Color.speakDelivered : Color.speakBone)
            }
            .buttonStyle(.bordered)
            .disabled(text.isEmpty)
            Button("Clear", role: .destructive) { text = "" }
                .font(.speakBody(.caption, semibold: true))
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
