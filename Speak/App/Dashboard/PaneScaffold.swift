// App/Dashboard/PaneScaffold.swift
//
// Shared chrome for dashboard panes so every pane shares one rhythm and the
// not-yet-built panes read as intentional placeholders (not broken screens).
//
// `PanePlaceholder` — the "this lands in this wave" empty state used by scaffolded panes
//   until their specialist fills the body. Pane titles are owned by the desk
//   header (`DashboardSection.title`/`.subtitle`) — panes render no hero title
//   of their own, so there is exactly one title per screen.

import SwiftUI
#if DEBUG
import SpeakCore
#endif

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
                .foregroundStyle(Color.speakMica)
            Text(message)
                .font(.speakBody(.caption))
                .foregroundStyle(Color.speakMica)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(SpeakSpacing.xl)
    }
}

// MARK: - Preview support

#if DEBUG
/// A no-op `HistoryStoring` for SwiftUI previews of dashboard panes that require a
/// `DashboardContext`. Every method succeeds with empty results.
final class PreviewNullHistoryStore: HistoryStoring, @unchecked Sendable {
    func save(_ entry: HistoryEntry) throws {}
    func recent(limit: Int) throws -> [HistoryEntry] { [] }
    func search(_ substring: String) throws -> [HistoryEntry] { [] }
    func clear() throws {}
    func export() throws -> String { "[]" }
}
#endif
