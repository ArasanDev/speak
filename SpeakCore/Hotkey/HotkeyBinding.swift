// SpeakCore/Hotkey/HotkeyBinding.swift
//
// HotkeyEvent and HotkeyBinding — the event type and binding model for the
// global hotkey monitor (architecture.md §6, roadmap P5).
//
// Moved from HotkeyMonitor.swift (pure-data seam; no CGEventTap dependency).

import Foundation
import CoreGraphics
import Carbon.HIToolbox

// MARK: - HotkeyEvent

/// The two events the hotkey monitor can emit (architecture.md §6).
public enum HotkeyEvent: Sendable {
    case startCapture
    case stopCapture
}

// MARK: - HotkeyBinding

/// A binding that maps a key + modifiers + trigger style to hotkey events.
/// Custom Codable because CGEventFlags is a OptionSet over UInt64 and does not
/// synthesize Codable on its own.
public struct HotkeyBinding: Codable, Sendable {

    /// How the hotkey activates dictation.
    ///
    /// - `doubleTap`: double-tap Fn (toggle) — the default. Two presses within
    ///   `doubleTapWindow` start a hands-free session; the next single press stops it.
    ///   Implemented by `DoubleTapDetector`.
    /// - `hold`: push-to-talk. Fn press → startCapture; Fn release → stopCapture.
    ///   No minimum-hold guard in Phase B [decision: an accidental short tap yields a
    ///   near-empty recording — acceptable; a min-hold timer can come in a later phase].
    ///   Implemented by `holdEdge(isFnDown:wasDown:)`.
    ///
    /// `.singleTapToggle` was planned but never implemented; it was removed in Phase B
    /// to keep the enum honest. Persisted payloads containing it decode to `nil` (via
    /// `try?` in `UserDefaultsBindingStore.load()`) and fall back to the default binding.
    public enum Trigger: String, Codable, Sendable {
        case doubleTap
        case hold
    }

    public let keyCode: Int
    public let modifiers: CGEventFlags
    public let trigger: Trigger
    /// Default 0.4 s — benchmark.md §7 [decision]; tune empirically at P13.
    public let doubleTapWindow: TimeInterval

    public init(
        keyCode: Int,
        modifiers: CGEventFlags,
        trigger: Trigger,
        doubleTapWindow: TimeInterval
    ) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.trigger = trigger
        self.doubleTapWindow = doubleTapWindow
    }

    // MARK: Codable — manual implementation for CGEventFlags

    private enum CodingKeys: String, CodingKey {
        case keyCode, modifiersRawValue, trigger, doubleTapWindow
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        keyCode = try container.decode(Int.self, forKey: .keyCode)
        let raw = try container.decode(UInt64.self, forKey: .modifiersRawValue)
        modifiers = CGEventFlags(rawValue: raw)
        trigger = try container.decode(Trigger.self, forKey: .trigger)
        doubleTapWindow = try container.decode(TimeInterval.self, forKey: .doubleTapWindow)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(keyCode, forKey: .keyCode)
        try container.encode(modifiers.rawValue, forKey: .modifiersRawValue)
        try container.encode(trigger, forKey: .trigger)
        try container.encode(doubleTapWindow, forKey: .doubleTapWindow)
    }
}

extension HotkeyBinding {
    /// The default binding: double-tap Fn → start, next single-tap Fn → stop.
    /// kVK_Function = 0x3F = 63 (Carbon/HIToolbox) [verified].
    /// Window = 0.4 s (benchmark.md §7 [decision]).
    public static let defaultBinding = HotkeyBinding(
        keyCode: Int(kVK_Function), // 0x3F = 63 [verified]
        modifiers: [],
        trigger: .doubleTap,
        doubleTapWindow: 0.4 // benchmark.md §7 [decision]; tune at P13
    )

    /// Return a new binding identical to `self` but with a different trigger.
    /// Used by `DictationController` to apply a `SettingsStore.triggerMode` change
    /// without losing the user's configured key, modifiers, or window.
    public func with(trigger newTrigger: Trigger) -> HotkeyBinding {
        HotkeyBinding(
            keyCode: keyCode,
            modifiers: modifiers,
            trigger: newTrigger,
            doubleTapWindow: doubleTapWindow
        )
    }
}
