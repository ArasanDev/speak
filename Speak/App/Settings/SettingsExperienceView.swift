// App/Settings/SettingsExperienceView.swift
//
// The dedicated two-panel Settings experience — the single canonical Settings
// surface for the app. Used in two presentations:
//
//   .embedded   — inside the dashboard window (Mode B). The desk swaps out for
//                 this view; `onBack` returns to the desk, Esc / Cmd+[ are
//                 bound via hidden shortcut buttons, and the header insets
//                 past the traffic lights (.fullSizeContentView).
//
//   .standalone — the SwiftUI `Settings` scene (Cmd+,). Same rail + same
//                 detail cards, but no back button / esc hint — the window
//                 chrome already provides close.
//
// [decision: custom rail over NavigationSplitView — the rail is fixed-width,
//  grouped, and intentionally non-collapsible inside an already-split window;
//  a nested split would fight the outer dashboard chrome.]
//
// Detail chrome mirrors the Mode A desk pane: a radius-24 `speakCardCanvas`
// card floating on `speakWindowCanvas`, so Settings reads as the same surface
// as Home rather than a separate app.

import SpeakCore
import SwiftUI

// MARK: - SettingsExperienceView

@MainActor
struct SettingsExperienceView: View {

    enum Presentation {
        /// Inside the dashboard window — back button, esc hint, traffic-light inset.
        case embedded
        /// The SwiftUI Settings scene (Cmd+,) — plain title header, no back chrome.
        case standalone
    }

    let context: DashboardContext
    var presentation: Presentation = .embedded
    var onBack: () -> Void = {}
    var onOpenSection: (DashboardSection) -> Void = { _ in }

    @State private var category: SettingsCategory

    init(
        context: DashboardContext,
        presentation: Presentation = .embedded,
        initialCategory: SettingsCategory = .pipeline,
        onBack: @escaping () -> Void = {},
        onOpenSection: @escaping (DashboardSection) -> Void = { _ in }
    ) {
        self.context = context
        self.presentation = presentation
        self.onBack = onBack
        self.onOpenSection = onOpenSection
        _category = State(initialValue: initialCategory)
    }

    var body: some View {
        HStack(spacing: 0) {
            rail
                .frame(width: 220)

            detailCard
                .padding(SpeakSpacing.md)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.speakWindowCanvas)
        // Esc (also Cmd+.) and Cmd+[ return to the dashboard desk — embedded only;
        // the standalone window relies on its own close affordance.
        .background(
            Group {
                if presentation == .embedded {
                    Button(action: onBack) { EmptyView() }
                        .keyboardShortcut(.cancelAction)
                    Button(action: onBack) { EmptyView() }
                        .keyboardShortcut("[", modifiers: .command)
                }
            }
            .opacity(0)
        )
    }

    // MARK: - Left rail

    private var rail: some View {
        VStack(spacing: 0) {
            if presentation == .embedded {
                // Mirrors Mode A's sidebar-toggle row: 28pt of traffic-light
                // clearance with the back button at the same x position.
                HStack {
                    BackToDashboardButton(action: onBack)
                        .padding(.leading, 80)
                    Spacer()
                }
                .frame(height: 28)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: SpeakSpacing.md) {
                    ForEach(SettingsCategoryGroup.allCases) { group in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(group.title.uppercased())
                                .font(.speakBody(.caption))
                                .foregroundStyle(Color.speakMica)
                                .padding(.horizontal, SpeakSpacing.sm)
                                .padding(.bottom, SpeakSpacing.xs)

                            ForEach(group.categories) { item in
                                SettingsRailRow(
                                    category: item,
                                    isSelected: item == category
                                ) {
                                    withAnimation(.easeInOut(duration: 0.15)) {
                                        category = item
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, SpeakSpacing.sm)
                .padding(.vertical, SpeakSpacing.sm)
            }
        }
    }

    // MARK: - Right detail canvas

    /// The detail surface — identical chrome to the Mode A desk pane: a slim
    /// `.headline` title row inside a radius-24 `speakCardCanvas` card floating
    /// on `speakWindowCanvas`, so Settings reads as the same window as Home.
    private var detailCard: some View {
        VStack(spacing: 0) {
            HStack(spacing: SpeakSpacing.sm) {
                Text(category.title)
                    .font(.headline)
                    .foregroundStyle(Color.speakBone)
                Text(category.subtitle)
                    .font(.speakBody(.caption))
                    .foregroundStyle(Color.speakMica)
                    .lineLimit(1)

                Spacer(minLength: 0)

                if presentation == .embedded {
                    HStack(spacing: SpeakSpacing.xs) {
                        KeyCapView(label: "esc")
                        Text("to go back")
                            .font(.speakBody(.caption))
                            .foregroundStyle(Color.speakMica)
                    }
                }
            }
            .padding(.leading, SpeakSpacing.md)
            .padding(.trailing, SpeakSpacing.md)
            .frame(height: 44)

            ScrollView {
                detail(for: category)
                    .padding(.horizontal, SpeakSpacing.lg)
                    .padding(.bottom, SpeakSpacing.lg)
                    .frame(maxWidth: 860, alignment: .leading)
                    .frame(maxWidth: .infinity)
            }
        }
        .background(Color.speakCardCanvas)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.speakCardBorder, lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.05), radius: 12, y: 4)
        // Category switch gets a subtle cross-fade so the canvas doesn't hard-cut.
        .animation(.easeInOut(duration: 0.15), value: category)
    }

    @ViewBuilder
    private func detail(for category: SettingsCategory) -> some View {
        switch category {
        case .pipeline:
            PipelineSettingsView(context: context) { target in
                withAnimation(.easeInOut(duration: 0.15)) { self.category = target }
            }
        case .speechToText: SpeechToTextSettingsView(context: context)
        case .textToSpeech: TextToSpeechSettingsView(context: context)
        case .intelligence: IntelligenceSettingsView(context: context)
        case .hotkeys:      HotkeysSettingsView(context: context)
        case .vocabulary:   VocabularySettingsView(context: context)
        case .agentBridge:  AgentBridgeSettingsView(context: context, onOpenSection: onOpenSection)
        case .appearance:   AppearanceHUDSettingsView(context: context)
        case .privacy:      PrivacyHealthSettingsView(context: context)
        case .general:      GeneralSettingsView(context: context)
        case .about:        AboutSettingsTab().frame(minHeight: 420)
        }
    }
}

// MARK: - BackToDashboardButton

/// Icon back button at the Mode A sidebar-toggle position — same 26×26 hit
/// area and hover treatment so the two surfaces share chrome.
private struct BackToDashboardButton: View {
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "chevron.left")
                .font(.system(size: 15))
                .foregroundColor(Color.speakMica)
                .frame(width: 26, height: 26)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(Color.primary.opacity(isHovering ? 0.08 : 0))
        .cornerRadius(6)
        .help("Back to Dashboard (Esc)")
        .onHover { isHovering = $0 }
    }
}

// MARK: - SettingsRailRow

/// One rail destination: a plain monochrome glyph + label, exactly like the
/// desk sidebar's `Label` rows (and t3code's `SettingsSidebarNav`, where icons
/// are muted `size-3.5` glyphs with no tiles). Selection is the same accent
/// pill the desk's `.listStyle(.sidebar)` renders — shape and weight carry the
/// state, never icon color.
private struct SettingsRailRow: View {
    let category: SettingsCategory
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: SpeakSpacing.sm) {
                Image(systemName: category.systemImage)
                    .font(.system(size: 14))
                    .foregroundStyle(isSelected ? Color.speakOnAccent : .secondary)
                    .frame(width: 20)
                Text(category.title)
                    .font(.speakBody(.base, semibold: isSelected))
                    .foregroundStyle(isSelected ? Color.speakOnAccent : .secondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, SpeakSpacing.sm)
            .padding(.vertical, SpeakSpacing.xs + 2)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(
                        isSelected
                            ? Color.speakUIAccent
                            : (isHovering ? Color.primary.opacity(0.05) : Color.clear)
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}
