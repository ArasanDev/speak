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

/// Helper function to map a key code to a printable key symbol.
public func symbolForKeyCode(_ keyCode: Int) -> String {
    switch keyCode {
    case Int(kVK_Function):                         return "Fn"
    case Int(kVK_RightCommand), Int(kVK_Command): return "⌘"
    case Int(kVK_RightOption), Int(kVK_Option):    return "⌥"
    case Int(kVK_RightControl), Int(kVK_Control):  return "⌃"
    case Int(kVK_RightShift), Int(kVK_Shift):      return "⇧"
    case Int(kVK_Space):        return "Space"
    case Int(kVK_Return):       return "Return"
    case Int(kVK_Tab):          return "Tab"
    case Int(kVK_Delete):       return "Delete"
    case Int(kVK_Escape):       return "Esc"
    case Int(kVK_UpArrow):      return "↑"
    case Int(kVK_DownArrow):    return "↓"
    case Int(kVK_LeftArrow):    return "←"
    case Int(kVK_RightArrow):   return "→"
    case 0: return "A"
    case 1: return "S"
    case 2: return "D"
    case 3: return "F"
    case 4: return "H"
    case 5: return "G"
    case 6: return "Z"
    case 7: return "X"
    case 8: return "C"
    case 9: return "V"
    case 11: return "B"
    case 12: return "Q"
    case 13: return "W"
    case 14: return "E"
    case 15: return "R"
    case 16: return "Y"
    case 17: return "T"
    case 18: return "1"
    case 19: return "2"
    case 20: return "3"
    case 21: return "4"
    case 22: return "6"
    case 23: return "5"
    case 24: return "="
    case 25: return "9"
    case 26: return "7"
    case 27: return "-"
    case 28: return "8"
    case 29: return "0"
    case 30: return "]"
    case 31: return "O"
    case 32: return "U"
    case 33: return "["
    case 34: return "I"
    case 35: return "P"
    case 37: return "L"
    case 38: return "J"
    case 39: return "'"
    case 40: return "K"
    case 41: return ";"
    case 42: return "\\"
    case 43: return ","
    case 44: return "/"
    case 45: return "N"
    case 46: return "M"
    case 47: return "."
    case 50: return "`"
    case 122: return "F1"
    case 120: return "F2"
    case 99:  return "F3"
    case 118: return "F4"
    case 96:  return "F5"
    case 97:  return "F6"
    case 98:  return "F7"
    case 100: return "F8"
    case 101: return "F9"
    case 109: return "F10"
    case 103: return "F11"
    case 111: return "F12"
    default: return "Key \(keyCode)"
    }
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
