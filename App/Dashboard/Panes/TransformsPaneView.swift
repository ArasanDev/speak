// App/Dashboard/Panes/TransformsPaneView.swift
//
// The Transforms pane — highlight any text, press a shortcut, and have speak rewrite it
// on-device (verified Wispr pattern: built-ins "Polish" and "Prompt Engineer"). This is
// the read-side catalog of transforms; the live highlight→rewrite action is Wave D
// (Command Mode shares the same on-device cleanup seam).
//
// SCAFFOLD: lists the built-in transforms so the IA is complete and discoverable. The
// per-transform run/edit + custom-transform authoring lands in Wave D. Keep the PaneHeader.

import SwiftUI
import SpeakCore

// MARK: - TransformsPaneView

struct TransformsPaneView: View {
    let context: DashboardContext

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PaneHeader(
                title: "Transforms",
                subtitle: "Highlight text anywhere, press your shortcut, and speak — speak rewrites it on-device."
            )
            VStack(alignment: .leading, spacing: SpeakSpacing.sm) {
                ForEach(BuiltInTransform.all) { transform in
                    transformRow(transform)
                }
                Spacer(minLength: 0)
            }
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
                    .font(.speakMonoBody)
                Text(transform.blurb)
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

// MARK: - BuiltInTransform

/// The built-in transforms speak ships with (mirrors Wispr's Polish / Prompt Engineer).
/// Pure presentation data for now; wired to the on-device cleanup seam in Wave D.
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
