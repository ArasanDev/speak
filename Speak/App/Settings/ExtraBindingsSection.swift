// App/Settings/ExtraBindingsSection.swift
//
// ExtraBindingsCard — the "Additional Shortcuts" editor in Settings → Hotkeys
// (V01-5: up to `ExtraBindingSet.maxPerAction` bindings per action, including
// mouse buttons 4–10).
//
// These are ADDITIVE to the primary toggle binding — direct-fire shortcuts
// (press → action), no double-tap window, no release edge. Edits route through
// `DashboardContext.rebindExtraBindings` → `DictationController` — the single
// point of truth that swaps the live tap set, persists, and republishes.
//
// The list binds to `SettingsStore.extraBindings` — the observable user-facing
// mirror `rebindExtraBindings` writes — rather than the `context` struct
// snapshot, so rows repaint immediately on add/remove. See
// `SpeakCore/Hotkey/ExtraBinding.swift` for the model and
// `HotkeyMonitor.updateExtraBindings(_:)` for the tap-side wiring.

import Carbon.HIToolbox
import SpeakCore
import SwiftUI

// MARK: - ExtraBindingsCard

/// Editor for the additive bindings set: rows render the bound input as a
/// keycap (keyboard) or glyph + label (mouse), the mapped action as a status
/// pill, and a trailing remove affordance. The composer below blocks with a
/// reason — duplicate source, per-action cap — before the Add button ever
/// fires, and cautions on high-collision generic modifiers.
struct ExtraBindingsCard: View {
    let context: DashboardContext

    /// The modifier-key set the tap observes via `flagsChanged` — only these
    /// keys can fire a keyboard extra binding (same set the primary recorder
    /// supports; see `HotkeyRecorderView.captureFromFlagsChanged` /
    /// `modifierMask(forKeyCode:)`).
    private static let modifierKeyOptions: [(label: String, keyCode: Int)] = [
        ("Fn", Int(kVK_Function)),
        ("Right ⌘", Int(kVK_RightCommand)),
        ("⌘", Int(kVK_Command)),
        ("Right ⌥", Int(kVK_RightOption)),
        ("⌥", Int(kVK_Option))
    ]

    /// Generic (left-side) modifier keyCodes: the tap fires on that key's
    /// press edge, which opens EVERY chord — a bound ⌘ would trigger on ⌘C.
    /// Side-specific keys (Right ⌘/Right ⌥) and Fn are the safe picks.
    /// [mirrors validateCapture's ambiguousModifier set, HotkeyRecorderView]
    private static let highCollisionKeyCodes: Set<Int> = [
        Int(kVK_Command),
        Int(kVK_Option)
    ]

    @State private var newSourceIsMouse = false
    @State private var newModifierKeyCode = Int(kVK_Function)
    @State private var newMouseButton = ExtraBindingSet.mouseButtonRange.lowerBound
    @State private var newAction: HotkeyAction = .activate
    @State private var addErrorMessage: String?

    private var store: SettingsStore { context.settingsStore }

    /// The live set — read through the observable store mirror (written by
    /// `rebindExtraBindings`) so add/remove repaint in place.
    private var bindings: ExtraBindingSet { store.extraBindings }

    /// The input the composer is currently pointed at.
    private var candidateSource: ExtraBindingSource {
        newSourceIsMouse
            ? .mouseButton(newMouseButton)
            : .modifierKey(newModifierKeyCode)
    }

    /// Proactive composer block — surfaced as a caption and disables Add, so
    /// the user sees *why* before clicking rather than an error after.
    private var addBlocker: String? {
        if let existing = bindings.action(for: candidateSource) {
            return "Already bound — it \(existing == .activate ? "starts" : "stops") dictation."
        }
        let count = bindings.bindings.filter { $0.action == newAction }.count
        if count >= ExtraBindingSet.maxPerAction {
            return "\(newAction.displayString) already has \(ExtraBindingSet.maxPerAction) shortcuts — remove one first."
        }
        return nil
    }

    /// Non-blocking caution for the high-collision generic modifiers — allowed
    /// (user autonomy), but warned like the recorder's ambiguousModifier rule.
    private var collisionCaution: String? {
        guard !newSourceIsMouse,
              Self.highCollisionKeyCodes.contains(newModifierKeyCode) else { return nil }
        return "This key fires on every press — including inside chords you type normally. Right ⌘, Right ⌥, or Fn is safer."
    }

    var body: some View {
        SettingsSectionCard(title: "Additional Shortcuts") {
            if bindings.bindings.isEmpty {
                Text("No additional shortcuts. These fire immediately on press — no double-tap needed.")
                    .font(.speakBody(.caption))
                    .foregroundStyle(Color.speakMica)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, SpeakSpacing.md)
                    .padding(.vertical, SpeakSpacing.sm + 4)
            } else {
                ForEach(Array(bindings.bindings.enumerated()), id: \.element.id) { index, binding in
                    if index > 0 { SettingsRowSeparator() }
                    bindingRow(binding)
                }
            }

            SettingsRowSeparator()

            composer
                .padding(.horizontal, SpeakSpacing.md)
                .padding(.vertical, SpeakSpacing.sm + 4)
        }
    }

    // MARK: - Binding rows

    private func bindingRow(_ binding: ExtraBinding) -> some View {
        HStack(spacing: SpeakSpacing.sm) {
            sourceBadge(binding.source)

            Image(systemName: "arrow.right")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(Color.speakMica)

            SettingsStatusPill(
                text: binding.action == .activate ? "Start" : "Stop",
                tint: binding.action == .activate ? .speakHumanAmber : .speakMica
            )

            Spacer(minLength: 0)

            Button {
                remove(binding)
            } label: {
                Image(systemName: "minus.circle")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.speakMica)
            }
            .buttonStyle(.borderless)
            .help("Remove shortcut")
            .accessibilityLabel("Remove \(binding.source.displayString) shortcut")
        }
        .padding(.horizontal, SpeakSpacing.md)
        .padding(.vertical, SpeakSpacing.sm)
    }

    /// The bound input, rendered the way it looks on hardware: a keycap for
    /// keys, a mouse glyph + button number for clicks.
    @ViewBuilder
    private func sourceBadge(_ source: ExtraBindingSource) -> some View {
        switch source {
        case .modifierKey:
            KeyCapView(label: source.displayString)

        case .mouseButton(let number):
            HStack(spacing: SpeakSpacing.xs) {
                Image(systemName: "mouse.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.speakHumanAmber)
                Text("Button \(number)")
                    .font(.speakBody(.caption, semibold: true))
                    .foregroundStyle(Color.speakBone)
            }
        }
    }

    // MARK: - Composer

    private var composer: some View {
        VStack(alignment: .leading, spacing: SpeakSpacing.sm) {
            Text("Add a shortcut")
                .font(.speakBody(.caption, semibold: true))
                .foregroundStyle(Color.speakBone)

            HStack(spacing: SpeakSpacing.sm) {
                Picker("", selection: $newSourceIsMouse) {
                    Text("Keyboard").tag(false)
                    Text("Mouse").tag(true)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 148) // [decision: fits both segments at base size]

                if newSourceIsMouse {
                    Picker("", selection: $newMouseButton) {
                        ForEach(Array(ExtraBindingSet.mouseButtonRange), id: \.self) { number in
                            Text("Button \(number)").tag(number)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                } else {
                    Picker("", selection: $newModifierKeyCode) {
                        ForEach(Self.modifierKeyOptions, id: \.keyCode) { option in
                            Text(option.label).tag(option.keyCode)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                }

                Image(systemName: "arrow.right")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Color.speakMica)

                Picker("", selection: $newAction) {
                    ForEach(HotkeyAction.allCases, id: \.self) { action in
                        Text(action.displayString).tag(action)
                    }
                }
                .labelsHidden()
                .fixedSize()

                Spacer(minLength: 0)

                Button("Add") { addBinding() }
                    .controlSize(.small)
                    .disabled(context.rebindExtraBindings == nil || addBlocker != nil)
            }

            if let addBlocker {
                caption(addBlocker, tint: .speakWarning)
            } else if let collisionCaution {
                caption(collisionCaution, tint: .speakWarning)
            } else if let addErrorMessage {
                caption(addErrorMessage, tint: .speakError)
            }

            Text(
                "Fires immediately on press — no double-tap. Up to \(ExtraBindingSet.maxPerAction) per action. "
                + "A bound mouse button still performs its normal click too."
            )
            .font(.speakBody(.caption))
            .foregroundStyle(Color.speakMica)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func caption(_ text: String, tint: Color) -> some View {
        HStack(alignment: .top, spacing: SpeakSpacing.xs) {
            Image(systemName: "exclamationmark.triangle")
                .font(.speakBody(.caption))
                .foregroundStyle(tint)
            Text(text)
                .font(.speakBody(.caption))
                .foregroundStyle(tint)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Mutations

    private func addBinding() {
        let candidate = ExtraBinding(source: candidateSource, action: newAction)
        guard let updated = bindings.adding(candidate) else {
            addErrorMessage = "That shortcut can't be added — it may already be bound, or this action already has \(ExtraBindingSet.maxPerAction) shortcuts."
            return
        }
        addErrorMessage = nil
        context.rebindExtraBindings?(updated)
    }

    private func remove(_ binding: ExtraBinding) {
        context.rebindExtraBindings?(bindings.removing(id: binding.id))
    }
}
