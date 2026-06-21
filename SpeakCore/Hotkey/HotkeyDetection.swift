// SpeakCore/Hotkey/HotkeyDetection.swift
//
// Pure, testable hotkey detection primitives — no CGEventTap dependency.
// Moved from HotkeyMonitor.swift.
//
//   holdEdge()          — free function for hold-mode (push-to-talk) edge detection
//   DoubleTapDetector   — pure value-type double-tap state machine
//   TapRestartRateLimiter — rate limiter for CGEventTap re-enable events

import Foundation

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
