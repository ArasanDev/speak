// SpeakCore/Hotkey/ExtraBinding.swift
//
// Multiple hotkey bindings per action (v0.1 task V01-5, roadmap V01-5).
//
// This is ADDITIVE to the existing primary `HotkeyBinding` (double-tap / hold
// toggle, HotkeyBinding.swift) — it does not replace it. The primary binding
// remains the default toggle gesture. `ExtraBinding`s are independent,
// direct-fire shortcuts: pressing the bound input immediately fires the mapped
// action (`.activate` or `.stop`), no double-tap window, no release edge.
//
// Up to `ExtraBindingSet.maxPerAction` (4) bindings are allowed per action
// [decision: V01-5 task spec, 2026-07-06].
//
// --- Input sources ---
// `.modifierKey(keyCode)` — a modifier key (Fn/⌘/⌥, same set the existing
//   recorder supports — see HotkeyRecorderView.supportedModifierKeys). Modifier
//   keys arrive exclusively as CGEventType.flagsChanged, already in HotkeyMonitor's
//   event mask — no new permission surface. [decision: advisor guidance, avoid
//   keyDown/keyUp entirely — that observation shape is the classic Input-
//   Monitoring TCC tripwire, and IM was deliberately removed from v0 (see
//   project_im_removal memory).]
// `.mouseButton(buttonNumber)` — CGEvent's `.mouseEventButtonNumber` field on an
//   `.otherMouseDown` event. Restricted to 4...10 per the task spec (buttons 0-2
//   are the primary/secondary/middle click and are never observed here).
//
// --- Matching model ---
// Pure, testable, no CGEventTap dependency — mirrors DoubleTapDetector's shape.
// `ExtraBindingSet.action(for:)` is a simple dictionary-style lookup: at most one
// binding may exist per (source) — enforced by `adding(_:)`.

import Carbon.HIToolbox
import Foundation

// MARK: - ExtraBindingSource

/// The input that triggers an `ExtraBinding`.
public enum ExtraBindingSource: Codable, Sendable, Equatable, Hashable {
    /// A modifier keyCode (Carbon.HIToolbox), observed via CGEventType.flagsChanged.
    /// Must be one of the keys `modifierMask(forKeyCode:)` recognizes (Fn, ⌘, ⌥ —
    /// left or right variant) or the binding fails closed (never fires) — same
    /// fail-closed behavior as the primary binding's `modifierMask` sentinel.
    case modifierKey(Int)
    /// A mouse button number (CGEvent `.mouseEventButtonNumber`), restricted to
    /// 4...10 [decision: V01-5 task spec — buttons 0-2 are primary/secondary/
    /// middle click and are never bindable].
    case mouseButton(Int)

    /// Whether this source is a mouse button in the supported 4...10 range.
    public var isValidMouseButton: Bool {
        if case .mouseButton(let n) = self {
            return ExtraBindingSet.mouseButtonRange.contains(n)
        }
        return false
    }

    /// True for any `.mouseButton` case, valid range or not — used by
    /// `HotkeyMonitor` to decide whether the tap needs `otherMouseDown` in its
    /// event mask.
    public var isMouseButton: Bool {
        if case .mouseButton = self { return true }
        return false
    }
}

// MARK: - HotkeyAction

/// The dictation action an `ExtraBinding` fires. Distinct from `HotkeyEvent`
/// (which is the tap's output type) so the binding model does not need to know
/// about `HotkeyEvent` naming — `HotkeyMonitor` maps `.activate` → `.startCapture`
/// and `.stop` → `.stopCapture` at dispatch time.
public enum HotkeyAction: String, Codable, Sendable, CaseIterable, Equatable {
    case activate
    case stop
}

// MARK: - ExtraBinding

/// One user-configured extra hotkey: a single input source mapped to a single
/// action. `id` is stable across edits so the Settings UI can diff/remove rows.
public struct ExtraBinding: Codable, Sendable, Equatable, Identifiable {
    public let id: UUID
    public let source: ExtraBindingSource
    public let action: HotkeyAction

    public init(id: UUID = UUID(), source: ExtraBindingSource, action: HotkeyAction) {
        self.id = id
        self.source = source
        self.action = action
    }
}

// MARK: - ExtraBindingSet

/// The full collection of extra bindings, persisted as one unit.
/// Enforces: at most `maxPerAction` bindings per action, and at most one
/// binding per (source) — a given key/button can only map to a single action.
public struct ExtraBindingSet: Codable, Sendable, Equatable {
    /// Maximum bindings allowed per action. [decision: V01-5 task spec, 2026-07-06]
    public static let maxPerAction = 4

    /// The supported mouse-button-number range. [decision: V01-5 task spec —
    /// "mouse buttons 4-10"; 0-2 are primary/secondary/middle click.]
    public static let mouseButtonRange = 4...10

    public static let empty = ExtraBindingSet(bindings: [])

    public private(set) var bindings: [ExtraBinding]

    public init(bindings: [ExtraBinding] = []) {
        self.bindings = bindings
    }

    /// Bindings mapped to `.activate`.
    public var activateBindings: [ExtraBinding] {
        bindings.filter { $0.action == .activate }
    }

    /// Bindings mapped to `.stop`.
    public var stopBindings: [ExtraBinding] {
        bindings.filter { $0.action == .stop }
    }

    /// Whether at least one binding targets a mouse button — `HotkeyMonitor`
    /// uses this to decide whether `otherMouseDown` belongs in the tap's mask.
    public var hasMouseBinding: Bool {
        bindings.contains { $0.source.isMouseButton }
    }

    /// Attempt to add a binding. Returns the new set on success, or `nil` if the
    /// binding is rejected:
    ///   - a mouse button outside `mouseButtonRange`,
    ///   - the action already has `maxPerAction` bindings,
    ///   - the same `source` is already bound (to any action).
    public func adding(_ binding: ExtraBinding) -> ExtraBindingSet? {
        if case .mouseButton = binding.source, !binding.source.isValidMouseButton {
            return nil
        }
        guard bindings.filter({ $0.action == binding.action }).count < Self.maxPerAction else {
            return nil
        }
        guard !bindings.contains(where: { $0.source == binding.source }) else {
            return nil
        }
        var updated = bindings
        updated.append(binding)
        return ExtraBindingSet(bindings: updated)
    }

    /// Remove a binding by id. No-op (returns an equal set) if the id is absent.
    public func removing(id: UUID) -> ExtraBindingSet {
        ExtraBindingSet(bindings: bindings.filter { $0.id != id })
    }

    /// Pure lookup: does any binding match this source, and if so which action?
    /// At most one binding exists per source (enforced by `adding(_:)`), so the
    /// first match is the only match.
    public func action(for source: ExtraBindingSource) -> HotkeyAction? {
        bindings.first(where: { $0.source == source })?.action
    }
}

// MARK: - Display helpers

extension ExtraBindingSource {
    /// A short, human-readable label for the Settings editor. Mirrors
    /// `HotkeyBinding.keySymbol`'s key-name mapping for the modifier-key cases.
    public var displayString: String {
        switch self {
        case .modifierKey(let keyCode):
            switch keyCode {
            case Int(kVK_Function):     return "Fn"
            case Int(kVK_RightCommand): return "Right ⌘"
            case Int(kVK_Command):      return "⌘"
            case Int(kVK_RightOption):  return "Right ⌥"
            case Int(kVK_Option):       return "⌥"
            default:                    return "Key \(keyCode)"
            }
        case .mouseButton(let number):
            return "Mouse Button \(number)"
        }
    }
}

extension HotkeyAction {
    /// A human-readable label for the Settings editor.
    public var displayString: String {
        switch self {
        case .activate: return "Start Dictation"
        case .stop:     return "Stop Dictation"
        }
    }
}
