// App/Settings/HotkeyRecorderView.swift
//
// HotkeyRecorderView — a sheet that lets the user record a new hotkey binding.
//
// DESIGN (W1.1 hotkey recorder):
//   Opens as a sheet from ShortcutsSettingsTab when the user taps "Record Shortcut…".
//   While recording, a local NSEvent monitor (in-window, no permission needed) captures
//   .keyDown and .flagsChanged events. The user presses the desired key combo once;
//   the view detects the press-edge and shows a live preview via HotkeyBinding.displayString.
//
//   Modifier-only double-tap keys (Right-Command, Fn) arrive via .flagsChanged only —
//   no .keyDown event. Regular key+modifier combos (e.g. ⌘+Shift+D) arrive as .keyDown
//   with modifier flags set. Both are supported.
//
// CAPTURE STATE MACHINE:
//   .idle       — waiting for the user to start (shows current binding)
//   .recording  — local NSEvent monitor active; showing "Press your shortcut…"
//   .captured   — a valid binding is previewed; user can Save or Re-record
//   .invalid    — captured combo failed validation; shows a warning
//
// LOCAL MONITOR NOTES:
//   NSEvent.addLocalMonitorForEvents(matching:) is in-window only; requires NO
//   Accessibility or Input Monitoring permission [verified: AppKit docs — local
//   monitors fire only when the app is key, 2026-06-22].
//   The monitor token is stored and removed on sheet dismiss or re-record.
//   [decision: local monitor for the recorder — CGEventTap is already the global
//    runtime path; using a separate in-window monitor for the recorder avoids any
//    entanglement with the live tap, 2026-06-22]
//
// VALIDATION:
//   reject(binding:) returns a HotkeyRecorderWarning? describing why the combo is unsafe.
//   Currently warns on bare-modifier-only combos that have no keyCode specificity
//   (e.g. pressing just Command with no additional key) — these would activate on
//   any Command-key press. Modifier-only keys that identify a specific physical key
//   (Right-Command keyCode 54, Fn keyCode 63) are accepted since they are low-collision.
//
// THREADING:
//   All SwiftUI view bodies are @MainActor (implicit). NSEvent local monitor
//   callbacks arrive on the main thread [verified: AppKit docs, 2026-06-22].
//
// DESIGN TOKENS:
//   Monaco font / SpeakSpacing / speakSurface per SpeakTheme (SettingsView.swift contract).
//
// NO MAGIC NUMBERS:
//   - cornerRadius 8: [decision: matches macOS control radius — aligns with RoundedRectangle
//     used in ShortcutsSettingsTab keycap display, W3.1]
//   - sheet min width 400/height 260: [decision: fits the preview label + two-button row
//     comfortably at default Dynamic Type size, W1.1]

import SwiftUI
import AppKit
import SpeakCore
import Carbon.HIToolbox

// MARK: - HotkeyCapture (pure, testable)

/// The result of capturing a key event from the NSEvent local monitor.
/// Pure value type — no AppKit dependency at this layer — so it can be
/// unit-tested by constructing values directly.
public struct HotkeyCapture: Equatable, Sendable {
    /// The Carbon key code of the pressed key (or modifier key).
    public let keyCode: Int
    /// The modifier flags present at capture time.
    public let modifiers: CGEventFlags
    /// Whether this capture came from a .flagsChanged event (modifier-only press).
    public let isModifierOnly: Bool
}

// MARK: - HotkeyRecorderWarning

/// A human-readable warning emitted by `validateCapture(_:)` when the combo is
/// risky but not invalid (we warn rather than hard-reject to respect user autonomy).
public enum HotkeyRecorderWarning: Equatable, Sendable {
    /// A generic modifier (Command, Shift, etc.) without a specific physical key
    /// identity — this would collide with normal typing.
    case ambiguousModifier
    /// The captured key code is unrecognised (keyCode 0 with no modifiers).
    case unrecognised
}

// MARK: - Pure capture helpers (pure value logic; no test file added in W1.1 — candidates for a future HotkeyRecorderTests.swift)

/// Convert an NSEvent from a .flagsChanged event into a `HotkeyCapture`.
/// Returns nil if the event doesn't represent a supported modifier-only key.
///
/// Supported modifier-only keys: Right-Command (kVK_RightCommand = 54),
/// Fn (kVK_Function = 63), Left-Command (kVK_Command = 55),
/// Right-Option (kVK_RightOption = 61), Left-Option (kVK_Option = 58).
/// [decision: limit to the small set of keys HotkeyBinding already models;
///  arbitrary modifier keys are unrecognised — the user will see a warning, W1.1]
public func captureFromFlagsChanged(keyCode: Int, cgFlags: CGEventFlags) -> HotkeyCapture? {
    let supportedModifierKeys: Set<Int> = [
        Int(kVK_RightCommand), // 54 [verified: Carbon/HIToolbox + SDK, 2026-06-21]
        Int(kVK_Command),      // 55 [verified: Carbon/HIToolbox]
        Int(kVK_Function),     // 63 [verified: Carbon/HIToolbox + SDK, 2026-06-20]
        Int(kVK_RightOption),  // 61 [verified: Carbon/HIToolbox]
        Int(kVK_Option),       // 58 [verified: Carbon/HIToolbox]
    ]
    guard supportedModifierKeys.contains(keyCode) else { return nil }
    return HotkeyCapture(keyCode: keyCode, modifiers: cgFlags, isModifierOnly: true)
}

/// Convert an NSEvent from a .keyDown event into a `HotkeyCapture`.
/// Requires at least one modifier to avoid capturing bare letters/digits.
///
/// The modifier flags are translated from NSEvent.modifierFlags.
/// We require that at least Command, Option, Control, or Shift is held —
/// bare key presses without a modifier are not useful as a global hotkey
/// and would collide with normal typing.
/// [decision: require-modifier gate matches behaviour of macOS ShortcutRecorder, W1.1]
public func captureFromKeyDown(
    keyCode: Int,
    nsModifiers: NSEvent.ModifierFlags,
    cgFlags: CGEventFlags
) -> HotkeyCapture? {
    let usefulModifiers: NSEvent.ModifierFlags = [.command, .option, .control, .shift]
    guard nsModifiers.intersection(usefulModifiers).isEmpty == false else { return nil }
    return HotkeyCapture(keyCode: keyCode, modifiers: cgFlags, isModifierOnly: false)
}

/// Build a `HotkeyBinding` from a `HotkeyCapture` and an explicit `Trigger`.
///
/// Modifier-only captures (isModifierOnly == true) use the capture's keyCode directly
/// as the binding key. Regular key-down captures also use the keyCode directly.
/// The doubleTapWindow defaults to 0.4 s [decision: benchmark.md §7].
public func bindingFromCapture(
    _ capture: HotkeyCapture,
    trigger: HotkeyBinding.Trigger
) -> HotkeyBinding {
    HotkeyBinding(
        keyCode: capture.keyCode,
        modifiers: capture.modifiers,
        trigger: trigger,
        doubleTapWindow: 0.4 // benchmark.md §7 [decision]
    )
}

/// Validate a `HotkeyCapture` and return a warning if the combo is risky.
/// Returns `nil` if the combo looks safe.
///
/// Current rules:
///   - keyCode 0 with empty modifiers → .unrecognised
///   - A generic (non-identity) modifier key that maps to a modifier that appears
///     on both sides of the keyboard (Command keyCode 55, Option keyCode 58,
///     Shift keyCode 56) → .ambiguousModifier, because both left and right physical
///     keys share this keyCode and these appear in common modifier chords.
public func validateCapture(_ capture: HotkeyCapture) -> HotkeyRecorderWarning? {
    // A zero keyCode with empty flags means we captured nothing useful.
    if capture.keyCode == 0 && capture.modifiers.isEmpty {
        return .unrecognised
    }
    // Generic modifier keys (not side-specific) are high-collision.
    // kVK_Command (55), kVK_Option (58), kVK_Shift (56), kVK_Control (59)
    // appear in virtually every chord and would generate constant false triggers.
    // [decision: Right-Command (54) and Fn (63) are accepted because they are
    //  rare in chords and are the canonical speak bindings, W1.1]
    let ambiguousModifierKeys: Set<Int> = [
        Int(kVK_Command),  // 55 — left ⌘, high-collision
        Int(kVK_Option),   // 58 — left ⌥, high-collision
        Int(kVK_Shift),    // 56 — left ⇧, high-collision
        Int(kVK_Control),  // 59 — left ⌃, high-collision
    ]
    if capture.isModifierOnly && ambiguousModifierKeys.contains(capture.keyCode) {
        return .ambiguousModifier
    }
    return nil
}

// MARK: - RecorderState

private enum RecorderState: Equatable {
    case idle
    case recording
    case captured(HotkeyCapture, HotkeyRecorderWarning?)
    case invalid(String)
}

// MARK: - HotkeyRecorderView

/// A sheet that records a new hotkey binding.
///
/// Presents:
///   - A trigger-mode picker (double-tap vs hold)
///   - A "Start Recording" button that arms the local NSEvent monitor
///   - A live "Press your shortcut…" prompt while recording
///   - A preview of the captured binding via `HotkeyBinding.displayString`
///   - A warning label when the captured combo might false-trigger
///   - Save and Cancel buttons
///
/// On save, calls `onSave(_:)` with the constructed `HotkeyBinding`.
struct HotkeyRecorderView: View {

    /// The binding that was active when the sheet opened (used to pre-populate trigger).
    let initialBinding: HotkeyBinding

    /// Called when the user confirms a new binding. Dismissed by caller.
    let onSave: (HotkeyBinding) -> Void

    /// Called when the user cancels.
    let onCancel: () -> Void

    // MARK: - State

    @State private var recorderState: RecorderState = .idle
    @State private var selectedTrigger: HotkeyBinding.Trigger = .doubleTap
    @State private var eventMonitor: Any?

    // MARK: - Init

    init(
        initialBinding: HotkeyBinding,
        onSave: @escaping (HotkeyBinding) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.initialBinding = initialBinding
        self.onSave = onSave
        self.onCancel = onCancel
        // Seed trigger state from the existing binding so the user sees the current
        // mode pre-selected. [decision: preserve trigger on recorder open, W1.1]
        _selectedTrigger = State(initialValue: initialBinding.trigger)
    }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: SpeakSpacing.md) {

            // Title
            Text("Record Shortcut")
                .font(.headline)
                .padding(.bottom, SpeakSpacing.xs)

            // Trigger mode picker
            Picker("Activation Mode", selection: $selectedTrigger) {
                Text("Double-tap (toggle)").tag(HotkeyBinding.Trigger.doubleTap)
                Text("Hold (push-to-talk)").tag(HotkeyBinding.Trigger.hold)
            }
            .pickerStyle(.inline)
            .padding(.bottom, SpeakSpacing.xs)

            Divider()

            // Recording area
            recordingArea

            Divider()

            // Warning label (shown only when there is a warning)
            if case .captured(_, let warning?) = recorderState {
                warningLabel(for: warning)
            }

            // Action row
            HStack {
                Button("Cancel") {
                    stopMonitor()
                    onCancel()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                if case .captured = recorderState {
                    Button("Re-record") {
                        recorderState = .idle
                        stopMonitor()
                    }
                }

                Button("Save") {
                    commitSave()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canSave)
            }
        }
        .padding(SpeakSpacing.lg)
        .frame(minWidth: 400, minHeight: 260) // [decision: fits preview at default text size, W1.1]
        .onDisappear {
            stopMonitor()
        }
    }

    // MARK: - Recording area

    @ViewBuilder
    private var recordingArea: some View {
        switch recorderState {

        case .idle:
            VStack(spacing: SpeakSpacing.sm) {
                Button("Start Recording") {
                    startMonitor()
                }
                .buttonStyle(.borderedProminent)
                Text("Press Start, then press your desired shortcut.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)

        case .recording:
            VStack(spacing: SpeakSpacing.sm) {
                Text("Press your shortcut\u{2026}")
                    .font(.speakMonoBody)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)

                // Pulsing indicator
                Image(systemName: "record.circle")
                    .foregroundStyle(.red)
                    .imageScale(.large)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, SpeakSpacing.sm)
            .background(
                RoundedRectangle(cornerRadius: 8) // [decision: matches keycap radius, W1.1]
                    .fill(Color.speakSurface)
            )

        case .captured(let capture, _):
            let preview = bindingFromCapture(capture, trigger: selectedTrigger)
            VStack(spacing: SpeakSpacing.sm) {
                Text("Captured:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(preview.displayString)
                    .font(.speakMonoBody)
                    .foregroundStyle(.primary)
                    .padding(.horizontal, SpeakSpacing.sm)
                    .padding(.vertical, SpeakSpacing.xs)
                    .background(
                        RoundedRectangle(cornerRadius: 8) // [decision: keycap radius, W1.1]
                            .fill(Color.speakSurface)
                    )
            }
            .frame(maxWidth: .infinity)

        case .invalid(let reason):
            VStack(spacing: SpeakSpacing.sm) {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                Text(reason)
                    .font(.caption)
                    .foregroundStyle(.orange)
                Button("Try Again") {
                    recorderState = .idle
                    stopMonitor()
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Warning label

    @ViewBuilder
    private func warningLabel(for warning: HotkeyRecorderWarning) -> some View {
        HStack(alignment: .top, spacing: SpeakSpacing.sm) {
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(.orange)
                .imageScale(.small)
            Text(warningMessage(for: warning))
                .font(.caption)
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, SpeakSpacing.xs)
    }

    private func warningMessage(for warning: HotkeyRecorderWarning) -> String {
        switch warning {
        case .ambiguousModifier:
            return "This key is used in many common shortcuts and may trigger accidentally. Consider using Right-Command or Fn instead."
        case .unrecognised:
            return "The captured combo was not recognised. Try a different key."
        }
    }

    // MARK: - Helpers

    private var canSave: Bool {
        if case .captured = recorderState { return true }
        return false
    }

    private func commitSave() {
        guard case .captured(let capture, _) = recorderState else { return }
        stopMonitor()
        let binding = bindingFromCapture(capture, trigger: selectedTrigger)
        onSave(binding)
    }

    // MARK: - NSEvent local monitor

    /// Arm the local NSEvent monitor. In-window only — no permission needed.
    /// [verified: NSEvent.addLocalMonitorForEvents is in-window only, AppKit docs, 2026-06-22]
    private func startMonitor() {
        stopMonitor()
        recorderState = .recording

        eventMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.keyDown, .flagsChanged]
        ) { [self] event in
            handleEvent(event)
            // Swallow the event so it doesn't propagate to buttons etc. while recording.
            // This is correct — we want the raw key, not its action.
            return nil
        }
    }

    private func stopMonitor() {
        if let token = eventMonitor {
            NSEvent.removeMonitor(token)
            eventMonitor = nil
        }
    }

    /// Handle an event from the local monitor.
    /// Called on the main thread (AppKit local monitor delivery guarantee).
    private func handleEvent(_ event: NSEvent) {
        guard case .recording = recorderState else { return }

        // Escape = cancel recording without saving
        if event.type == .keyDown && event.keyCode == UInt16(kVK_Escape) {
            recorderState = .idle
            stopMonitor()
            return
        }

        // Return = confirm if already captured (keyboard shortcut ergonomics)
        if event.type == .keyDown && event.keyCode == UInt16(kVK_Return) {
            return // let the Save button's .defaultAction handle it
        }

        let cgFlags = CGEventFlags(rawValue: UInt64(event.modifierFlags.rawValue))

        switch event.type {

        case .flagsChanged:
            // Modifier-only keys (Right-Command, Fn, etc.) — detect press edge.
            // NSEvent.keyCode is the Carbon key code of the modifier that changed.
            // We only accept a press edge (key going DOWN). To detect the edge we
            // check whether the modifier's bit is now SET. For Right-Command (54),
            // the relevant bit is .maskCommand; for Fn (63), .maskSecondaryFn.
            // [decision: press-edge detection mirrors HotkeyMonitor.handle(), W1.1]
            let kc = Int(event.keyCode)

            // Is the modifier going DOWN? Check the specific mask.
            let modMask = nsModifierMask(forKeyCode: kc)
            guard event.modifierFlags.contains(modMask) else {
                // Key is going up — ignore (we only record the press edge).
                return
            }

            guard let capture = captureFromFlagsChanged(keyCode: kc, cgFlags: cgFlags) else {
                // Unsupported modifier key
                recorderState = .invalid("That modifier key is not supported as a standalone hotkey. Try Right-Command or Fn.")
                stopMonitor()
                return
            }

            let warning = validateCapture(capture)
            recorderState = .captured(capture, warning)
            stopMonitor()

        case .keyDown:
            let kc = Int(event.keyCode)
            let nsFlags = event.modifierFlags

            guard let capture = captureFromKeyDown(keyCode: kc, nsModifiers: nsFlags, cgFlags: cgFlags) else {
                // Bare key with no modifier — not usable as a global hotkey
                recorderState = .invalid("Add a modifier key (⌘, ⌥, ⌃, or ⇧) to use this key as a shortcut.")
                stopMonitor()
                return
            }

            let warning = validateCapture(capture)
            recorderState = .captured(capture, warning)
            stopMonitor()

        default:
            break
        }
    }
}

// MARK: - NSEvent modifier mapping

/// Map a Carbon key code to the NSEvent.ModifierFlags bit that indicates whether
/// that specific key is currently pressed.
///
/// This is used to detect the press edge for modifier-only keys in .flagsChanged events:
/// a .flagsChanged event fires on both press and release, so we check whether the
/// relevant flag bit is now SET to distinguish the two.
///
/// Only the keys in `captureFromFlagsChanged` need a non-nil mapping — others are
/// rejected before this is called.
private func nsModifierMask(forKeyCode keyCode: Int) -> NSEvent.ModifierFlags {
    switch keyCode {
    case Int(kVK_RightCommand), Int(kVK_Command):  return .command
    case Int(kVK_Function):                         return .function
    case Int(kVK_RightOption), Int(kVK_Option):    return .option
    case Int(kVK_Shift), Int(kVK_RightShift):      return .shift
    case Int(kVK_Control), Int(kVK_RightControl):  return .control
    default:                                        return []
    }
}
