// App/Dashboard/PaneScaffold.swift
//
// Shared chrome for dashboard panes so every pane shares one header rhythm and the
// not-yet-built panes read as intentional placeholders (not broken screens).
//
// `PaneHeader` — a Monaco title + optional subtitle, the standard top of each pane.
// `PanePlaceholder` — the "this lands in this wave" empty state used by scaffolded panes
//   until their specialist fills the body. Replace the placeholder, keep the header.

import SwiftUI

// MARK: - PaneHeader

/// Standard pane header: a Monaco title row with an optional subtitle line.
struct PaneHeader: View {
    let title: String
    var subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: SpeakSpacing.xs) {
            Text(title)
                .font(.speakMonoTitle)
            if let subtitle {
                Text(subtitle)
                    .font(.speakMonoCaption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, SpeakSpacing.lg)
        .padding(.top, SpeakSpacing.lg)
        .padding(.bottom, SpeakSpacing.md)
    }
}

// MARK: - PanePlaceholder

/// The empty-state body for a pane whose feature is scheduled but not yet built.
/// Honest by design: tells the user (and the next agent) what belongs here.
struct PanePlaceholder: View {
    let systemImage: String
    let message: String

    var body: some View {
        VStack(spacing: SpeakSpacing.sm) {
            Image(systemName: systemImage)
                .font(.system(size: 34))
                .foregroundStyle(.tertiary)
            Text(message)
                .font(.speakMonoCaption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(SpeakSpacing.xl)
    }
}
