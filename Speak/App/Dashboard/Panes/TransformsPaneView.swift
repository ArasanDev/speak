// App/Dashboard/Panes/TransformsPaneView.swift
//
// The Transforms pane — highlight text, invoke the transform action, and have speak rewrite it
// on-device using local language models. This provides a catalog of built-in and custom rewrite presets.
//
// Lists built-in transforms so the interface is discoverable and ready for custom authoring.
//
// Layout contract: the section header sits on the canvas (16pt semibold, the
// dashboard's one header rhythm); rows live inside a single `speakCard` with
// hairlines between them rather than a card per row.

import SpeakCore
import SwiftUI

// MARK: - TransformsPaneView

struct TransformsPaneView: View {
    let context: DashboardContext

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SpeakSpacing.sm) {
                Text("Built-in Transforms")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.speakBone)

                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(BuiltInTransform.all.enumerated()), id: \.offset) { index, transform in
                        TransformRow(transform: transform)
                        if index < BuiltInTransform.all.count - 1 {
                            TransformHairline(indented: true)
                        }
                    }

                    TransformHairline(indented: false)

                    // Where custom transforms go — AI Studio's profiles are the
                    // authoring surface; this catalog is the discovery surface.
                    Text("Custom transforms are authored as profiles in AI Studio.")
                        .font(.speakBody(.caption))
                        .foregroundStyle(Color.speakMica)
                        .padding(.horizontal, SpeakSpacing.md)
                        .padding(.vertical, SpeakSpacing.sm + 2)
                }
                .speakCard()
            }
            .padding(.top, SpeakSpacing.sm)
            .padding(.horizontal, SpeakSpacing.lg)
            .padding(.bottom, SpeakSpacing.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - TransformRow

private struct TransformRow: View {
    let transform: BuiltInTransform

    var body: some View {
        HStack(alignment: .top, spacing: SpeakSpacing.md) {
            // Transforms are agent work done on your text — the violet channel.
            Image(systemName: transform.systemImage)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.speakAgentViolet)
                .frame(width: 24)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 2) {
                Text(transform.name)
                    .font(.speakBody(.base, semibold: true))
                    .foregroundStyle(Color.speakBone)
                Text(transform.blurb)
                    .font(.speakBody(.caption))
                    .foregroundStyle(Color.speakMica)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, SpeakSpacing.md)
        .padding(.vertical, SpeakSpacing.sm + 2)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - TransformHairline

/// The themed hairline between rows — `Divider()` picks up a system gray that
/// fights the two-temperature palette.
private struct TransformHairline: View {
    /// Row separators indent past the icon column so they align with the text
    /// block; the footer's separator runs the full card width.
    var indented = true

    var body: some View {
        Rectangle()
            .fill(Color.speakCardBorder)
            .frame(height: 1)
            .opacity(0.5)
            .padding(.leading, indented ? SpeakSpacing.md + 24 + SpeakSpacing.md : 0)
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
