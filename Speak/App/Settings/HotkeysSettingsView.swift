// App/Settings/HotkeysSettingsView.swift
//
// "Hotkeys & Activation" — the second Settings category. The activation hero
// (current binding + trigger style), the recorder sheet, extra (additive)
// bindings, engage/release feedback, and the Accessibility permission that
// powers the CGEventTap.
//
// DATA FLOW:
//   Rebinding routes through `DashboardContext.rebindHotkey` /
//   `rebindExtraBindings` → `DictationController` — the single point of truth
//   that swaps the live tap binding, persists, and republishes.
//   `DashboardContext` is a value-type snapshot refreshed at window-show, so
//   the hero reads `triggerMode` from the observable `SettingsStore` mirror and
//   tracks the just-saved binding locally — a rebind repaints in place instead
//   of waiting for the next dashboard open.
//
//   The Accessibility pill re-reads `AXIsProcessTrusted()` on every render;
//   `permissionRefresh` bumps when the app re-activates (e.g. returning from
//   System Settings) so a grant mid-session is reflected without relaunch.

import AppKit
import Carbon.HIToolbox
import Combine
import SpeakCore
import SwiftUI

// MARK: - HotkeysSettingsView

@MainActor
struct HotkeysSettingsView: View {
    let context: DashboardContext

    @State private var showingRecorder = false
    /// The binding saved via the recorder while this pane is open — the
    /// context snapshot (`activeBinding`) doesn't refresh until next show.
    @State private var savedBinding: HotkeyBinding?
    /// Re-render trigger: bumped on app activation so the permission pill
    /// reflects a grant made in System Settings while the pane was open.
    @State private var permissionRefresh = 0

    private var store: SettingsStore { context.settingsStore }

    /// The binding as it fires today: key + modifiers from the live binding,
    /// trigger from the observable user-facing setting (`SettingsStore
    /// .triggerMode` is the reconcile source — `DictationController` applies
    /// it to the monitor, so this stays true even after the picker flips).
    private var activeBinding: HotkeyBinding {
        (savedBinding ?? context.activeBinding).with(trigger: store.triggerMode)
    }

    private var accessibilityState: PermissionState? {
        _ = permissionRefresh // dependency: repaint when the app re-activates
        return context.permissionManager?.status(.accessibility)
    }

    /// Fn doubles as the macOS Dictation key — worth a callout whenever the
    /// primary binding or any extra binding uses it.
    private var usesFunctionKey: Bool {
        if activeBinding.keyCode == Int(kVK_Function) { return true }
        return store.extraBindings.bindings.contains {
            $0.source == .modifierKey(Int(kVK_Function))
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: SpeakSpacing.lg) {
            activationCard
            feedbackCard
            ExtraBindingsCard(context: context)
            permissionsCard
        }
        .sheet(isPresented: $showingRecorder) {
            HotkeyRecorderView(
                initialBinding: activeBinding,
                onSave: { newBinding in
                    savedBinding = newBinding
                    context.rebindHotkey?(newBinding)
                    showingRecorder = false
                },
                onCancel: { showingRecorder = false }
            )
        }
        .onReceive(
            NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
        ) { _ in
            permissionRefresh += 1
        }
    }

    // MARK: - Activation

    /// One card for the whole gesture: the binding hero on top (unmissable —
    /// keycaps + what it does), then the trigger-style picker and the recorder
    /// entry point as regular rows.
    private var activationCard: some View {
        SettingsSectionCard(title: "Activation") {
            bindingHero
                .padding(.horizontal, SpeakSpacing.md)
                .padding(.top, SpeakSpacing.sm + 4)
                .padding(.bottom, SpeakSpacing.sm)

            if let state = accessibilityState, state != .granted {
                warningCallout(
                    icon: "exclamationmark.triangle",
                    message: "Hotkeys can't fire — speak needs Accessibility permission to see your keystrokes in other apps.",
                    buttonTitle: "Grant Access…"
                ) {
                    _ = context.permissionManager?.requestAccessibility()
                }
                .padding(.horizontal, SpeakSpacing.md)
                .padding(.bottom, SpeakSpacing.sm)
            }

            if usesFunctionKey {
                warningCallout(
                    icon: "exclamationmark.triangle",
                    message: "Fn also triggers macOS Dictation. If presses don't reach speak, turn off the Dictation shortcut in System Settings → Keyboard.",
                    buttonTitle: "Open Keyboard Settings…"
                ) {
                    openKeyboardSettings()
                }
                .padding(.horizontal, SpeakSpacing.md)
                .padding(.bottom, SpeakSpacing.sm)
            }

            SettingsRowSeparator()

            SettingsRow(
                "Trigger style",
                description: triggerExplainer
            ) {
                Picker("", selection: Binding(
                    get: { store.triggerMode },
                    set: { store.triggerMode = $0 }
                )) {
                    Text("Double-tap").tag(HotkeyBinding.Trigger.doubleTap)
                    Text("Hold (push-to-talk)").tag(HotkeyBinding.Trigger.hold)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }

            SettingsRowSeparator()

            SettingsRow(
                "Record a new shortcut",
                description: "Any key+modifier combo, or a modifier-only key like Right ⌘ or Fn."
            ) {
                Button("Record…") { showingRecorder = true }
                    .controlSize(.small)
                    .disabled(context.rebindHotkey == nil)
            }
        }
    }

    /// The hero: the bound keys rendered as keycaps inside a recessed well,
    /// with a one-line description of the gesture. Modifier-only double-taps
    /// render as one cap + "× 2" (a chord joiner would misread as a combo).
    private var bindingHero: some View {
        VStack(spacing: SpeakSpacing.sm) {
            bindingKeycaps
            Text(heroActionLine)
                .font(.speakBody(.caption))
                .foregroundStyle(Color.speakMica)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, SpeakSpacing.md)
        .speakInset(cornerRadius: 12)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Current hotkey: \(activeBinding.displayString). \(heroActionLine)")
    }

    @ViewBuilder
    private var bindingKeycaps: some View {
        if activeBinding.isModifierOnly {
            HStack(spacing: SpeakSpacing.xs) {
                KeyCapView(label: activeBinding.keySymbol, isAccented: true)
                if activeBinding.trigger == .doubleTap {
                    Text("× 2")
                        .font(.speakBody(.base, semibold: true))
                        .foregroundStyle(Color.speakMica)
                }
            }
        } else {
            KeyComboView(keys: activeBinding.keycapLabels)
        }
    }

    private var heroActionLine: String {
        switch activeBinding.trigger {
        case .doubleTap: return "Tap twice to start · tap once to stop"

        case .hold:      return "Hold to talk · release to stop and paste"
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

    /// A caution well inside a card — warning-tinted hairline + icon, readable
    /// body text, and an optional trailing action so the fix is one click away.
    private func warningCallout(
        icon: String,
        message: String,
        buttonTitle: String? = nil,
        action: (() -> Void)? = nil
    ) -> some View {
        HStack(alignment: .top, spacing: SpeakSpacing.sm) {
            Image(systemName: icon)
                .font(.speakBody(.base))
                .foregroundStyle(Color.speakWarning)
                .padding(.top, 1)

            Text(message)
                .font(.speakBody(.caption))
                .foregroundStyle(Color.speakBone)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: SpeakSpacing.sm)

            if let buttonTitle, let action {
                Button(action: action) {
                    Text(buttonTitle)
                }
                .controlSize(.small)
            }
        }
        .padding(SpeakSpacing.sm)
        .background(Color.speakWarning.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.speakWarning.opacity(0.25), lineWidth: 1)
        )
    }

    // MARK: - Feedback

    /// Sensory confirmation on dictation engage/release — fired by
    /// `DictationController` on the menubar-icon state edges.
    private var feedbackCard: some View {
        SettingsSectionCard(title: "Feedback") {
            SettingsRow(
                "Sounds",
                description: "A subtle system chime when dictation engages and releases."
            ) {
                Toggle("", isOn: Binding(
                    get: { store.dictationFeedbackSounds },
                    set: { store.dictationFeedbackSounds = $0 }
                ))
                .toggleStyle(.switch)
                .controlSize(.small)
                .tint(.speakUIAccent)
            }

            SettingsRowSeparator()

            SettingsRow(
                "Trackpad haptics",
                description: "A soft click on Force Touch trackpads at each engage/release edge."
            ) {
                Toggle("", isOn: Binding(
                    get: { store.dictationFeedbackHaptics },
                    set: { store.dictationFeedbackHaptics = $0 }
                ))
                .toggleStyle(.switch)
                .controlSize(.small)
                .tint(.speakUIAccent)
            }
        }
    }

    // MARK: - Permissions

    private var permissionsCard: some View {
        SettingsSectionCard(title: "System Permissions") {
            SettingsRow(
                "Accessibility",
                description: "Required — the global hotkey tap can't see keystrokes without it. macOS gates it in Privacy & Security."
            ) {
                HStack(spacing: SpeakSpacing.sm) {
                    accessibilityPill
                    if let state = accessibilityState, state != .granted {
                        Button("Grant Access…") {
                            _ = context.permissionManager?.requestAccessibility()
                        }
                        .controlSize(.small)
                    }
                }
            }

            SettingsRowSeparator()

            SettingsRow(
                "Not responding?",
                description: "If speak is toggled on in System Settings but the hotkey doesn't fire, re-arm the tap or toggle the permission off/on there."
            ) {
                HStack(spacing: SpeakSpacing.sm) {
                    Button("Re-arm Tap") { context.onSelfHeal?() }
                        .controlSize(.small)
                        .disabled(context.onSelfHeal == nil)
                    Button("Open System Settings…") { openAccessibilitySettings() }
                        .controlSize(.small)
                }
            }
        }
    }

    @ViewBuilder
    private var accessibilityPill: some View {
        switch accessibilityState {
        case .granted:
            SettingsStatusPill(text: "Granted", tint: .speakOK)

        case .denied:
            SettingsStatusPill(text: "Not granted", tint: .speakWarning)

        case .restricted:
            SettingsStatusPill(text: "Restricted", tint: .speakError)

        case .notDetermined, .requesting:
            SettingsStatusPill(text: "Pending", tint: .speakMica)

        case nil:
            SettingsStatusPill(text: "Unavailable", tint: .speakMica)
        }
    }

    // MARK: - System Settings deep links

    private func openAccessibilitySettings() {
        let urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        if let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }
    }

    /// The Dictation shortcut lives in the Keyboard pane.
    /// [inferred: com.apple.preference.keyboard still resolves on macOS 26 —
    ///  the pane hosts the Dictation row]
    private func openKeyboardSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.keyboard") {
            NSWorkspace.shared.open(url)
        }
    }
}
