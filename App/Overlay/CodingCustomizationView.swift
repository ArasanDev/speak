// App/Overlay/CodingCustomizationView.swift
//
// SwiftUI content hosted by `CodingCustomizationPanel` (P-Code v2) — the real-time
// PROMPT-CUSTOMIZATION surface opened from the base HUD's single button. Shows the
// system prompt that will actually govern cleanup for the current dictation
// (`model.defaultSystemPrompt`, read-only — DictationController sets it from the
// per-app-resolved profile) and an editable "additional instructions" field the user
// can type into to append to that prompt at runtime. [decision P-Code v2: append-only,
// not full prompt replacement — the user's stated preference, and the simpler correct
// wire: `PromptBuilder.customInstructionsClause` appends it as the final instruction.]
//
// Also still reuses `OverlayKnobsRow` (format / tone / length overrides) — those are
// orthogonal per-dictation knobs, unrelated to the (now-removed) Agent-category picker,
// so they stay useful here. Both bind the same `OverlayViewModel` instance as the base HUD.
//
// SIZING: this view intentionally does NOT `.frame()`-lock its own size. `.fixedSize` lets
// it report its true ideal size to `NSHostingController.sizingOptions` (see
// `CodingCustomizationPanel`), which is what makes the panel grow/shrink with content
// instead of being a fixed-size clone of `TranscriptOverlayPanel`.

import SpeakCore
import SwiftUI

struct CodingCustomizationView: View {
    let model: OverlayViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: SpeakSpacing.sm) {
            header
            Divider()
            content
        }
        .padding(SpeakSpacing.md)
        .frame(minWidth: 360, maxWidth: 480, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.regularMaterial)
        )
    }

    private var header: some View {
        HStack(spacing: SpeakSpacing.xs) {
            Image(systemName: "slider.horizontal.3")
                .foregroundStyle(.secondary)
            Text("Customize this dictation's prompt")
                .font(.speakMonoBody)
                .fontWeight(.semibold)
            Spacer(minLength: 0)
            Button {
                close()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close prompt customization panel")
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: SpeakSpacing.sm) {
            defaultPromptSection
            customInstructionsSection
            // Reused from the base HUD (App/Overlay/TranscriptOverlayView.swift) — same
            // per-dictation format/tone/length overrides, same OverlayViewModel instance.
            OverlayKnobsRow(model: model)
        }
    }

    /// Read-only display of the profile system prompt that will actually run for this
    /// dictation (set by `DictationController.beginDictation()`). Empty (e.g. Raw
    /// destination, no system prompt) shows a plain-language explanation instead of a
    /// blank box, so the panel never looks broken.
    private var defaultPromptSection: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Current prompt")
                .font(.speakMonoCaption)
                .foregroundStyle(.secondary)
            ScrollView {
                Text(model.defaultSystemPrompt.isEmpty
                    ? "No system prompt for this dictation (AI cleanup is off, or the active destination is Raw)."
                    : model.defaultSystemPrompt)
                    .font(.speakMonoCaption)
                    .foregroundStyle(model.defaultSystemPrompt.isEmpty ? .tertiary : .secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            // [decision P-Code v2: 72 pt cap — long profile prompts scroll instead of
            //  pushing the panel past a comfortable height; matches the panel's own
            //  dynamic-but-bounded sizing philosophy.]
            .frame(maxHeight: 72)
            .padding(SpeakSpacing.xs)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.primary.opacity(0.05))
            )
        }
    }

    /// Editable "append at runtime" field. Bound directly to `model.customInstructions` —
    /// `DictationController` reads it off the model at stop time (same no-callback-needed
    /// pattern as the format/tone/length knobs), so no `onChange` wiring is required here.
    private var customInstructionsSection: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Additional instructions for this dictation")
                .font(.speakMonoCaption)
                .foregroundStyle(.secondary)
            TextEditor(text: Binding(
                get: { model.customInstructions },
                set: { model.customInstructions = $0 }
            ))
            .font(.speakMonoCaption)
            .scrollContentBackground(.hidden)
            .frame(minHeight: 44, maxHeight: 88)
            .padding(4)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.primary.opacity(0.05))
            )
            .accessibilityLabel("Additional instructions appended to the prompt for this dictation")
        }
    }

    /// Close both the SwiftUI-visible flag and notify `OverlayController` to hide the
    /// actual `NSPanel`. Mirrors the open path in `TranscriptOverlayView.customizeButton`.
    private func close() {
        model.isCodingPanelOpen = false
        model.onCodingPanelOpenChanged?(false)
    }
}
