// SpeakCore/Hotkey/HotkeyBinding.swift
//
// HotkeyEvent and HotkeyBinding — the event type and binding model for the
// global hotkey monitor (architecture.md §6, roadmap P5).
//
// Moved from HotkeyMonitor.swift (pure-data seam; no CGEventTap dependency).
//
// --- Default binding change (W1.1) ---
// Default is now double-tap Right-Command (keyCode 54) instead of Fn (63).
// Rationale: Fn is contested by macOS system dictation; Right-⌘ is rarely
// used in chords (chord shortcuts use left ⌘); same flagsChanged path, lowest-
// risk change. Fn stays selectable; when selected the 40 ms FnDebouncer
// (HotkeyDetection.swift) filters the OS dictation burst.
// [decision: next-iteration-plan.md §2, 2026-06-21]

import Carbon.HIToolbox
import CoreGraphics
import Foundation

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
    /// The default binding: double-tap Right-Command → start, next single-tap → stop.
    ///
    /// Changed from Fn (kVK_Function = 63) in W1.1 [decision: next-iteration-plan.md §2,
    /// 2026-06-21]. Right-Command (kVK_RightCommand = 54) avoids the macOS system-
    /// dictation conflict; chord shortcuts use the left ⌘, so keycode 54 rarely fires.
    ///
    /// kVK_RightCommand = 0x36 = 54 [verified: swiftc + macOS 26 SDK, 2026-06-21].
    /// Window = 0.4 s (benchmark.md §7 [decision]).
    public static let defaultBinding = HotkeyBinding(
        keyCode: Int(kVK_RightCommand), // 0x36 = 54 [verified: swiftc + SDK, 2026-06-21]
        modifiers: [],
        trigger: .doubleTap,
        doubleTapWindow: 0.4 // benchmark.md §7 [decision]; tune at P13
    )

    /// Fn binding (selectable): double-tap Fn → start, next single-tap → stop.
    /// kVK_Function = 0x3F = 63 [verified: Carbon/HIToolbox].
    /// The FnDebouncer (40 ms) is applied in HotkeyMonitor.handle() when this
    /// binding is active to filter the OS-internal Fn-dictation burst
    /// [decision: VoiceInk pattern, benchmark.md §7].
    public static let fnBinding = HotkeyBinding(
        keyCode: Int(kVK_Function), // 0x3F = 63 [verified]
        modifiers: [],
        trigger: .doubleTap,
        doubleTapWindow: 0.4
    )

    // MARK: - Display helpers

    /// The primary key symbol for this binding, rendered as a short keycap label.
    ///
    /// Used by `DictationController.currentHotkeyCombo()` to build the keycap
    /// array the dashboard and onboarding consume. The onboarding agent reads
    /// this instead of hard-coding "Fn".
    public var keySymbol: String {
        switch keyCode {
        case Int(kVK_Function):     return "Fn"
        case Int(kVK_RightCommand): return "⌘"    // right ⌘ keycap
        case Int(kVK_Command):      return "⌘"    // left ⌘ keycap
        default:                    return "⌘"    // fallback
        }
    }

    /// A human-readable label describing the full binding gesture.
    ///
    /// Examples:
    ///   double-tap Right-Command  → "⌘⌘ Right Command"
    ///   double-tap Fn             → "Fn ×2"
    ///   hold Right-Command        → "⌘ Right Command (hold)"
    ///   hold Fn                   → "Fn (hold)"
    ///
    /// For Fn, `keySymbol` equals `keyName` ("Fn"), so the hold format uses
    /// `keyName` directly (not `"\(keySymbol) \(keyName) (hold)"` which would
    /// produce "Fn Fn (hold)").
    ///
    /// Consumed by onboarding/settings agents instead of hard-coding "Fn".
    public var displayString: String {
        switch keyCode {
        case Int(kVK_Function):
            // Fn is its own symbol; avoid "Fn Fn ×2" or "Fn Fn (hold)".
            return trigger == .doubleTap ? "Fn ×2" : "Fn (hold)"

        case Int(kVK_RightCommand):
            return trigger == .doubleTap ? "⌘⌘ Right Command" : "⌘ Right Command (hold)"

        case Int(kVK_Command):
            return trigger == .doubleTap ? "⌘⌘ Command" : "⌘ Command (hold)"

        default:
            let sym = keySymbol
            return trigger == .doubleTap ? "\(sym)\(sym) Key \(keyCode)" : "\(sym) Key \(keyCode) (hold)"
        }
    }

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
