// App/Settings/HotkeysSettingsView.swift
//
// "Hotkeys & Activation" — the second Settings category. Activation mode,
// the primary hotkey recorder, extra (additive) bindings, and the
// Accessibility permission that powers the CGEventTap.
//
// Rebinding routes through `DashboardContext.rebindHotkey` /
// `rebindExtraBindings` → `DictationController` — the single point of truth
// that swaps the live tap binding, persists, and republishes.

import Carbon.HIToolbox
import SpeakCore
import SwiftUI

// MARK: - HotkeysSettingsView

@MainActor
struct HotkeysSettingsView: View {
    let context: DashboardContext

    @State private var showingRecorder = false

    private var store: SettingsStore { context.settingsStore }

    var body: some View {
        VStack(alignment: .leading, spacing: SpeakSpacing.lg) {
            activationCard
            primaryHotkeyCard
            ExtraBindingsCard(context: context)
            permissionsCard
        }
        .sheet(isPresented: $showingRecorder) {
            HotkeyRecorderView(
                initialBinding: context.activeBinding,
                onSave: { newBinding in
                    context.rebindHotkey?(newBinding)
                    showingRecorder = false
                },
                onCancel: { showingRecorder = false }
            )
        }
    }

    // MARK: - Activation mode

    private var activationCard: some View {
        SettingsSectionCard(title: "Activation", systemImage: "bolt") {
            VStack(alignment: .leading, spacing: SpeakSpacing.sm) {
                Picker("", selection: Binding(
                    get: { store.triggerMode },
                    set: { store.triggerMode = $0 }
                )) {
                    Text("Double-tap").tag(HotkeyBinding.Trigger.doubleTap)
                    Text("Hold (push-to-talk)").tag(HotkeyBinding.Trigger.hold)
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                Text(triggerExplainer)
                    .font(.speakBody(.caption))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, SpeakSpacing.md)
            .padding(.vertical, SpeakSpacing.sm + 4)
        }
    }

    private var triggerExplainer: String {
        switch store.triggerMode {
        case .doubleTap:
            return "Tap the hotkey twice to start; tap once to stop."

        case .hold:
            return "Hold the hotkey to record; release to stop and paste."
        }
    }

    // MARK: - Primary hotkey

    private var primaryHotkeyCard: some View {
        SettingsSectionCard(title: "Primary Hotkey", systemImage: "command") {
            SettingsRow(
                "Current binding",
                description: "Record any key+modifier combo or a modifier-only key (Right ⌘, Fn)."
            ) {
                HStack(spacing: SpeakSpacing.xs) {
                    ForEach(context.hotkeyCombo, id: \.self) { key in
                        KeyCapView(label: key)
                    }
                    Button("Change…") { showingRecorder = true }
                        .disabled(context.rebindHotkey == nil)
                }
            }
        }
    }

    // MARK: - Permissions

    private var permissionsCard: some View {
        SettingsSectionCard(title: "System Permissions", systemImage: "hand.raised") {
            SettingsRow(
                "Accessibility",
                description: "Required for the global hotkey tap (CGEventTap). macOS gates it in Privacy & Security."
            ) {
                if context.permissionManager?.status(.accessibility) == .granted {
                    SettingsStatusPill(text: "Granted")
                } else {
                    SettingsStatusPill(text: "Missing", tint: .orange)
                }
            }

            SettingsRowSeparator()

            SettingsRow(
                "Re-check & re-arm",
                description: "If speak is toggled ON in System Settings but not responding, re-arm the tap or toggle it off/on there."
            ) {
                HStack(spacing: SpeakSpacing.sm) {
                    Button("Re-arm Tap") { context.onSelfHeal?() }
                        .disabled(context.onSelfHeal == nil)
                    Button("Open System Settings…") { openAccessibilitySettings() }
                }
            }
        }
    }

    private func openAccessibilitySettings() {
        let urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        if let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }
    }
}

// MARK: - ExtraBindingsCard

/// Editor for the additive bindings set (V01-5): up to `maxPerAction`
/// direct-fire shortcuts per action, including mouse buttons 4–10.
/// Same model as `ExtraBindingsSection` in the legacy tabbed Settings, routed
/// through `DashboardContext` instead of the controller directly.
private struct ExtraBindingsCard: View {
    let context: DashboardContext

    /// The modifier-key set the primary recorder supports — only these keys are
    /// observed via `flagsChanged` (see `HotkeyRecorderView.captureFromFlagsChanged`).
    private static let modifierKeyOptions: [(label: String, keyCode: Int)] = [
        ("Fn", Int(kVK_Function)),
        ("Right ⌘", Int(kVK_RightCommand)),
        ("⌘", Int(kVK_Command)),
        ("Right ⌥", Int(kVK_RightOption)),
        ("⌥", Int(kVK_Option))
    ]

    @State private var newSourceIsMouse = false
    @State private var newModifierKeyCode = Int(kVK_Function)
    @State private var newMouseButton = ExtraBindingSet.mouseButtonRange.lowerBound
    @State private var newAction: HotkeyAction = .activate
    @State private var addErrorMessage: String?

    private var bindings: ExtraBindingSet { context.activeExtraBindings }

    var body: some View {
        SettingsSectionCard(title: "Additional Shortcuts", systemImage: "plus.rectangle.on.rectangle") {
            VStack(alignment: .leading, spacing: SpeakSpacing.sm) {
                if bindings.bindings.isEmpty {
                    Text("No additional shortcuts. These fire immediately on press — no double-tap.")
                        .font(.speakBody(.caption))
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(bindings.bindings) { binding in
                        HStack {
                            Text(binding.source.displayString)
                                .font(.speakMonoBody)
                            Spacer()
                            Text(binding.action.displayString)
                                .font(.speakBody(.caption))
                                .foregroundStyle(.secondary)
                            Button(role: .destructive) {
                                remove(binding)
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                }

                Divider()

                HStack(spacing: SpeakSpacing.sm) {
                    Picker("", selection: $newSourceIsMouse) {
                        Text("Keyboard").tag(false)
                        Text("Mouse").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 150)

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

                    Picker("", selection: $newAction) {
                        ForEach(HotkeyAction.allCases, id: \.self) { action in
                            Text(action.displayString).tag(action)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()

                    Spacer()

                    Button("Add") { addBinding() }
                        .disabled(context.rebindExtraBindings == nil)
                }

                if let addErrorMessage {
                    Text(addErrorMessage)
                        .font(.speakBody(.caption))
                        .foregroundStyle(.red)
                }
            }
            .padding(.horizontal, SpeakSpacing.md)
            .padding(.vertical, SpeakSpacing.sm + 4)
        }
    }

    private func addBinding() {
        let source: ExtraBindingSource = newSourceIsMouse
            ? .mouseButton(newMouseButton)
            : .modifierKey(newModifierKeyCode)
        let candidate = ExtraBinding(source: source, action: newAction)
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
