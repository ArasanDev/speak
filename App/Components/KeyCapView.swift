// App/Components/KeyCapView.swift
//
// A small keyboard-keycap glyph used to render hotkeys in the dashboard (Home pane,
// Insights, onboarding hints). The amber accent face is the project's signature for
// "this is a key you press". (acceleration-plan.md Wave A: "KeyCapView, orange keycap")
//
// Pure presentation — no state, no side effects. The label string is supplied by the
// caller (e.g. "Fn", "⌘", "⏎"). Monaco glyph via the theme token (Font.speakMonoKeycap),
// never a hardcoded family.

import SwiftUI

// MARK: - KeyCapView

struct KeyCapView: View {

    /// The glyph rendered on the cap (e.g. "Fn", "⌘", "⏎", "Esc").
    let label: String

    /// When `true`, the cap renders in the amber accent (the "active"/primary key).
    /// When `false`, it renders in the resting control face.
    var isAccented: Bool = false

    var body: some View {
        Text(label)
            .font(.speakMonoKeycap)
            .foregroundStyle(isAccented ? Color.black.opacity(0.85) : Color.primary)
            .padding(.horizontal, SpeakSpacing.sm)
            .padding(.vertical, SpeakSpacing.xs)
            .frame(minWidth: 28)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isAccented ? Color.speakAccent : Color.speakKeycapFace)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.15), lineWidth: 1)
            )
            .accessibilityLabel("\(label) key")
    }
}

// MARK: - KeyComboView

/// A row of keycaps joined by a subtle "+" — renders a full hotkey combo such as
/// double-tap Fn or ⌘⏎. The last cap is accented to draw the eye to the trigger.
struct KeyComboView: View {

    /// Ordered cap labels, left to right.
    let keys: [String]

    var body: some View {
        HStack(spacing: SpeakSpacing.xs) {
            ForEach(Array(keys.enumerated()), id: \.offset) { index, key in
                if index > 0 {
                    Text("+")
                        .font(.speakMonoCaption)
                        .foregroundStyle(.secondary)
                }
                KeyCapView(label: key, isAccented: index == keys.count - 1)
            }
        }
    }
}

// MARK: - Preview

#if DEBUG
#Preview("Keycaps") {
    VStack(alignment: .leading, spacing: SpeakSpacing.md) {
        KeyCapView(label: "Fn")
        KeyCapView(label: "Fn", isAccented: true)
        KeyComboView(keys: ["Fn", "Fn"])
        KeyComboView(keys: ["⌘", "⏎"])
    }
    .padding(SpeakSpacing.xl)
}
#endif
