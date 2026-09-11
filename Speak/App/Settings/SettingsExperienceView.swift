// App/Settings/SettingsExperienceView.swift
//
// The dedicated two-panel Settings experience (Mode B of the dashboard window).
//
//   ┌──────────────────────────────────────────────────────────┐
//   │ ‹ Dashboard   Settings › <Category>                esc   │  ← header
//   ├────────────┬─────────────────────────────────────────────┤
//   │ rail       │  detail canvas — card-based settings        │
//   │ (grouped   │  (ScrollView of SettingsSectionCards)       │
//   │  nav)      │                                             │
//   └────────────┴─────────────────────────────────────────────┘
//
// Entered when `DashboardView.selection == .settings`. `onBack` returns to the
// desk; `onOpenSection` jumps to a dashboard section (e.g. "Open MCP & Agents").
// Esc and Cmd+[ are bound to `onBack` via hidden shortcut buttons.
//
// [decision: custom rail over NavigationSplitView — the rail is fixed-width,
//  grouped, and intentionally non-collapsible inside an already-split window;
//  a nested split would fight the outer dashboard chrome.]

import SpeakCore
import SwiftUI

// MARK: - SettingsExperienceView

@MainActor
struct SettingsExperienceView: View {
    let context: DashboardContext
    let onBack: () -> Void
    let onOpenSection: (DashboardSection) -> Void

    @State private var category: SettingsCategory = .generalAudio

    /// Traffic-light clearance — the dashboard window is `.fullSizeContentView`
    /// with a transparent titlebar, so leading chrome pads past the lights.
    private let trafficLightInset: CGFloat = 78

    var body: some View {
        VStack(spacing: 0) {
            header

            HStack(spacing: 0) {
                rail
                    .frame(width: 208)

                Divider()
                    .overlay(Color.speakCardBorder.opacity(0.6))

                detailCanvas
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.speakWindowCanvas)
        // Esc (also Cmd+.) and Cmd+[ both return to the dashboard desk.
        .background(
            Group {
                Button(action: onBack) { EmptyView() }
                    .keyboardShortcut(.cancelAction)
                Button(action: onBack) { EmptyView() }
                    .keyboardShortcut("[", modifiers: .command)
            }
            .opacity(0)
        )
    }

    // MARK: - Header (back + breadcrumb)

    private var header: some View {
        HStack(spacing: SpeakSpacing.sm) {
            BackToDashboardButton(action: onBack)

            breadcrumb

            Spacer(minLength: 0)

            HStack(spacing: SpeakSpacing.xs) {
                KeyCapView(label: "esc")
                Text("to go back")
                    .font(.speakBody(.caption))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.leading, trafficLightInset)
        .padding(.trailing, SpeakSpacing.lg)
        .frame(height: 52)
        .overlay(alignment: .bottom) {
            Divider().overlay(Color.speakCardBorder.opacity(0.6))
        }
    }

    private var breadcrumb: some View {
        HStack(spacing: SpeakSpacing.xs) {
            Text("Settings")
                .font(.speakBody(.base, semibold: true))
                .foregroundStyle(.primary)
            Image(systemName: "chevron.right")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.tertiary)
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
        .background(Color.speakSidebarBg.opacity(0.5))
    }

    // MARK: - Right detail canvas

    private var detailCanvas: some View {
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
            .padding(.horizontal, SpeakSpacing.lg)
            .padding(.vertical, SpeakSpacing.lg)
            .frame(maxWidth: 860, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(Color.speakCardCanvas)
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
                    .foregroundStyle(isSelected ? Color.speakAccent : .secondary)
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
