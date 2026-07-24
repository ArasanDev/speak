// SpeakCore/Hotkey/HotkeyBinding.swift
//
// HotkeyEvent and HotkeyBinding — the event type and binding model for the
// global hotkey monitor (architecture.md §6, roadmap P5).
//
// Moved from HotkeyMonitor.swift (pure-data seam; no CGEventTap dependency).

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
    public static let defaultBinding = HotkeyBinding(
        keyCode: Int(kVK_RightCommand),
        modifiers: [],
        trigger: .doubleTap,
        doubleTapWindow: 0.5
    )

    /// Fn binding (selectable): double-tap Fn → start, next single-tap → stop.
    public static let fnBinding = HotkeyBinding(
        keyCode: Int(kVK_Function),
        modifiers: [],
        trigger: .doubleTap,
        doubleTapWindow: 0.5
    )

    // MARK: - Display helpers

    /// Whether this binding uses a standalone modifier key.
    public var isModifierOnly: Bool {
        isModifierOnlyKey(keyCode)
    }

    /// The primary key symbol for this binding, rendered as a short keycap label.
    public var keySymbol: String {
        symbolForKeyCode(keyCode)
    }

    /// The list of modifier symbols for this binding (in ⌃ ⌥ ⇧ ⌘ order).
    public var modifierSymbols: [String] {
        var result: [String] = []
        if modifiers.contains(.maskControl) { result.append("⌃") }
        if modifiers.contains(.maskAlternate) { result.append("⌥") }
        if modifiers.contains(.maskShift) { result.append("⇧") }
        if modifiers.contains(.maskCommand) { result.append("⌘") }
        return result
    }

    /// The list of keycap labels representing the hotkey visually.
    public var keycapLabels: [String] {
        if isModifierOnly {
            let sym = keySymbol
            return trigger == .doubleTap ? [sym, sym] : [sym]
        } else {
            var labels = modifierSymbols
            labels.append(keySymbol)
            return labels
        }
    }

    /// A human-readable label describing the full binding gesture.
    public var displayString: String {
        switch keyCode {
        case Int(kVK_Function):
            return trigger == .doubleTap ? "Fn ×2" : "Fn (hold)"

        case Int(kVK_RightCommand):
            return trigger == .doubleTap ? "⌘⌘ Right Command" : "⌘ Right Command (hold)"

        case Int(kVK_Command):
            return trigger == .doubleTap ? "⌘⌘ Command" : "⌘ Command (hold)"

        case Int(kVK_RightOption):
            return trigger == .doubleTap ? "⌥⌥ Right Option" : "⌥ Right Option (hold)"

        case Int(kVK_Option):
            return trigger == .doubleTap ? "⌥⌥ Option" : "⌥ Option (hold)"

        case Int(kVK_RightControl):
            return trigger == .doubleTap ? "⌃⌃ Right Control" : "⌃ Right Control (hold)"

        case Int(kVK_Control):
            return trigger == .doubleTap ? "⌃⌃ Control" : "⌃ Control (hold)"

        case Int(kVK_RightShift):
            return trigger == .doubleTap ? "⇧⇧ Right Shift" : "⇧ Shift (hold)"

        case Int(kVK_Shift):
            return trigger == .doubleTap ? "⇧⇧ Shift" : "⇧ Shift (hold)"

        default:
            let modStr = modifierSymbols.joined()
            let sym = keySymbol
            let combo = modStr + sym
            return trigger == .hold ? "\(combo) (hold)" : combo
        }
    }

    /// Return a new binding identical to `self` but with a different trigger.
    public func with(trigger newTrigger: Trigger) -> HotkeyBinding {
        HotkeyBinding(
            keyCode: keyCode,
            modifiers: modifiers,
            trigger: newTrigger,
            doubleTapWindow: doubleTapWindow
        )
    }
}

private let keyCodeSymbolMap: [Int: String] = [
    Int(kVK_Function): "Fn",
    Int(kVK_RightCommand): "⌘",
    Int(kVK_Command): "⌘",
    Int(kVK_RightOption): "⌥",
    Int(kVK_Option): "⌥",
    Int(kVK_RightControl): "⌃",
    Int(kVK_Control): "⌃",
    Int(kVK_RightShift): "⇧",
    Int(kVK_Shift): "⇧",
    Int(kVK_Space): "Space",
    Int(kVK_Return): "Return",
    Int(kVK_Tab): "Tab",
    Int(kVK_Delete): "Delete",
    Int(kVK_Escape): "Esc",
    Int(kVK_UpArrow): "↑",
    Int(kVK_DownArrow): "↓",
    Int(kVK_LeftArrow): "←",
    Int(kVK_RightArrow): "→",
    0: "A",
    1: "S",
    2: "D",
    3: "F",
    4: "H",
    5: "G",
    6: "Z",
    7: "X",
    8: "C",
    9: "V",
    11: "B",
    12: "Q",
    13: "W",
    14: "E",
    15: "R",
    16: "Y",
    17: "T",
    18: "1",
    19: "2",
    20: "3",
    21: "4",
    22: "6",
    23: "5",
    24: "=",
    25: "9",
    26: "7",
    27: "-",
    28: "8",
    29: "0",
    30: "]",
    31: "O",
    32: "U",
    33: "[",
    34: "I",
    35: "P",
    37: "L",
    38: "J",
    39: "'",
    40: "K",
    41: ";",
    42: "\\",
    43: ",",
    44: "/",
    45: "N",
    46: "M",
    47: ".",
    50: "`",
    122: "F1",
    120: "F2",
    99: "F3",
    118: "F4",
    96: "F5",
    97: "F6",
    98: "F7",
    100: "F8",
    101: "F9",
    109: "F10",
    103: "F11",
    111: "F12"
]

/// Helper function to map a key code to a printable key symbol.
public func symbolForKeyCode(_ keyCode: Int) -> String {
    keyCodeSymbolMap[keyCode] ?? "Key \(keyCode)"
}

/// Helper function to check whether a key code represents a standalone modifier.
public func isModifierOnlyKey(_ keyCode: Int) -> Bool {
    switch keyCode {
    case Int(kVK_Function),
         Int(kVK_RightCommand), Int(kVK_Command),
         Int(kVK_RightOption), Int(kVK_Option),
         Int(kVK_RightShift), Int(kVK_Shift),
         Int(kVK_RightControl), Int(kVK_Control):
        return true
    default:
        return false
    }
}
