// App/Dashboard/Panes/TransformsPaneView.swift
//
// The Transforms pane — highlight text, invoke the transform action, and have speak rewrite it
// on-device using local language models. This provides a catalog of built-in and custom rewrite presets.
//
// Lists built-in transforms so the interface is discoverable and ready for custom authoring.

import SpeakCore
import SwiftUI

// MARK: - TransformsPaneView

struct TransformsPaneView: View {
    let context: DashboardContext

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: SpeakSpacing.sm) {
                ForEach(BuiltInTransform.all) { transform in
                    transformRow(transform)
                }
                Spacer(minLength: 0)
            }
            .padding(.top, SpeakSpacing.sm)
            .padding(.horizontal, SpeakSpacing.lg)
        }
    }

    private func transformRow(_ transform: BuiltInTransform) -> some View {
        HStack(alignment: .top, spacing: SpeakSpacing.md) {
            Image(systemName: transform.systemImage)
                .font(.system(size: 18))
                .foregroundStyle(Color.speakAccent)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: SpeakSpacing.xs) {
                Text(transform.name)
                    .font(.speakBody(.base))
                Text(transform.blurb)
                    .font(.speakBody(.caption))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(SpeakSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.speakSurface))
    }
}

// MARK: - BuiltInTransform

/// The built-in rewrite transforms speak ships with (e.g., Polish, Prompt Engineer).
/// Presentation models wired to the on-device cleanup engine.
private struct BuiltInTransform: Identifiable {
    let id: String
    let name: String
    let blurb: String
    let systemImage: String

    static let all: [BuiltInTransform] = [
        BuiltInTransform(id: "polish", name: "Polish",
                         blurb: "Clean up the selection for clarity and concision — no meaning change.",
                         systemImage: "sparkles"),
        BuiltInTransform(id: "prompt", name: "Prompt Engineer",
                         blurb: "Restructure rambling notes into a well-formed AI prompt.",
                         systemImage: "text.badge.star")
    ]
}

// MARK: - Preview

#if DEBUG
#Preview("Transforms") {
    TransformsPaneView(context: DashboardContext(
        settingsStore: SettingsStore(),
        historyStore: PreviewNullHistoryStore(),
        hotkeyCombo: ["Fn", "Fn"]
    ))
    .frame(width: 620, height: 520)
}
#endif
