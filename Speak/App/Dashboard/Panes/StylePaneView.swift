// App/Dashboard/Panes/StylePaneView.swift
//
// The Style pane — choose the neat-writing voice (Default/Professional/Casual/Code/Email)
// and the cleanup level (Basic/Balanced/Thorough). Binds to `SettingsStore.cleanupStyle`
// + `.cleanupLevel`; `SpeakEngine.newSession()` reads both at call time, so a change here
// applies on the next dictation (no restart). The per-mode prompt lives in
// FoundationModelsCleaner.styledInstructions (acceleration-plan.md Wave B — the moat).
//
// The pane disables itself when AI cleanup is off (raw transcript mode), since style has
// no effect without the LLM pass — surfaced honestly rather than silently ignored.

import SpeakCore
import SwiftUI

// MARK: - StylePaneView

struct StylePaneView: View {
    let context: DashboardContext

    let settings: SettingsStore

    init(context: DashboardContext) {
        self.context = context
        self.settings = context.settingsStore
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PaneHeader(
                title: "Style",
                subtitle: "Choose how speak rewrites your words — the voice and the polish level."
            )

            if settings.cleanupEnabled {
                content
            } else {
                cleanupOffNotice
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: - Content

    private var content: some View {
        VStack(alignment: .leading, spacing: SpeakSpacing.lg) {
            styleSection
            levelSection
            previewCard
        }
        .padding(.horizontal, SpeakSpacing.lg)
    }

    private var styleSection: some View {
        VStack(alignment: .leading, spacing: SpeakSpacing.sm) {
            Text("Voice")
                .font(.speakMonoBody)
            Picker("Voice", selection: Binding(
                get: { settings.cleanupStyle },
                set: { settings.cleanupStyle = $0 }
            )) {
                ForEach(CleanupStyle.allCases, id: \.self) { style in
                    Text(style.displayName).tag(style)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            Text(styleBlurb(settings.cleanupStyle))
                .font(.speakMonoCaption)
                .foregroundStyle(.secondary)
        }
    }

    private var levelSection: some View {
        VStack(alignment: .leading, spacing: SpeakSpacing.sm) {
            Text("Polish level")
                .font(.speakMonoBody)
            Picker("Polish level", selection: Binding(
                get: { settings.cleanupLevel },
                set: { settings.cleanupLevel = $0 }
            )) {
                ForEach(CleanupLevel.allCases, id: \.self) { level in
                    Text(level.displayName).tag(level)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            Text(levelBlurb(settings.cleanupLevel))
                .font(.speakMonoCaption)
                .foregroundStyle(.secondary)
        }
    }

    private var previewCard: some View {
        VStack(alignment: .leading, spacing: SpeakSpacing.xs) {
            Text("Example")
                .font(.speakMonoCaption)
                .foregroundStyle(.secondary)
            Text(examplePhrase(settings.cleanupStyle))
                .font(.speakMonoBody)
                .textSelection(.enabled)
        }
        .padding(SpeakSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.speakSurface))
    }

    private var cleanupOffNotice: some View {
        PanePlaceholder(
            systemImage: "wand.and.stars",
            message: "AI neat-writing is off — style has no effect in raw transcript mode.\n"
                + "Turn cleanup on in Settings to choose a voice."
        )
    }

    // MARK: - Copy

    private func styleBlurb(_ style: CleanupStyle) -> String {
        switch style {
        case .default:      return "Natural written text in your own words."
        case .professional: return "Polished prose for workplace communication."
        case .casual:       return "Relaxed, conversational, friendly."
        case .code:         return "Preserves identifiers, flags, and paths verbatim."
        case .email:        return "Organized into a clear, courteous email body."
        }
    }

    // W4.1: updated for 4-level scale (none/light/medium/high).
    private func levelBlurb(_ level: CleanupLevel) -> String {
        switch level {
        case .none:   return "Raw transcript — no AI changes applied."
        case .light:  return "Light touch — punctuation and obvious fillers only."
        case .medium: return "Standard cleanup — grammar, punctuation, filler removal."
        case .high:   return "Full polish — tightens phrasing and adds paragraph breaks."
        }
    }

    /// A short illustrative result for the chosen voice. Static copy (not a live LLM
    /// call) — the preview communicates intent without spending an on-device pass.
    private func examplePhrase(_ style: CleanupStyle) -> String {
        switch style {
        case .default:      return "So I think we should ship it on Friday."
        case .professional: return "I believe we should plan to ship on Friday."
        case .casual:       return "I think we're good to ship it Friday."
        case .code:         return "Set isEnabled to true in AppConfig.swift before the build."
        case .email:        return "Hi team — I think we're ready to ship Friday. Let me know if that works."
        }
    }
}

// MARK: - Preview

#if DEBUG
#Preview("Style") {
    StylePaneView(context: DashboardContext(
        settingsStore: SettingsStore(),
        historyStore: PreviewNullHistoryStore(),
        hotkeyCombo: ["Fn", "Fn"]
    ))
    .frame(width: 620, height: 520)
}
#endif
