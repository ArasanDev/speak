// App/Settings/SettingsChrome.swift
//
// The card + row primitives for the dedicated Settings experience — the native
// SwiftUI analogue of t3code's `SettingsSection` (grouped card container) and
// `SettingsRow` (title + description on the left, control on the right).
//
// Tokens: `Color.speakSurface` card fill, `Color.speakCardBorder` hairline,
// `SpeakSpacing` grid, `Font.speakBody`/`speak2*` for chrome — content voice
// (Monaco) is reserved for user data like triggers and expansions.

import SwiftUI

// MARK: - SettingsSectionCard

/// A grouped settings card: muted section header + rounded-rect container with
/// hairline-separated rows, matching the t3code `SettingsSection` rhythm.
struct SettingsSectionCard<Content: View>: View {
    let title: String
    var systemImage: String?
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: SpeakSpacing.sm) {
            HStack(spacing: SpeakSpacing.xs + 2) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.speakBody(.base))
                        .foregroundStyle(.secondary)
                }
                Text(title)
                    .font(.speakBody(.base))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, SpeakSpacing.xs)

            VStack(spacing: 0) {
                content()
            }
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.speakSurface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.speakCardBorder, lineWidth: 1)
            )
        }
    }
}

// MARK: - SettingsRow

/// One setting: title + optional description on the left, control on the right.
/// Mirrors t3code's `SettingsRow` — descriptions stay one line where possible
/// and wrap rather than truncate on narrow windows.
struct SettingsRow<Control: View>: View {
    let title: String
    var description: String?
    @ViewBuilder var control: () -> Control

    init(
        _ title: String,
        description: String? = nil,
        @ViewBuilder control: @escaping () -> Control
    ) {
        self.title = title
        self.description = description
        self.control = control
    }

    var body: some View {
        HStack(alignment: .center, spacing: SpeakSpacing.md) {
            VStack(alignment: .leading, spacing: SpeakSpacing.xs) {
                Text(title)
                    .font(.speakBody(.base))
                    .foregroundStyle(.primary)
                if let description {
                    Text(description)
                        .font(.speakBody(.caption))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: SpeakSpacing.lg)
            control()
                .labelsHidden()
        }
        .padding(.horizontal, SpeakSpacing.md)
        .padding(.vertical, SpeakSpacing.sm + 4)
    }
}

extension SettingsRow where Control == EmptyView {
    /// A label-only row — for status readouts and informational entries.
    init(_ title: String, description: String? = nil) {
        self.init(title, description: description) { EmptyView() }
    }
}

// MARK: - SettingsRowSeparator

/// Hairline divider between rows inside a `SettingsSectionCard`, inset to align
/// with the row label rather than spanning edge-to-edge.
struct SettingsRowSeparator: View {
    var body: some View {
        Divider()
            .overlay(Color.speakCardBorder.opacity(0.6))
            .padding(.leading, SpeakSpacing.md)
    }
}

// MARK: - SettingsStatusPill

/// A tiny capsule status tag ("READY", "ACTIVE", "GRANTED") — the same visual
/// the MCP pane uses for capability status.
struct SettingsStatusPill: View {
    let text: String
    var tint: Color = .speakDelivered

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .bold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(tint.opacity(0.18))
            .foregroundStyle(tint)
            .clipShape(Capsule())
    }
}
