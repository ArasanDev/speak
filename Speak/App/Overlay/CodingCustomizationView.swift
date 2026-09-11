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
// LAYOUT: modern macOS productivity interfaces keep exactly ONE
// control dominant (a free-text field), and every secondary option deferred behind
// progressive disclosure. This panel's core purpose is the custom-instructions text box,
// so it is now the first, largest, auto-focused element; the read-only system-prompt box
// and the 14 format/tone/length preset chips are both collapsed by default behind small
// disclosure affordances the user taps to reveal.
//
// SIZING: this view intentionally does NOT `.frame()`-lock its own size. `.fixedSize` lets
// it report its true ideal size to `NSHostingController.sizingOptions` (see
// `CodingCustomizationPanel`), which is what makes the panel grow/shrink with content
// instead of being a fixed-size clone of `TranscriptOverlayPanel`. Toggling either
// disclosure below changes SwiftUI's ideal size, which the panel already observes via
// `NSWindow.didResizeNotification` — no changes needed there.

import SpeakCore
import SwiftUI

struct CodingCustomizationView: View {
    let model: OverlayViewModel

    /// Collapsed by default — the 14 format/tone/length preset chips are a secondary,
    /// per-dictation override, not the panel's primary purpose. See LAYOUT decision above.
    @State private var isOverridesExpanded = false
    /// Collapsed by default — the read-only resolved system prompt is reference material,
    /// not something most dictations need to see. See LAYOUT decision above.
    @State private var isSystemPromptExpanded = false

    /// Drives keyboard focus into the custom-instructions `TextEditor` as soon as the panel
    /// appears. `CodingCustomizationPanel.canBecomeKey` + `makeKey()` only gets the *window*
    /// key status — SwiftUI still needs an explicit `FocusState` binding pushed on `.onAppear`
    /// for the very first keystroke to land in the text view instead of being dropped.
    @FocusState private var isCustomInstructionsFocused: Bool

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
        .onAppear {
            isCustomInstructionsFocused = true
        }
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
            // Dominant, first element — see LAYOUT decision above.
            customInstructionsSection

            agentPrefixSection

            disclosureToggle(
                title: "View system prompt",
                systemImage: "text.alignleft",
                isExpanded: $isSystemPromptExpanded
            )
            if isSystemPromptExpanded {
                defaultPromptSection
            }

            disclosureToggle(
                title: "Overrides",
                systemImage: "slider.horizontal.3",
                isExpanded: $isOverridesExpanded
            )
            if isOverridesExpanded {
                // Reused from the base HUD (App/Overlay/TranscriptOverlayView.swift) — same
                // per-dictation format/tone/length overrides, same OverlayViewModel instance.
                OverlayKnobsRow(model: model)
            }
        }
    }

    /// A small, low-visual-weight affordance that expands/collapses a deferred section.
    /// [decision, redesign pass: manual chevron+conditional-view over `DisclosureGroup` —
    ///  no existing disclosure pattern elsewhere in App/Overlay to match, and this gives
    ///  precise control over the compact chip-like appearance the other overlay controls use.]
    private func disclosureToggle(title: String, systemImage: String, isExpanded: Binding<Bool>) -> some View {
        Button {
            isExpanded.wrappedValue.toggle()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "chevron.right")
                    .rotationEffect(.degrees(isExpanded.wrappedValue ? 90 : 0))
                Image(systemName: systemImage)
                Text(title)
                Spacer(minLength: 0)
            }
            .font(.speakMonoCaption)
            .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityValue(isExpanded.wrappedValue ? "Expanded" : "Collapsed")
        .accessibilityAddTraits(.isButton)
    }

    /// Read-only display of the profile system prompt that will actually run for this
    /// dictation (set by `DictationController.beginDictation()`). Empty (e.g. Raw
    /// destination, no system prompt) shows a plain-language explanation instead of a
    /// blank box, so the panel never looks broken. Deferred behind the "View system
    /// prompt" disclosure — see LAYOUT decision above.
    private var defaultPromptSection: some View {
        VStack(alignment: .leading, spacing: 2) {
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
    /// This is the panel's dominant, first, auto-focused control — see LAYOUT decision above.
    private var customInstructionsSection: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Additional instructions for this dictation")
                .font(.speakMonoCaption)
                .foregroundStyle(.secondary)
            TextEditor(text: Binding(
                get: { model.customInstructions },
                set: { model.customInstructions = $0 }
            ))
            .font(.speakMonoBody)
            .focused($isCustomInstructionsFocused)
            .scrollContentBackground(.hidden)
            .frame(minHeight: 88, maxHeight: 160)
            .padding(6)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.primary.opacity(0.06))
            )
            .accessibilityLabel("Additional instructions appended to the prompt for this dictation")
        }
    }

    /// Segmented selector for agent prompt tagging ([Off | [speak] | [voice]]).
    /// Allows the developer to tag the dictation output so coding agents apply the Speak skill.
    private var agentPrefixSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Agent Prompt Tag")
                    .font(.speakMonoCaption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("Tags prompt for Speak agent skill")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            HStack(spacing: 4) {
                ForEach(AgentPrefixStyle.allCases, id: \.self) { style in
                    let isSelected = model.agentPrefixStyle == style
                    Button {
                        model.agentPrefixStyle = style
                        model.onKnobChanged?()
                    } label: {
                        Text(style.displayName)
                            .font(.speakMonoCaption)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 3)
                            .background(
                                RoundedRectangle(cornerRadius: 5, style: .continuous)
                                    .fill(isSelected ? Color.accentColor.opacity(0.30) : Color.primary.opacity(0.06))
                            )
                            .foregroundStyle(isSelected ? Color.primary : Color.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Agent Prompt Tag \(style.displayName)")
                    .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
                }
            }
            if model.agentPrefixStyle != .none {
                Toggle(isOn: Binding(
                    get: { model.agentPrefixIncludeState },
                    set: {
                        model.agentPrefixIncludeState = $0
                        model.onKnobChanged?()
                    }
                )) {
                    Text("Include state tag (:clean / :raw)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .toggleStyle(.checkbox)
            }
        }
    }

    /// Close both the SwiftUI-visible flag and notify `OverlayController` to hide the
    /// actual `NSPanel`. Mirrors the open path in `TranscriptOverlayView.customizeButton`.
    private func close() {
        model.isCodingPanelOpen = false
        model.onCodingPanelOpenChanged?(false)
    }
}
