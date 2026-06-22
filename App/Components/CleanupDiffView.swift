// App/Components/CleanupDiffView.swift
//
// W4.1 transparency moat — the "see exactly what the AI changed" component.
//
// Shows what the AI cleanup changed between a raw transcript and its cleaned form,
// using a word-level diff computed by `SpeakCore.textDiff(raw:cleaned:)`.
//
// DESIGN:
//   - Wired into Settings▸AI Cleanup (W4.1): `AICleanupSettingsTab` embeds this as
//     a live diff preview that updates when the user changes the cleanup level. The
//     preview uses a canned illustrative transcript; live diffs from real dictations
//     are a future History-detail integration. [decision W4.1: Settings preview first]
//   - Monaco theme throughout (Font.speakMono*, Color.speakAccent, SpeakSpacing).
//     No magic numbers — all sizes are semantic tokens or tagged [decision]. [decision]
//   - Three display modes via `CleanupDiffView.DisplayMode`:
//       .sideBySide  — raw (left) / cleaned (right) panels.
//       .inline      — interleaved red-strikethrough deletes + green inserts (the diff).
//       .cleanedOnly — the cleaned text alone (the "result" view, no diff markup).
//     The default is `.inline` — it is the transparency feature. [decision W4.1]
//   - When `cleanedText == nil` (cleanup off or unavailable), the view shows the
//     raw transcript with a "No AI cleanup" label instead of a diff. This is the
//     correct graceful state (matches the CaptureSession fallback contract). [decision]
//   - Colors: `.speakDiffInsert` (green) and `.speakDiffDelete` (red) are new tokens
//     added as `Color` extensions below. They extend `SpeakTheme.swift`'s palette
//     via the same extension pattern. [decision: Color.speakDiffInsert/speakDiffDelete]
//   - SwiftUI `#Preview` at bottom for visual iteration — no live data needed.
//
// HARD RULES (from CLAUDE.md):
//   - No `print`. No force-unwrap. No magic numbers (all sizes token-traced).
//   - No third-party import. `SpeakCore` is the only non-Apple framework import.

import SwiftUI
import SpeakCore

// MARK: - Diff color tokens (extend SpeakTheme palette)

public extension Color {
    /// Background/tint for inserted words (AI additions). Calm green — visible but not
    /// alarming. Chosen to pair with the speakAccent amber without competing.
    /// [decision W4.1: green (0.2, 0.7, 0.3) at 15% opacity for background,
    ///  full opacity for text indicator]
    static let speakDiffInsert = Color(red: 0.2, green: 0.7, blue: 0.3)

    /// Background/tint for deleted words (AI removals). Muted red to signal removal
    /// without creating visual alarm on every filler-word strip.
    /// [decision W4.1: red (0.85, 0.25, 0.25)]
    static let speakDiffDelete = Color(red: 0.85, green: 0.25, blue: 0.25)
}

// MARK: - CleanupDiffView

/// A reusable SwiftUI component showing what the AI cleanup changed between
/// `rawText` and `cleanedText`, using an inline word-level diff.
///
/// **Standalone in W4.1** — not yet wired into Settings or History. The orchestrator
/// will compose this into those surfaces in later waves.
///
/// Usage:
/// ```swift
/// CleanupDiffView(rawText: result.rawText, cleanedText: result.cleanedText)
/// ```
public struct CleanupDiffView: View {

    // MARK: - Display mode

    /// Controls how the diff is presented. [decision W4.1: .inline is the default
    /// because it is the most informative and most differentiating mode]
    public enum DisplayMode: String, CaseIterable, Sendable {
        /// Interleaved inline diff: deletions in red strikethrough, insertions in green.
        /// The primary transparency view. [decision: this is the moat]
        case inline        = "Inline"
        /// Two panels side by side: raw (left) and cleaned (right).
        case sideBySide    = "Side by Side"
        /// Cleaned text only, no diff markup.
        case cleanedOnly   = "Cleaned"
    }

    // MARK: - Inputs

    /// The raw (pre-cleanup) transcript.
    public let rawText: String
    /// The AI-cleaned text. `nil` when cleanup is off or unavailable (shows raw + label).
    public let cleanedText: String?

    // MARK: - State

    @State private var displayMode: DisplayMode = .inline

    // MARK: - Init

    public init(rawText: String, cleanedText: String?) {
        self.rawText = rawText
        self.cleanedText = cleanedText
    }

    // MARK: - Body

    public var body: some View {
        VStack(alignment: .leading, spacing: SpeakSpacing.sm) {
            headerBar
            Divider()
            contentArea
        }
        .padding(SpeakSpacing.md)
        .background(Color.speakSurface)
        .cornerRadius(SpeakSpacing.sm)   // [decision W4.1: 8pt corner radius, matches speakSurface cards]
    }

    // MARK: - Subviews

    @ViewBuilder
    private var headerBar: some View {
        HStack {
            Text("AI Changes")
                .font(.speakMonoBody)
                .foregroundColor(.secondary)

            Spacer()

            // Mode picker — only shown when cleanedText is non-nil (a diff exists).
            if cleanedText != nil {
                Picker("Mode", selection: $displayMode) {
                    ForEach(DisplayMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 260)  // [decision W4.1: 260pt keeps picker compact]
            }
        }
    }

    @ViewBuilder
    private var contentArea: some View {
        if let cleaned = cleanedText {
            switch displayMode {
            case .inline:
                inlineDiffView(raw: rawText, cleaned: cleaned)
            case .sideBySide:
                sideBySideView(raw: rawText, cleaned: cleaned)
            case .cleanedOnly:
                cleanedOnlyView(text: cleaned)
            }
        } else {
            noCleanupView
        }
    }

    /// Inline interleaved diff: the primary transparency view.
    @ViewBuilder
    private func inlineDiffView(raw: String, cleaned: String) -> some View {
        let segments = textDiff(raw: raw, cleaned: cleaned)
        ScrollView {
            segmentedText(segments: segments)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Side-by-side: raw panel left, cleaned panel right.
    @ViewBuilder
    private func sideBySideView(raw: String, cleaned: String) -> some View {
        HStack(alignment: .top, spacing: SpeakSpacing.md) {
            VStack(alignment: .leading, spacing: SpeakSpacing.xs) {
                Text("Raw")
                    .font(.speakMonoCaption)
                    .foregroundColor(.secondary)
                ScrollView {
                    Text(raw)
                        .font(.speakMonoBody)
                        .foregroundColor(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
            }
            .frame(maxWidth: .infinity)

            Divider()

            VStack(alignment: .leading, spacing: SpeakSpacing.xs) {
                Text("Cleaned")
                    .font(.speakMonoCaption)
                    .foregroundColor(.secondary)
                ScrollView {
                    Text(cleaned)
                        .font(.speakMonoBody)
                        .foregroundColor(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    /// Cleaned-only view: the final result with no diff markup.
    @ViewBuilder
    private func cleanedOnlyView(text: String) -> some View {
        ScrollView {
            Text(text)
                .font(.speakMonoBody)
                .foregroundColor(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
    }

    /// State shown when `cleanedText == nil` (cleanup off or FM unavailable).
    @ViewBuilder
    private var noCleanupView: some View {
        VStack(alignment: .leading, spacing: SpeakSpacing.sm) {
            Label("No AI cleanup applied", systemImage: "wand.and.stars.inverse")
                .font(.speakMonoCaption)
                .foregroundColor(.secondary)

            ScrollView {
                Text(rawText)
                    .font(.speakMonoBody)
                    .foregroundColor(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
        }
    }

    // MARK: - Inline segment rendering

    /// Renders a `[DiffSegment]` as a single `Text` built by concatenation.
    /// SwiftUI `Text` concatenation (`+`) builds a single attributed run with mixed
    /// styles — no `ForEach`, no `HStack` word-wrap issues. [decision W4.1]
    private func segmentedText(segments: [DiffSegment]) -> Text {
        guard !segments.isEmpty else {
            return Text("(empty)").font(.speakMonoBody).foregroundColor(.secondary)
        }

        // Build from first segment so we can use + to accumulate.
        let first = renderSegment(segments[0])
        return segments.dropFirst().reduce(first) { acc, seg in
            // Add a space before each segment to restore word separation.
            acc + Text(" ") + renderSegment(seg)
        }
    }

    /// Render one `DiffSegment` as a styled `Text`.
    private func renderSegment(_ segment: DiffSegment) -> Text {
        switch segment.kind {
        case .equal:
            return Text(segment.text)
                .font(.speakMonoBody)

        case .insert:
            // Inserted words: green + underline to signal "AI added this".
            // [decision W4.1: underline (not bold) to avoid weight mismatch with Monaco]
            return Text(segment.text)
                .font(.speakMonoBody)
                .foregroundColor(.speakDiffInsert)
                .underline(true, color: .speakDiffInsert)

        case .delete:
            // Deleted words: red + strikethrough to signal "AI removed this".
            // [decision W4.1: strikethrough is the universal "crossed out" affordance]
            return Text(segment.text)
                .font(.speakMonoBody)
                .foregroundColor(.speakDiffDelete)
                .strikethrough(true, color: .speakDiffDelete)
        }
    }
}

// MARK: - Preview

#Preview("Inline diff — filler removal") {
    CleanupDiffView(
        rawText: "Um I wanted to uh ask you about the project deadline you know",
        cleanedText: "I wanted to ask you about the project deadline."
    )
    .frame(width: 520, height: 200)
    .padding()
}

#Preview("Side by side") {
    CleanupDiffView(
        rawText: "Um I wanted to uh ask you about the project deadline you know",
        cleanedText: "I wanted to ask you about the project deadline."
    )
    .frame(width: 520, height: 200)
    .padding()
    // Show in side-by-side mode by setting displayMode on the live view;
    // the @State default is .inline, so this preview exercises .inline.
    // To see side-by-side, toggle the segmented picker in Canvas.
}

#Preview("No cleanup (cleanedText nil)") {
    CleanupDiffView(
        rawText: "This is the raw transcript with um some filler words.",
        cleanedText: nil
    )
    .frame(width: 520, height: 160)
    .padding()
}

#Preview("Identical (no changes)") {
    CleanupDiffView(
        rawText: "This is already clean.",
        cleanedText: "This is already clean."
    )
    .frame(width: 520, height: 120)
    .padding()
}

#Preview("High-level restructuring") {
    CleanupDiffView(
        rawText: "so um i was thinking that maybe we should like move the meeting to thursday because on wednesday i have a conflict with another thing",
        cleanedText: "I think we should move the meeting to Thursday. I have a conflict on Wednesday."
    )
    .frame(width: 520, height: 200)
    .padding()
}
