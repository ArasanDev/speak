// App/Dashboard/Panes/InferenceComponents.swift
//
// Shared visual chrome for the Inference pane (`InferencePaneView.swift` +
// `InferenceToolsViews.swift`). Extracted so the three files each stay well
// under the 400-line file_length budget and so every card in the pane shares
// ONE elevation, ONE header rhythm, and ONE control language.
//
// [decision: the pane's old look failed for two structural reasons, not a
//  shortage of effects — (1) every string was Monaco at one of two sizes, so
//  nothing was a heading and nothing was data; (2) cards were filled with
//  `Color.speakSurface` (= `.underPageBackgroundColor`, a *recessed* system
//  color) and had no border, so they read as holes punched in the pane.
//  The fix is the type system already in the repo: SF Pro (`Font.speakBody`)
//  for chrome/labels/controls, Monaco (`Font.speakMono*`) reserved for DATA
//  ONLY — URLs, keys, IDs, endpoints, numerals, code. Elevation comes from a
//  `speakCardCanvas` fill + a `speakCardBorder` hairline + a whisper of
//  shadow, the additive FE-1 tokens that SpeakTheme has no equivalent for.]
//
// Naming: every symbol here is prefixed `Inference*` because `private` does not
// cross files — these are internal to the App target and must not collide.
//
// Pasteboard is WRITE-ONLY here (AGENTS.md §2.6). No print — os.Logger only.

import AppKit
import SwiftUI

// MARK: - Metrics

/// The pane's local geometry constants. [decision: a 14pt card radius sits
/// between the dashboard's 12pt cards and Home's 16pt glass cards; controls use
/// 7pt so nested corners stay concentric rather than parallel.]
enum InferenceMetrics {
    static let cardRadius: CGFloat = 14
    static let controlRadius: CGFloat = 7
    static let codeRadius: CGFloat = 9
    static let glyphSide: CGFloat = 26
    static let statusDot: CGFloat = 8
    static let hairline: CGFloat = 1
}

// MARK: - InferenceCard

/// The one card container for the pane: a raised surface with a hairline border
/// and a titled header (glyph + title + optional subtitle + optional accessory).
struct InferenceCard<Content: View, Accessory: View>: View {
    let systemImage: String
    let title: String
    var subtitle: String?
    /// Tint for the header glyph. Also tints the card's border when `isEmphasized`.
    var tint: Color = .speakMica
    /// When true the border picks up `tint` — used by the server card when running.
    var isEmphasized = false
    @ViewBuilder var accessory: () -> Accessory
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: SpeakSpacing.md) {
            HStack(alignment: .center, spacing: SpeakSpacing.sm) {
                InferenceGlyph(systemImage: systemImage, tint: tint)

                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.speakBody(.base, semibold: true))
                        .foregroundStyle(Color.speakBone)
                    if let subtitle {
                        Text(subtitle)
                            .font(.speakBody(.caption))
                            .foregroundStyle(Color.speakMica)
                            // Narrow panes (the dashboard floor is 480pt wide,
                            // sidebar included) must wrap the subtitle rather
                            // than truncate it against the accessory button.
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .layoutPriority(1)

                Spacer(minLength: SpeakSpacing.sm)

                accessory()
            }

            content()
        }
        .padding(SpeakSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: InferenceMetrics.cardRadius, style: .continuous)
                .fill(Color.speakCardCanvas)
        )
        .overlay(
            RoundedRectangle(cornerRadius: InferenceMetrics.cardRadius, style: .continuous)
                .strokeBorder(
                    isEmphasized ? tint.opacity(0.45) : Color.speakCardBorder,
                    lineWidth: InferenceMetrics.hairline
                )
        )
        // [decision: a 1pt-offset, 10pt shadow at 6% — enough to lift the card
        //  off the pane without the drop-shadow look of a 2010s dashboard.]
        .shadow(color: Color.black.opacity(0.06), radius: 10, x: 0, y: 1)
    }
}

extension InferenceCard where Accessory == EmptyView {
    init(
        systemImage: String,
        title: String,
        subtitle: String? = nil,
        tint: Color = .speakMica,
        isEmphasized: Bool = false,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.init(
            systemImage: systemImage,
            title: title,
            subtitle: subtitle,
            tint: tint,
            isEmphasized: isEmphasized,
            accessory: { EmptyView() },
            content: content
        )
    }
}

// MARK: - InferenceGlyph

/// A tinted rounded-square icon chip — the card header's anchor.
struct InferenceGlyph: View {
    let systemImage: String
    var tint: Color = .speakMica

    var body: some View {
        RoundedRectangle(cornerRadius: InferenceMetrics.controlRadius, style: .continuous)
            .fill(tint.opacity(0.14))
            .frame(width: InferenceMetrics.glyphSide, height: InferenceMetrics.glyphSide)
            .overlay(
                Image(systemName: systemImage)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(tint)
            )
    }
}

// MARK: - InferenceStatusDot

/// A status dot with an optional soft halo that breathes while `isLive`.
/// The breath reads a real signal (the server is up), per the SpeakMotion charter.
struct InferenceStatusDot: View {
    let color: Color
    var isLive = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var haloScale: CGFloat = 1

    var body: some View {
        ZStack {
            if isLive {
                Circle()
                    .fill(color.opacity(0.22))
                    .frame(width: InferenceMetrics.statusDot * 2.4,
                           height: InferenceMetrics.statusDot * 2.4)
                    .scaleEffect(haloScale)
                    .opacity(reduceMotion ? 0.7 : 2 - haloScale)
            }
            Circle()
                .fill(color)
                .frame(width: InferenceMetrics.statusDot, height: InferenceMetrics.statusDot)
        }
        .frame(width: InferenceMetrics.statusDot * 2.4, height: InferenceMetrics.statusDot * 2.4)
        .onAppear { startBreath() }
        .onChange(of: isLive) { _, _ in startBreath() }
    }

    private func startBreath() {
        guard isLive, !reduceMotion else {
            haloScale = 1
            return
        }
        haloScale = 1
        withAnimation(SpeakMotion.idleBreath(reduceMotion: false)) {
            haloScale = 1.35
        }
    }
}

// MARK: - InferenceButton

/// The pane's one button. `.filled` is the primary affordance (one per card at
/// most); `.tinted` and `.quiet` step down from it. Hover raises the fill by a
/// notch through `SpeakMotion.micro` so the control feels alive but never noisy.
struct InferenceButton: View {
    enum Emphasis { case filled, tinted, quiet }

    let title: String
    var systemImage: String?
    var tint: Color = .speakUIAccent
    var emphasis: Emphasis = .tinted
    var isBusy = false
    let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovering = false

    var body: some View {
        Button {
            action()
        } label: {
            HStack(spacing: SpeakSpacing.xs) {
                if isBusy {
                    ProgressView()
                        .controlSize(.small)
                        .scaleEffect(0.7)
                        .frame(width: 11, height: 11)
                } else if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 10, weight: .semibold))
                }
                Text(title)
                    .font(.speakBody(.caption, semibold: true))
            }
            .padding(.horizontal, SpeakSpacing.sm + 2)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: InferenceMetrics.controlRadius, style: .continuous)
                    .fill(background)
            )
            .overlay(
                RoundedRectangle(cornerRadius: InferenceMetrics.controlRadius, style: .continuous)
                    .strokeBorder(border, lineWidth: InferenceMetrics.hairline)
            )
            .foregroundStyle(foreground)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(isEnabled ? 1 : 0.4)
        .onHover { hovering in
            withAnimation(SpeakMotion.micro(reduceMotion: reduceMotion)) {
                isHovering = hovering && isEnabled
            }
        }
    }

    private var background: Color {
        switch emphasis {
        case .filled: return tint.opacity(isHovering ? 1 : 0.9)
        case .tinted: return tint.opacity(isHovering ? 0.22 : 0.13)
        case .quiet: return Color.primary.opacity(isHovering ? 0.07 : 0.03)
        }
    }

    private var border: Color {
        switch emphasis {
        case .filled: return .clear
        case .tinted: return tint.opacity(0.22)
        case .quiet: return Color.speakCardBorder
        }
    }

    private var foreground: Color {
        switch emphasis {
        case .filled: return Color.speakOnAccent
        case .tinted: return tint
        case .quiet: return Color.speakMica
        }
    }
}

// MARK: - InferenceCopyButton

/// A quiet copy affordance that writes to NSPasteboard (write-only,
/// AGENTS.md §2.6) and swaps to a checkmark for a beat — the swap reads a real
/// signal (the copy happened), so it earns its animation.
struct InferenceCopyButton: View {
    let text: String
    var label: String?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var copied = false
    @State private var isHovering = false

    var body: some View {
        Button {
            copyToPasteboard()
        } label: {
            HStack(spacing: SpeakSpacing.xs) {
                Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 10, weight: .semibold))
                if let label {
                    Text(copied ? "Copied" : label)
                        .font(.speakBody(.caption, semibold: true))
                }
            }
            .foregroundStyle(copied ? Color.speakDelivered : Color.speakMica)
            .padding(.horizontal, label == nil ? 5 : SpeakSpacing.sm)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: InferenceMetrics.controlRadius - 1, style: .continuous)
                    .fill(Color.primary.opacity(isHovering ? 0.07 : 0))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(copied ? "Copied" : "Copy to clipboard")
        .onHover { hovering in
            withAnimation(SpeakMotion.micro(reduceMotion: reduceMotion)) {
                isHovering = hovering
            }
        }
    }

    private func copyToPasteboard() {
        // Write-only pasteboard access (AGENTS.md §2.6: never read the pasteboard).
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        withAnimation(SpeakMotion.micro(reduceMotion: reduceMotion)) { copied = true }
        Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            withAnimation(SpeakMotion.micro(reduceMotion: reduceMotion)) { copied = false }
        }
    }
}

// MARK: - InferenceEmptyState

/// The pane's empty/blocked state: a glyph, a headline, one line of guidance,
/// and — crucially — the action that resolves it. [decision: the pane's default
/// state IS the empty state (server stopped, nothing discovered); shipping it as
/// three gray sentences was the single loudest thing wrong with the old design.]
struct InferenceEmptyState<Action: View>: View {
    let systemImage: String
    let headline: String
    let message: String
    @ViewBuilder var action: () -> Action

    var body: some View {
        VStack(spacing: SpeakSpacing.sm) {
            Image(systemName: systemImage)
                .font(.system(size: 22, weight: .regular))
                .foregroundStyle(Color.speakMica)
            VStack(spacing: 2) {
                Text(headline)
                    .font(.speakBody(.base, semibold: true))
                    .foregroundStyle(Color.speakMica)
                Text(message)
                    .font(.speakBody(.caption))
                    .foregroundStyle(Color.speakMica)
                    .multilineTextAlignment(.center)
            }
            action()
                .padding(.top, 2)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, SpeakSpacing.lg)
        .background(
            RoundedRectangle(cornerRadius: InferenceMetrics.codeRadius, style: .continuous)
                .fill(Color.primary.opacity(0.02))
        )
    }
}

extension InferenceEmptyState where Action == EmptyView {
    init(systemImage: String, headline: String, message: String) {
        self.init(systemImage: systemImage, headline: headline, message: message) { EmptyView() }
    }
}
