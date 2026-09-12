// SpeakCore/Feedback/DictationFeedback.swift
//
// Sensory confirmation for dictation engage/release — the Settings ▸ Hotkeys
// "Feedback" card wires these to `SettingsStore.dictationFeedbackSounds` /
// `dictationFeedbackHaptics`, and `DictationController` fires them on the
// menubar-icon state edges (`.listening` entry/exit).
//
// - Sounds: bundled macOS system sounds ("Tink" on engage, "Pop" on release)
//   via `NSSound` — short, non-looping, zero-asset. [decision: Tink/Pop — the
//   lightest pair in /System/Library/Sounds; a chime per edge is the standard
//   dictation-tool cue (Wispr/Superwhisper both ship one)]
// - Haptics: `NSHapticFeedbackManager` `.generic` — a single subtle trackpad
//   click on Macs with a Force Touch trackpad; a no-op elsewhere.
//
// `@MainActor` throughout: NSSound and NSHapticFeedbackPerformer are AppKit
// objects; the only call site (DictationController.icon didSet) is already
// main-actor-isolated, so marking the entry point keeps the contract explicit
// rather than relying on a caller convention.

import AppKit
import Foundation

// MARK: - DictationFeedbackEvent

public enum DictationFeedbackEvent: Sendable {
    /// Dictation engaged — session entered `.listening`.
    case engaged
    /// Dictation released — session left `.listening` (stop/processing/error).
    case released
    /// Input device switched mid-dictation (system default input changed while
    /// `.listening` — e.g. a USB headset grabbed the default, or the active mic
    /// was unplugged and macOS fell back). A distinct neutral tick so the user
    /// knows the mic source changed under them — the standard "you can feel it"
    /// route-change cue.
    case routeChanged
}

// MARK: - DictationFeedback

public enum DictationFeedback {

    /// Fire the enabled feedback channels for `event`. Both flags are read by
    /// the caller from `SettingsStore` at edge time so a Settings toggle applies
    /// on the very next press.
    @MainActor
    public static func play(
        _ event: DictationFeedbackEvent,
        soundsEnabled: Bool,
        hapticsEnabled: Bool
    ) {
        if soundsEnabled {
            sound(for: event)?.play()
        }
        if hapticsEnabled {
            NSHapticFeedbackManager.defaultPerformer.perform(
                .generic,
                performanceTime: .now
            )
        }
    }

    /// The system sound for an event. `nil` when the sound name is absent
    /// (nonstandard OS image) — the edge is then haptic-only or silent.
    static func sound(for event: DictationFeedbackEvent) -> NSSound? {
        switch event {
        case .engaged: return NSSound(named: NSSound.Name("Tink"))
        case .released: return NSSound(named: NSSound.Name("Pop"))
        case .routeChanged: return NSSound(named: NSSound.Name("Morse"))
        }
    }
}
