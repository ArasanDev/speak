// App/DesignSystem/SpeakCard.swift
//
// The shared card primitives. Home's `HomeCardModifier`, Settings'
// `SettingsSectionCard`, and the desk panes all render the same surface —
// flat `speakSurface` fill + `speakCardBorder` hairline — so the modifier
// lives here once instead of being re-implemented per pane.
//
//   speakCard()  — the grouped card (r16), same as `homeCard` /
//                  SettingsSectionCard's container.
//   speakInset() — a recessed well for code/commands/JSON inside a card
//                  (canvas tone + hairline, r8).

import SwiftUI

private struct SpeakCardModifier: ViewModifier {
    var cornerRadius: CGFloat = 16

    func body(content: Content) -> some View {
        content
            .background(Color.speakSurface)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.speakCardBorder, lineWidth: 1)
            )
    }
}

private struct SpeakInsetModifier: ViewModifier {
    var cornerRadius: CGFloat = 8

    func body(content: Content) -> some View {
        content
            .background(Color.speakWindowCanvas)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.speakCardBorder, lineWidth: 1)
            )
    }
}

public extension View {
    /// The standard grouped card — `speakSurface` + `speakCardBorder`, r16.
    func speakCard(cornerRadius: CGFloat = 16) -> some View {
        modifier(SpeakCardModifier(cornerRadius: cornerRadius))
    }

    /// A recessed well for code/commands inside a card — canvas tone + hairline.
    func speakInset(cornerRadius: CGFloat = 8) -> some View {
        modifier(SpeakInsetModifier(cornerRadius: cornerRadius))
    }
}
