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
        initialCategory: SettingsCategory = .generalAudio,
        onBack: @escaping () -> Void = {},
        onOpenSection: @escaping (DashboardSection) -> Void = { _ in }
    ) {
        self.context = context
        self.presentation = presentation
        self.onBack = onBack
        self.onOpenSection = onOpenSection
        _category = State(initialValue: initialCategory)
    }

    /// Traffic-light clearance — the dashboard window is `.fullSizeContentView`
    /// with a transparent titlebar. The standalone Settings window has a normal
    /// titlebar, so no inset is needed there.
    private var leadingInset: CGFloat {
        presentation == .embedded ? 78 : SpeakSpacing.lg
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            HStack(spacing: 0) {
                rail
                    .frame(width: 224)

                detailCard
                    .padding(SpeakSpacing.md)
            }
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

    // MARK: - Header

    private var header: some View {
        HStack(spacing: SpeakSpacing.sm) {
            if presentation == .embedded {
                BackToDashboardButton(action: onBack)
            } else {
                Text("Settings")
                    .font(.speakBody(.base, semibold: true))
                    .foregroundStyle(.primary)
            }

            breadcrumb

            Spacer(minLength: 0)

            if presentation == .embedded {
                HStack(spacing: SpeakSpacing.xs) {
                    KeyCapView(label: "esc")
                    Text("to go back")
                        .font(.speakBody(.caption))
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.leading, leadingInset)
        .padding(.trailing, SpeakSpacing.lg)
        .frame(height: 52)
        .overlay(alignment: .bottom) {
            Divider().overlay(Color.speakCardBorder.opacity(0.6))
        }
    }

    private var breadcrumb: some View {
        HStack(spacing: SpeakSpacing.xs) {
            if presentation == .embedded {
                Text("Settings")
                    .font(.speakBody(.base, semibold: true))
                    .foregroundStyle(.primary)
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.tertiary)
            }
            Text(category.title)
                .font(.speakBody(.base))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Left rail

    private var rail: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SpeakSpacing.md) {
                ForEach(SettingsCategoryGroup.allCases) { group in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(group.title.uppercased())
                            .font(.speakBody(.caption))
                            .foregroundStyle(.tertiary)
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
            .padding(.vertical, SpeakSpacing.md)
        }
    }

    // MARK: - Right detail canvas

    /// The detail surface — a rounded card matching the Mode A desk pane so
    /// Settings reads as the same window, not a separate app.
    private var detailCard: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SpeakSpacing.sm) {
                VStack(alignment: .leading, spacing: SpeakSpacing.xs) {
                    Text(category.title)
                        .font(.speak2Title)
                    Text(category.subtitle)
                        .font(.speakBody(.caption))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, SpeakSpacing.xs)
                .padding(.bottom, SpeakSpacing.sm)

                detail(for: category)
            }
            .padding(SpeakSpacing.lg)
            .frame(maxWidth: 860, alignment: .leading)
            .frame(maxWidth: .infinity)
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
        case .generalAudio: GeneralAudioSettingsView(context: context)
        case .hotkeys:      HotkeysSettingsView(context: context)
        case .aiModels:     AIModelsSettingsView(context: context)
        case .vocabulary:   VocabularySettingsView(context: context)
        case .agentBridge:  AgentBridgeSettingsView(context: context, onOpenSection: onOpenSection)
        case .appearance:   AppearanceHUDSettingsView(context: context)
        case .privacy:      PrivacyHealthSettingsView(context: context)
        case .about:        AboutSettingsTab().frame(minHeight: 420)
        }
    }
}

// MARK: - BackToDashboardButton

private struct BackToDashboardButton: View {
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: SpeakSpacing.xs) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 12, weight: .semibold))
                Text("Dashboard")
                    .font(.speakBody(.base, semibold: true))
            }
            .foregroundStyle(isHovering ? .primary : .secondary)
            .padding(.horizontal, SpeakSpacing.sm)
            .padding(.vertical, SpeakSpacing.xs + 1)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.primary.opacity(isHovering ? 0.08 : 0))
            )
        }
        .buttonStyle(.plain)
        .help("Back to Dashboard (Esc)")
        .onHover { isHovering = $0 }
    }
}

// MARK: - SettingsRailRow

/// One rail destination: SF Symbol + label in a selection pill. Sits flush with
/// the group header above it — the t3code `SidebarMenuButton` analogue.
private struct SettingsRailRow: View {
    let category: SettingsCategory
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: SpeakSpacing.sm) {
                Image(systemName: category.systemImage)
                    .font(.system(size: 13))
                    .foregroundStyle(isSelected ? .primary : .secondary)
                    .frame(width: 18)
                Text(category.title)
                    .font(.speakBody(.base, semibold: isSelected))
                    .foregroundStyle(isSelected ? .primary : .secondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, SpeakSpacing.sm)
            .padding(.vertical, SpeakSpacing.xs + 2)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(
                        isSelected
                            ? Color.speakSidebarSelection
                            : (isHovering ? Color.primary.opacity(0.05) : Color.clear)
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}
