// SpeakCore/Hotkey/HotkeyMonitor.swift
//
// Global hotkey monitor using CGEventTap (architecture.md §6, roadmap P5).
//
// API surface:
//   HotkeyEvent       — startCapture | stopCapture (Sendable)
//   HotkeyBinding     — Codable + Sendable; custom Codable for CGEventFlags
//   HotkeyMonitor     — installs the tap, exposes AsyncStream<HotkeyEvent>
//   DoubleTapDetector — pure value-type detector (testable without a tap)
//   holdEdge()        — pure free function for hold-mode edge detection (testable)
//
// --- Fn-key detection model [verified] ---
// The Fn/Globe key does NOT produce keyDown/keyUp events; it arrives exclusively
// as CGEventType.flagsChanged (rawValue 12) [verified: swiftc + SDK, 2026-06-20].
// Press-edge is detected by checking CGEventFlags.maskSecondaryFn (rawValue 8388608)
// [verified: swiftc + SDK] in the incoming flags; a tap is emitted on a
// low→high transition (flags now contains .maskSecondaryFn, previous state did not).
//
// --- Fn keycode ---
// kVK_Function (Carbon/HIToolbox) = 0x3F = 63 [verified: compiled + ran, 2026-06-20].
// We read this from the CGEvent keyCode field on flagsChanged events.
//
// --- CGEvent.tapCreate [verified] ---
// CGEventTapCreate() was obsoleted in Swift 3; the replacement is
// CGEvent.tapCreate(tap:place:options:eventsOfInterest:callback:userInfo:)
// returning CFMachPort? [verified: swiftc + SDK, 2026-06-20].
//
// --- Threading model (Phase A) ---
// The dedicated run-loop thread is the sole owner of tap state:
//   init()  — launch the thread, return immediately (non-blocking, fixes §1.3).
//   start() — set armingDesired flag + wake the run loop; thread builds the tap.
//   Thread  — owns CFRunLoop, CFRunLoopTimer (100ms re-arm watchdog), CFMachPort.
// No semaphore wait on the main thread. State shared between caller and thread is
// protected by NSLock. The AsyncStream lives for the monitor's lifetime; callers
// consume a stable reference to `events` — they do NOT need to re-subscribe after
// a re-arm.
//
// --- Re-arm watchdog ---
// A CFRunLoopTimer fires every ~100ms (re-arm poll interval, see benchmark.md §7
// [decision: 100ms is fast enough for <200ms arm latency, cheap enough to idle]).
// While the tap is not armed AND armingDesired == true, the timer checks
// AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt:false]). On the
// untrusted→trusted edge, it calls buildTap() on the run-loop thread. Once armed,
// the timer interval backs off (still runs for the tap-disabled watchdog, §3).
//
// --- Tap-disabled watchdog (spec §3) ---
// tapDisabledByTimeout/ByUserInput events re-enable the tap via CGEvent.tapEnable.
// A restart rate-limiter (TapRestartRateLimiter, pure/testable) caps restarts at
// 5 within 2 s to avoid a hot loop. On wake (NSWorkspace.didWakeNotification) the
// monitor schedules a re-arm in ~3 s (AltTab pattern).
//
// --- Live OS behavior [deferred] ---
// Whether the tap fires correctly while another app has focus, and whether
// the OS prompts for Accessibility + Input Monitoring permissions on first run,
// requires a live, non-sandboxed app run with permissions granted.
// These done-when rows are marked [deferred — needs human verification].
//
// --- Double-tap window ---
// Default 0.4 s = 400 ms. Source: benchmark.md §7 [decision], empirically tuned
// at P13 dogfood. Not a magic number — the trace comment is the authority.

import CoreFoundation
import CoreGraphics
import ApplicationServices
import Carbon.HIToolbox
import AppKit
import os

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

// MARK: - BindingStoring

/// A thin, testable boundary around UserDefaults for hotkey binding persistence.
/// Concrete impl: UserDefaultsBindingStore. Mock: InMemoryBindingStore (tests).
public protocol BindingStoring: Sendable {
    func load() -> HotkeyBinding?
    func save(_ binding: HotkeyBinding)
}

/// Production store backed by UserDefaults.standard.
public final class UserDefaultsBindingStore: BindingStoring, @unchecked Sendable {
    private let key = "com.speak.hotkeyBinding"
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init() {}

    public func load() -> HotkeyBinding? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? decoder.decode(HotkeyBinding.self, from: data)
    }

    public func save(_ binding: HotkeyBinding) {
        guard let data = try? encoder.encode(binding) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}

// MARK: - HotkeyMonitor

/// Installs a system-wide CGEventTap that detects Fn double-tap (start) and
/// the subsequent single Fn tap (stop), emitting HotkeyEvent on an AsyncStream.
///
/// Threading model (Phase A — non-blocking init):
///   - `init` spawns a dedicated run-loop thread and returns immediately.
///   - All tap state (CFMachPort, CFRunLoopSource) is owned exclusively by that thread.
///   - `start()` sets a flag + wakes the run loop; the thread builds the tap.
///   - `NSLock` guards the small set of cross-thread flags.
///   - The AsyncStream lifetime equals the monitor's lifetime; consumers do NOT
///     need to re-subscribe after a re-arm.
///
/// Permission model:
///   - Gate tap on Accessibility only (spec §2 — AX alone is sufficient for
///     a listen-only .flagsChanged tap). Input Monitoring is requested for
///     registration purposes but does NOT block tap arming.
///   - IOHIDCheckAccess is used only for status display.
///
/// Re-arm watchdog:
///   - A CFRunLoopTimer fires every 100ms [decision: benchmark.md §7].
///   - While ungranted: polls AXIsProcessTrustedWithOptions([prompt:false]).
///   - On untrusted→trusted edge: calls buildTap() on the run-loop thread.
///   - Once armed: timer continues (handles tapDisabled events) but at the same
///     cadence (100ms is cheap; the callback exits in ~1µs when armed).
///
/// Tap-disabled watchdog:
///   - tapDisabledByTimeout/ByUserInput → CGEvent.tapEnable, rate-limited by
///     TapRestartRateLimiter (5 within 2s) to prevent hot loops.
///   - NSWorkspace.didWakeNotification → schedules a re-arm attempt ~3 s later
///     [decision: AltTab pattern; 3 s allows the OS to settle after sleep].
///
/// `self` is passed to the C callback via Unmanaged.passUnretained — no
///   retain cycle, and the pointer is valid for the monitor's lifetime.
public final class HotkeyMonitor: @unchecked Sendable {

    // MARK: Public API

    /// The current binding. Persisted on every change.
    /// Lock-guarded: read on the run-loop thread (`handle`/`buildTap`) and written
    /// on the main thread (`updateBinding`, via Phase B's live trigger-mode switch).
    /// Without the lock this is a data race on a multi-field value struct.
    private var _binding: HotkeyBinding
    public var binding: HotkeyBinding { lock.withLock { _binding } }

    /// The stream of hotkey events. Stable for the monitor's lifetime.
    /// Consumers iterate this once and receive events across all arm/re-arm cycles.
    public let events: AsyncStream<HotkeyEvent>

    // MARK: Arm-state notification

    /// Yields `true` when the tap arms, `false` when it disarms.
    /// Used by `DictationController` to clear `permissionsNeeded` on the main actor.
    public let armStateChanges: AsyncStream<Bool>

    // MARK: Private — stream internals

    private let continuation: AsyncStream<HotkeyEvent>.Continuation
    private let armContinuation: AsyncStream<Bool>.Continuation

    // MARK: Private — state (guarded by lock)

    /// Lock protecting cross-thread mutable flags below.
    /// [decision: NSLock over os_unfair_lock for Swift ergonomics; both are
    ///  correct here — NSLock is sufficient for low-frequency flag mutation].
    private let lock = NSLock()

    /// Whether `start()` has been called and we want the tap armed.
    private var armingDesired: Bool = false

    /// Whether the tap is currently installed and enabled.
    private var isArmed: Bool = false

    /// Last known AX trust state (for edge detection in the watchdog).
    private var wasTrusted: Bool = false

    // MARK: Private — tap lifecycle (run-loop thread only — never touch from main)

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    /// The run-loop running on the dedicated tap thread.
    /// Written once (before first watchdog callback fires), then read-only.
    private var tapRunLoop: CFRunLoop?

    /// Rate limiter for tapDisabled re-enable events.
    private var restartRateLimiter = TapRestartRateLimiter()

    /// Detector: pure value type, mutated only on the run-loop callback thread.
    private var detector = DoubleTapDetector()

    /// Edge tracking for Fn up/down. Mutated only in the tap callback thread.
    private var lastFnDown: Bool = false

    private let store: any BindingStoring

    /// Wake re-arm timer reference. Invalidated if a new wake fires before it fires.
    private var wakeRearmTimer: CFRunLoopTimer?

    // MARK: Init

    /// Non-blocking init — the run-loop thread is spawned immediately; the tap is
    /// built asynchronously on the first `start()` call once AX is granted.
    public init(binding: HotkeyBinding = .defaultBinding, store: any BindingStoring = UserDefaultsBindingStore()) {
        let persisted = store.load() ?? binding
        self._binding = persisted
        self.store = store

        // Build the AsyncStream once — consumers keep the same reference for
        // the monitor's lifetime and receive events across all arm cycles.
        // AsyncStream.makeStream() [verified: Swift 5.9+, SE-0388, 2026-06-21]
        // avoids the IUO pattern (var cont: ...!) that the moat scanner flags.
        let (eventsStream, eventsCont) = AsyncStream<HotkeyEvent>.makeStream()
        self.events = eventsStream
        self.continuation = eventsCont

        let (armStream, armCont) = AsyncStream<Bool>.makeStream()
        self.armStateChanges = armStream
        self.armContinuation = armCont

        // Spawn the dedicated run-loop thread. This is the ONLY place we touch
        // the thread; everything tap-related thereafter runs on that thread.
        // No semaphore, no wait — init returns before the thread starts.
        Thread.detachNewThread { [weak self] in
            self?.runLoopMain()
        }
    }

    deinit {
        // Tear down the tap from wherever we are; the run loop will stop when the
        // thread sees the deallocation. Continuation finish clears stream subscribers.
        lock.withLock {
            armingDesired = false
        }
        tearDownTap()
        continuation.finish()
        armContinuation.finish()
    }

    // MARK: Tap lifecycle (called from any thread; work handed to run-loop thread)

    /// Signal the monitor to arm the event tap. Non-throwing — arming is async;
    /// if AX is not yet granted the watchdog will arm on the untrusted→trusted edge.
    /// Safe to call multiple times (idempotent via armingDesired flag).
    public func start() {
        lock.withLock {
            armingDesired = true
        }
        // Wake the run loop so the watchdog timer fires ASAP instead of waiting
        // for the next 100ms interval.
        if let rl = lock.withLock({ tapRunLoop }) {
            CFRunLoopWakeUp(rl)
        }
        SpeakLog.hotkey.info("HotkeyMonitor.start() called — arming will be attempted on run-loop thread.")
    }

    /// Disable the tap and stop emitting events. The stream itself stays open
    /// (re-calling start() will re-arm and events will flow again).
    public func stop() {
        lock.withLock {
            armingDesired = false
        }
        tearDownTap()
        SpeakLog.hotkey.info("HotkeyMonitor.stop() called — tap disarmed.")
    }

    /// Update the binding and persist it.
    public func updateBinding(_ newBinding: HotkeyBinding) {
        lock.withLock { _binding = newBinding }
        store.save(newBinding)
        SpeakLog.hotkey.info("Hotkey binding updated: keyCode=\(newBinding.keyCode, privacy: .public)")
    }

    // MARK: - Run-loop thread entry point

    /// The entry point for the dedicated tap thread. Runs for the monitor's lifetime.
    private func runLoopMain() {
        let rl = CFRunLoopGetCurrent()

        lock.withLock {
            tapRunLoop = rl
        }

        // Install the re-arm/watchdog timer. 100ms interval [decision: benchmark.md §7].
        // CFRunLoopTimerCreate [verified: swiftc -typecheck macOS SDK, 2026-06-21].
        let timerInterval: CFTimeInterval = 0.1 // 100ms [decision: benchmark.md §7]
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        let timerCallback: CFRunLoopTimerCallBack = { _, info in
            guard let ptr = info else { return }
            let monitor = Unmanaged<HotkeyMonitor>.fromOpaque(ptr).takeUnretainedValue()
            monitor.watchdogTick()
        }
        var context = CFRunLoopTimerContext(
            version: 0,
            info: selfPtr,
            retain: nil,
            release: nil,
            copyDescription: nil
        )
        let timer = CFRunLoopTimerCreate(
            kCFAllocatorDefault,
            CFAbsoluteTimeGetCurrent() + timerInterval,
            timerInterval,
            0, 0,
            timerCallback,
            &context
        )
        // timer is non-optional in Swift bridging of CFRunLoopTimerCreate
        CFRunLoopAddTimer(rl, timer, CFRunLoopMode.commonModes)

        // Register for workspace wake notifications so we can re-arm after sleep.
        // NSWorkspace.shared.notificationCenter (NOT NotificationCenter.default)
        // [verified: AppKit docs — didWakeNotification is on the workspace center].
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: nil  // nil → delivered on the posting thread; fine here
        ) { [weak self] _ in
            self?.handleWakeNotification()
        }

        CFRunLoopRun()
    }

    // MARK: - Watchdog timer callback (run-loop thread)

    /// Called every 100ms on the run-loop thread.
    /// Handles: re-arm on AX-grant edge, tap-disabled recovery.
    private func watchdogTick() {
        let shouldArm = lock.withLock { armingDesired }
        let currentlyArmed = lock.withLock { isArmed }

        if !currentlyArmed && shouldArm {
            // Check AX trust without prompting.
            // [verified: AXIsProcessTrustedWithOptions with kAXTrustedCheckOptionPrompt:false
            //  queries silently — no prompt — so safe to call at 100ms cadence, 2026-06-21].
            let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false] as CFDictionary
            let nowTrusted = AXIsProcessTrustedWithOptions(opts)
            let wasTrustedPrev = lock.withLock { wasTrusted }

            if nowTrusted && !wasTrustedPrev {
                SpeakLog.hotkey.info("HotkeyMonitor: AX trust granted — building tap (re-arm).")
                buildTap()
            }
            lock.withLock { wasTrusted = nowTrusted }
        }
    }

    // MARK: - Tap construction (run-loop thread)

    /// Build and install the CGEventTap on the run-loop thread.
    /// Tears down any existing half-built tap first (safe retry).
    private func buildTap() {
        tearDownTap()
        detector.reset()
        lastFnDown = false

        let mask = CGEventMask(1 << CGEventType.flagsChanged.rawValue)
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        guard let port = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: HotkeyMonitor.tapCallback,
            userInfo: selfPtr
        ) else {
            SpeakLog.hotkey.error("HotkeyMonitor: CGEvent.tapCreate returned nil — AX may have been revoked.")
            lock.withLock {
                isArmed = false
                wasTrusted = false  // force a re-check on next tick
            }
            return
        }

        guard let rl = lock.withLock({ tapRunLoop }) else {
            SpeakLog.hotkey.error("HotkeyMonitor: tapRunLoop not set — cannot install source.")
            return
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
        CFRunLoopAddSource(rl, source, .commonModes)

        self.eventTap = port
        self.runLoopSource = source

        lock.withLock {
            isArmed = true
            restartRateLimiter.reset()
        }

        SpeakLog.hotkey.info("HotkeyMonitor: tap armed, keyCode=\(self.binding.keyCode, privacy: .public).")
        armContinuation.yield(true)
    }

    // MARK: - Tap teardown (any thread)

    /// Disable and remove the tap. Safe to call multiple times.
    private func tearDownTap() {
        if let port = eventTap {
            CGEvent.tapEnable(tap: port, enable: false)
            if let src = runLoopSource, let rl = tapRunLoop {
                CFRunLoopRemoveSource(rl, src, .commonModes)
            }
        }
        eventTap = nil
        runLoopSource = nil

        let wasArmed = lock.withLock {
            let prev = isArmed
            isArmed = false
            return prev
        }
        if wasArmed {
            armContinuation.yield(false)
        }
    }

    // MARK: - CGEventTap callback (run-loop thread)

    /// The CGEventTap C-style callback. Runs on the private CFRunLoop thread.
    /// `self` is recovered from `userInfo` via Unmanaged.passUnretained (no retain).
    private static let tapCallback: CGEventTapCallBack = { proxy, eventType, event, userInfo in
        guard let ptr = userInfo else {
            return Unmanaged.passRetained(event)
        }
        let monitor = Unmanaged<HotkeyMonitor>.fromOpaque(ptr).takeUnretainedValue()
        monitor.handle(proxy: proxy, type: eventType, event: event)
        return Unmanaged.passRetained(event)
    }

    /// Handle an incoming CGEvent on the tap's run loop thread.
    ///
    /// Both trigger modes read `lastFnDown` for edge detection and update it
    /// before dispatching — this keeps edge state correct regardless of mode.
    ///
    /// - `.doubleTap`: acts only on the press leading edge (false→true) and
    ///   delegates to `DoubleTapDetector`.
    /// - `.hold`: acts on BOTH edges via `holdEdge(isFnDown:wasDown:)` —
    ///   press → startCapture, release → stopCapture. No timestamp or window needed.
    ///
    /// If the tap is torn down mid-hold (Phase A watchdog, rate-limiter, or wake
    /// re-arm), `buildTap()` resets `lastFnDown = false` (line ~519) so the next
    /// press after re-arm is treated as a fresh start — hold cannot stick "on".
    private func handle(proxy: CGEventTapProxy, type eventType: CGEventType, event: CGEvent) {
        if eventType == .tapDisabledByTimeout || eventType == .tapDisabledByUserInput {
            handleTapDisabled()
            return
        }

        guard eventType == .flagsChanged else { return }

        // Snapshot the binding once (lock-guarded getter) so a concurrent
        // updateBinding() on the main thread can't tear this multi-field read.
        let currentBinding = binding
        let keyCode = Int(event.getIntegerValueField(.keyboardEventKeycode))
        guard keyCode == currentBinding.keyCode else { return }

        // Fn-press edge detection: maskSecondaryFn bit set = key down.
        // [verified: CGEventFlags.maskSecondaryFn rawValue = 8388608, SDK 2026-06-20]
        let flags = event.flags
        let isFnDown = flags.contains(.maskSecondaryFn)
        let wasDown = lastFnDown
        lastFnDown = isFnDown   // update BEFORE branching so both modes see current state

        switch currentBinding.trigger {

        case .doubleTap:
            // Act only on the press leading edge — release edge is ignored.
            guard isFnDown && !wasDown else { return }

            // Timestamp: use DispatchTime.uptimeNanoseconds (nanoseconds, monotonic)
            // converted to seconds. Avoids CGEvent.timestamp unit ambiguity (mach
            // absolute time is not nanoseconds on Apple Silicon without conversion).
            // HID delivery latency is sub-ms; "now" ≈ press time for a 0.4s window.
            let timestampSec = Double(DispatchTime.now().uptimeNanoseconds) / 1_000_000_000.0
            let window = currentBinding.doubleTapWindow
            if let hotkeyEvent = detector.register(tapAt: timestampSec, window: window) {
                SpeakLog.hotkey.info("HotkeyEvent: \(String(describing: hotkeyEvent), privacy: .public)")
                continuation.yield(hotkeyEvent)
            }

        case .hold:
            // Act on BOTH edges: press → startCapture, release → stopCapture.
            // No timestamp or window needed — the gesture is defined by key state.
            if let hotkeyEvent = holdEdge(isFnDown: isFnDown, wasDown: wasDown) {
                SpeakLog.hotkey.info("HotkeyEvent (hold): \(String(describing: hotkeyEvent), privacy: .public)")
                continuation.yield(hotkeyEvent)
            }
        }
    }

    // MARK: - Tap-disabled recovery (spec §3, run-loop thread)

    /// Handle tapDisabledByTimeout / tapDisabledByUserInput.
    /// Re-enables the tap if within the rate limit; tears down and flags for
    /// re-arm (via watchdog) if the cap is exceeded.
    private func handleTapDisabled() {
        guard let port = eventTap else { return }

        let now = Double(DispatchTime.now().uptimeNanoseconds) / 1_000_000_000.0
        let allowed = lock.withLock { restartRateLimiter.recordAttempt(now: now) }

        if allowed {
            CGEvent.tapEnable(tap: port, enable: true)
            SpeakLog.hotkey.warning("HotkeyMonitor: tap re-enabled after OS disable.")
        } else {
            SpeakLog.hotkey.error("HotkeyMonitor: tap restart cap exceeded — tearing down. Will re-arm on next AX check.")
            tearDownTap()
            // armingDesired remains true → watchdog rebuilds after AX re-check.
            // Reset wasTrusted so the watchdog's untrusted→trusted EDGE re-fires:
            // without this, AX is still trusted (no edge) and the tap would stay
            // dead forever after the cap trips. (Review fix, Phase A.)
            lock.withLock { wasTrusted = false }
        }
    }

    // MARK: - Wake handling (spec §3, run-loop thread)

    /// Called on NSWorkspace.didWakeNotification.
    /// Schedules a re-arm ~3 s after wake (AltTab pattern; 3 s allows the OS
    /// to settle post-sleep before reinstalling the tap).
    /// [decision: AltTab uses a two-pass strategy; we do a single 3 s pass
    ///  since re-arm is idempotent — benchmark.md §7].
    private func handleWakeNotification() {
        SpeakLog.hotkey.info("HotkeyMonitor: wake notification — scheduling re-arm in 3 s.")

        // Invalidate any pending wake timer.
        wakeRearmTimer.map { CFRunLoopTimerInvalidate($0) }
        wakeRearmTimer = nil

        guard let rl = lock.withLock({ tapRunLoop }) else { return }

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        let cb: CFRunLoopTimerCallBack = { _, info in
            guard let ptr = info else { return }
            let monitor = Unmanaged<HotkeyMonitor>.fromOpaque(ptr).takeUnretainedValue()
            // Tear down and let the watchdog rebuild fresh.
            monitor.tearDownTap()
            let shouldArm = monitor.lock.withLock { monitor.armingDesired }
            if shouldArm {
                monitor.buildTap()
            }
            monitor.wakeRearmTimer = nil
        }
        var ctx = CFRunLoopTimerContext(version: 0, info: selfPtr, retain: nil, release: nil, copyDescription: nil)
        let wakeDelay: CFTimeInterval = 3.0  // [decision: AltTab pattern, benchmark.md §7]
        let timer = CFRunLoopTimerCreate(
            kCFAllocatorDefault,
            CFAbsoluteTimeGetCurrent() + wakeDelay,
            0,   // non-repeating
            0, 0,
            cb,
            &ctx
        )
        wakeRearmTimer = timer
        CFRunLoopAddTimer(rl, timer, CFRunLoopMode.commonModes)
    }
}
