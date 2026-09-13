// App/Settings/ExtraBindingsSection.swift
//
// ExtraBindingsSection — the "Additional Shortcuts" editor embedded in the
// Hotkey & Input settings tab (V01-5: up to 4 bindings per action, including
// mouse buttons 4-10). Split out of SettingsView.swift to keep that file under
// SwiftLint's file_length cap [decision: pure code motion, no behavior change].
//
// Applied live via `controller.rebindExtraBindings(_:)` — no restart. See
// `SpeakCore/Hotkey/ExtraBinding.swift` for the underlying model and
// `HotkeyMonitor.updateExtraBindings(_:)` for the tap-side wiring.

import Carbon.HIToolbox
import SpeakCore
import SwiftUI

/// Editor for up to 4 additional bindings per action (activate/stop), applied
/// live via `controller.rebindExtraBindings(_:)`. Independent of the primary
/// toggle binding in `HotkeyInputSettingsTab` — these are direct-fire shortcuts
/// (press → action), including mouse buttons 4-10.
struct ExtraBindingsSection: View {
    let store: SettingsStore
    let controller: DictationController

    /// Same modifier-key set the primary recorder supports
    /// (`HotkeyRecorderView.captureFromFlagsChanged`), reused here so an added
    /// keyboard shortcut is guaranteed to fire (only these keys are observed
    /// via `flagsChanged` — see `modifierMask(forKeyCode:)`).
    private static let modifierKeyOptions: [(label: String, keyCode: Int)] = [
        ("Fn", Int(kVK_Function)),
        ("Right ⌘", Int(kVK_RightCommand)),
        ("⌘", Int(kVK_Command)),
        ("Right ⌥", Int(kVK_RightOption)),
        ("⌥", Int(kVK_Option))
    ]

    @State private var newSourceIsMouse: Bool = false
    @State private var newModifierKeyCode: Int = Int(kVK_Function)
    @State private var newMouseButton: Int = ExtraBindingSet.mouseButtonRange.lowerBound
    @State private var newAction: HotkeyAction = .activate
    @State private var addErrorMessage: String?

    var body: some View {
        Section {
            let bindings = controller.activeExtraBindings.bindings
            if bindings.isEmpty {
                Text("No additional shortcuts configured.")
                    .font(.speakBody(.caption))
                    .foregroundStyle(Color.speakMica)
            } else {
                ForEach(bindings) { binding in
                    HStack {
                        Text(binding.source.displayString)
                            .font(.speakBody(.base))
                            .foregroundStyle(Color.speakBone)
                        Spacer()
                        Text(binding.action.displayString)
                            .font(.speakBody(.caption))
                            .foregroundStyle(Color.speakMica)
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

            Picker("Input", selection: $newSourceIsMouse) {
                Text("Keyboard").tag(false)
                Text("Mouse Button").tag(true)
            }
            .pickerStyle(.segmented)
            .foregroundStyle(Color.speakBone)

            if newSourceIsMouse {
                Picker("Mouse Button", selection: $newMouseButton) {
                    ForEach(Array(ExtraBindingSet.mouseButtonRange), id: \.self) { number in
                        Text("Button \(number)").tag(number)
                    }
                }
                .foregroundStyle(Color.speakBone)
            } else {
                Picker("Key", selection: $newModifierKeyCode) {
                    ForEach(Self.modifierKeyOptions, id: \.keyCode) { option in
                        Text(option.label).tag(option.keyCode)
                    }
                }
                .foregroundStyle(Color.speakBone)
            }

            Picker("Action", selection: $newAction) {
                ForEach(HotkeyAction.allCases, id: \.self) { action in
                    Text(action.displayString).tag(action)
                }
            }
            .foregroundStyle(Color.speakBone)

            Button("Add Shortcut") {
                addBinding()
            }

            if let addErrorMessage {
                Text(addErrorMessage)
                    .font(.speakBody(.caption))
                    .foregroundStyle(Color.speakError)
            }
        } header: {
            Text("Additional Shortcuts")
                .foregroundStyle(Color.speakBone)
        } footer: {
            Text(
                "Up to \(ExtraBindingSet.maxPerAction) shortcuts per action. These fire immediately on press — "
                + "no double-tap. A bound mouse button still performs its normal system action alongside dictation."
            )
                .font(.speakBody(.caption))
                .foregroundStyle(Color.speakMica)
        }
    }

    private func addBinding() {
        let source: ExtraBindingSource = newSourceIsMouse
            ? .mouseButton(newMouseButton)
            : .modifierKey(newModifierKeyCode)
        let candidate = ExtraBinding(source: source, action: newAction)
        guard let updated = controller.activeExtraBindings.adding(candidate) else {
            addErrorMessage = "That shortcut can't be added — it may already be bound, or this action already has \(ExtraBindingSet.maxPerAction) shortcuts."
            return
        }
        addErrorMessage = nil
        controller.rebindExtraBindings(updated)
    }

    private func remove(_ binding: ExtraBinding) {
        controller.rebindExtraBindings(controller.activeExtraBindings.removing(id: binding.id))
    }
}
