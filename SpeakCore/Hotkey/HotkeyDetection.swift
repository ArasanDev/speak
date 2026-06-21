// SpeakCore/Hotkey/HotkeyDetection.swift
//
// Pure, testable hotkey detection primitives — no CGEventTap dependency.
// Moved from HotkeyMonitor.swift.
//
//   modifierMask(forKeyCode:) — maps a bound key's Carbon keyCode to the
//                               CGEventFlags bit that tracks its down state
//   FnDebouncer              — 40 ms debounce for Fn flagsChanged events
//                              (VoiceInk pattern; filters OS-internal Fn bursts)
//   holdEdge()               — free function for hold-mode (push-to-talk) edge detection
//   DoubleTapDetector        — pure value-type double-tap state machine
//   TapRestartRateLimiter    — rate limiter for CGEventTap re-enable events

import CoreGraphics
import Carbon.HIToolbox
import Foundation

// MARK: - Modifier mask helper

/// Returns the CGEventFlags bit that is SET when the key with `keyCode` is
/// held down, as observed on a `CGEventType.flagsChanged` event.
///
/// Modifier keys never produce keyDown/keyUp — they arrive exclusively as
/// `flagsChanged` events. The *which-key* question is answered by the keyCode
/// field; the *is-key-down* question is answered by a specific bit in
/// `CGEventFlags`. This function centralises that mapping so callers need not
/// hard-code flag values.
///
/// Mapping (verified against macOS 26 SDK via `swiftc -typecheck`, 2026-06-21):
///   kVK_Function (0x3F = 63)  → `.maskSecondaryFn`  (rawValue 8388608)
///   kVK_RightCommand (0x36 = 54) → `.maskCommand`   (rawValue 1048576)
///   kVK_Command (0x37 = 55) [left] → `.maskCommand` (rawValue 1048576)
///   Any other keyCode          → `.maskCommand` (safe fallback; modifier is
///                                unusual for a hotkey binding, so "down when
///                                maskCommand set" is the least-surprising default)
///
/// Left vs Right Command both set `.maskCommand`; they are disambiguated by
/// the keyCode field on the same flagsChanged event — not by a separate flag.
/// [verified: kVK_RightCommand = 54, kVK_Command = 55, swiftc + SDK, 2026-06-21]
public func modifierMask(forKeyCode keyCode: Int) -> CGEventFlags {
    switch keyCode {
    case Int(kVK_Function):     return .maskSecondaryFn  // 0x3F = 63 [verified]
    case Int(kVK_RightCommand): return .maskCommand      // 0x36 = 54 [verified]
    case Int(kVK_Command):      return .maskCommand      // 0x37 = 55 [verified] (left ⌘)
    default:                    return .maskCommand      // safe fallback for future bindings
    }
}

// MARK: - Fn debouncer

/// A pure, testable debouncer for Fn `flagsChanged` events.
///
/// macOS emits a burst of spurious `flagsChanged` events when the Fn/Globe key
/// is pressed for its own dictation feature — these arrive within ~10 ms of
/// each other. VoiceInk (github.com/Beingpax/VoiceInk) filters them with a
/// 40 ms window. We apply the same strategy.
///
/// **Applied on the Fn path only** (keyCode == `kVK_Function`). Right-Command
/// does not trigger the macOS dictation feature and therefore does not produce
/// the spurious burst; the debouncer is a no-op when the binding is
/// Right-Command.
///
/// A debounced event is **dropped**; `lastFnDown` is NOT updated for dropped
/// events, so a dropped press does not advance edge state (no stale-state bug).
///
/// Source: VoiceInk 40 ms debounce [decision: VoiceInk pattern, `benchmark.md §7`].
public struct FnDebouncer: Sendable {
    /// The debounce window in seconds.
    /// 40 ms — VoiceInk pattern [decision: benchmark.md §7].
    public static let debounceWindow: TimeInterval = 0.04  // 40 ms [decision: VoiceInk / benchmark.md §7]

    /// Timestamp of the last event that was PASSED through (not debounced).
    private var lastPassTimestamp: TimeInterval?

    public init() {}

    /// Record an event at `now` (seconds, monotonic).
    /// Returns `true` if the event should be processed, `false` if it should be dropped.
    ///
    /// Only the first event in a burst is passed through; subsequent events
    /// within `debounceWindow` seconds of the last accepted event are dropped.
    public mutating func shouldProcess(now: TimeInterval) -> Bool {
        if let last = lastPassTimestamp, (now - last) < FnDebouncer.debounceWindow {
            return false  // within window of last accepted event — drop
        }
        lastPassTimestamp = now
        return true
    }

    /// Reset the debouncer (e.g. on tap re-arm).
    public mutating func reset() {
        lastPassTimestamp = nil
    }
}

// MARK: - Hold-mode edge detection

/// Pure free function for hold-mode (push-to-talk) edge detection.
/// Extracted for unit-testability — no CGEventTap, no clock dependency.
///
/// - Parameters:
///   - isFnDown: Whether the Fn key is pressed in the current event.
///   - wasDown:  Whether the Fn key was pressed in the previous event.
/// - Returns:
///   - `.startCapture` on the press leading edge (false → true).
///   - `.stopCapture` on the release trailing edge (true → false).
///   - `nil` if neither transition occurred (e.g., key-repeat or no change).
///
/// No minimum-hold guard is applied in Phase B [decision: specs/dictation-flow.md §6-B].
public func holdEdge(isFnDown: Bool, wasDown: Bool) -> HotkeyEvent? {
    switch (wasDown, isFnDown) {
    case (false, true):  return .startCapture   // press leading edge
    case (true, false):  return .stopCapture    // release trailing edge
    default:             return nil             // no transition
    }
}

// MARK: - DoubleTapDetector

/// Pure value-type double-tap state machine. No CGEventTap dependency.
/// Testable by injecting timestamps (no wall-clock, no sleep).
///
/// State:
///   isCapturing == false, lastTapTime == nil  → idle, waiting for first tap
///   isCapturing == false, lastTapTime set     → first tap received; waiting
///                                                for second within window
///   isCapturing == true                       → session active; next tap stops
///
/// Input:  register(tapAt:window:) — feed a Fn press timestamp
/// Output: HotkeyEvent? — non-nil when a state transition should fire
public struct DoubleTapDetector: Sendable {
    /// Timestamp of the most recent Fn press while idle, or nil if none yet.
    private var lastTapTime: TimeInterval?
    /// True once a double-tap has fired and before the stop single-tap.
    private(set) var isCapturing: Bool = false

    public init() {}

    /// Register a Fn key press at a given timestamp (seconds, monotonic).
    /// Returns the HotkeyEvent to emit, or nil if no state transition occurs.
    ///
    /// - Parameters:
    ///   - timestamp: The monotonic timestamp of the Fn press (e.g. from
    ///                CGEvent.timestamp, converted to seconds).
    ///   - window:    The double-tap window (default binding: 0.4 s —
    ///                benchmark.md §7 [decision]).
    public mutating func register(tapAt timestamp: TimeInterval, window: TimeInterval) -> HotkeyEvent? {
        if isCapturing {
            // Already capturing — next single Fn tap → stop
            isCapturing = false
            lastTapTime = nil
            return .stopCapture
        }

        if let prev = lastTapTime, (timestamp - prev) <= window {
            // Second tap within window → start
            isCapturing = true
            lastTapTime = nil
            return .startCapture
        }

        // First tap (or too slow) — record it and wait
        lastTapTime = timestamp
        return nil
    }

    /// Reset to idle state (e.g. after an error or external session cancellation).
    public mutating func reset() {
        isCapturing = false
        lastTapTime = nil
    }
}

// MARK: - Command Mode chord detection

/// The two edges of the Command Mode chord (Wave D): the user holds `Fn`+`Ctrl`, speaks
/// an instruction, and releases. `.begin` fires when both go down; `.end` when either
/// is released.
public enum CommandChordEvent: Sendable, Equatable {
    case begin
    case end
}

/// Pure value-type detector for the `Fn`+`Ctrl` push-to-talk chord. No CGEventTap, no
/// clock — fed `(isFnDown, isCtrlDown)` from the tap callback; returns an edge event or
/// nil. Tracks its own active state so the caller only forwards modifier state.
public struct CommandChordDetector: Sendable {
    /// True while the chord (Fn AND Ctrl) is held.
    private(set) var isActive: Bool = false

    public init() {}

    /// Feed the current modifier state. Returns `.begin` on the both-down leading edge,
    /// `.end` on the trailing edge (either key released), or nil if nothing changed.
    public mutating func update(isFnDown: Bool, isCtrlDown: Bool) -> CommandChordEvent? {
        let nowActive = isFnDown && isCtrlDown
        defer { isActive = nowActive }
        switch (isActive, nowActive) {
        case (false, true): return .begin
        case (true, false): return .end
        default:            return nil
        }
    }

    /// Reset to inactive (e.g. on tap re-arm or external cancel).
    public mutating func reset() {
        isActive = false
    }
}

// MARK: - TapRestartRateLimiter

/// Pure value-type rate limiter for tap restart events.
/// Caps re-enables to `maxRestarts` within `windowSeconds`.
/// Testable with injected timestamps — no wall-clock dependency.
///
/// Derivation: Loop OSS project uses 5 restarts / 2 s as the hot-loop guard.
/// Documented in benchmark.md §7 [decision: Loop pattern].
public struct TapRestartRateLimiter: Sendable {
    /// Maximum restarts within the window. Source: Loop OSS [decision].
    public let maxRestarts: Int
    /// Window duration in seconds. Source: Loop OSS [decision].
    public let windowSeconds: TimeInterval

    private var restartTimestamps: [TimeInterval] = []

    public init(
        maxRestarts: Int = 5,        // Loop OSS [decision]
        windowSeconds: TimeInterval = 2.0  // Loop OSS [decision]
    ) {
        self.maxRestarts = maxRestarts
        self.windowSeconds = windowSeconds
    }

    /// Record a restart attempt at `now` and return whether it is allowed.
    /// Prunes expired entries from the window first.
    public mutating func recordAttempt(now: TimeInterval) -> Bool {
        // Remove entries older than the window.
        restartTimestamps = restartTimestamps.filter { now - $0 < windowSeconds }
        guard restartTimestamps.count < maxRestarts else {
            return false // cap exceeded
        }
        restartTimestamps.append(now)
        return true
    }

    /// Reset the rate limiter (e.g. after a successful arm or on wake).
    public mutating func reset() {
        restartTimestamps = []
    }
}
