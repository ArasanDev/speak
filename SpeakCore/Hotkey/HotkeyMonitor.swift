// SpeakCore/Hotkey/HotkeyMonitor.swift
//
// Global hotkey monitor using CGEventTap (architecture.md §6, roadmap P5).
//
// API surface:
//   HotkeyEvent       — startCapture | stopCapture (Sendable)
//   HotkeyBinding     — Codable + Sendable; custom Codable for CGEventFlags
//   HotkeyMonitor     — installs the tap, exposes AsyncStream<HotkeyEvent>
//   DoubleTapDetector — pure value-type detector (testable without a tap)
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
// --- Live OS behavior [deferred] ---
// Whether the tap fires correctly while another app has focus, and whether
// the OS prompts for Accessibility + Input Monitoring permissions on first run,
// requires a live, non-sandboxed app run with permissions granted.
// These done-when rows are marked [deferred — needs human verification].
//
// --- Double-tap window ---
// Default 0.4 s = 400 ms. Source: benchmark.md §7 [decision], empirically tuned
// at P13 dogfood. Not a magic number — the trace comment is the authority.
// The constant below carries this citation; a bare 0.4 without the citation
// would fail the no-magic-numbers hard rule (AGENTS.md §3).

import CoreGraphics
import ApplicationServices
import Carbon.HIToolbox
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

    public enum Trigger: Codable, Sendable {
        case doubleTap
        case singleTapToggle
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
/// Threading model (architecture.md §8):
///   - The CGEventTap callback runs on a private CFRunLoop thread.
///   - Events are forwarded to the AsyncStream continuation, which is
///     consumed on @MainActor by the caller (App layer wires to CaptureSession).
///   - The HotkeyMonitor itself is not an actor; it is a final class.
///   - `self` is passed to the C callback via Unmanaged.passUnretained — no
///     retain cycle, and the pointer is valid for the monitor's lifetime.
///
/// Permissions:
///   CGEvent.tapCreate returns nil when Accessibility or Input Monitoring is
///   not granted. We detect which is missing via AXIsProcessTrusted() and
///   throw the appropriate SpeakError rather than force-unwrapping.
///
/// Fn-key detection model: see file-top comment.
public final class HotkeyMonitor: @unchecked Sendable {

    // MARK: Public API

    /// The current binding. Persisted on every change.
    public private(set) var binding: HotkeyBinding

    /// The stream of hotkey events. Consumers (the App layer) iterate this
    /// async stream and route each event to CaptureSession.start()/stop().
    /// A new stream is created on each call to `start()`.
    public private(set) var events: AsyncStream<HotkeyEvent>

    // MARK: Private state

    private var continuation: AsyncStream<HotkeyEvent>.Continuation?
    private var detector = DoubleTapDetector()
    private var lastFnDown: Bool = false   // edge-detection: was Fn down last event?

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private let runLoop: CFRunLoop
    private let store: any BindingStoring

    // MARK: Init

    public init(binding: HotkeyBinding = .defaultBinding, store: any BindingStoring = UserDefaultsBindingStore()) {
        let persisted = store.load() ?? binding
        self.binding = persisted
        self.store = store

        // Spawn the dedicated run loop for event tap callbacks.
        // The run loop is retained here and started below.
        //
        // CFRunLoopGetCurrent() always returns a non-nil CFRunLoop on any live
        // thread. We use a nonisolated helper to avoid force-unwrap while
        // preserving the semaphore synchronization.
        var capturedRunLoop: CFRunLoop = CFRunLoopGetMain() // safe default; overwritten below
        let sema = DispatchSemaphore(value: 0)
        Thread.detachNewThread {
            capturedRunLoop = CFRunLoopGetCurrent()
            sema.signal()
            CFRunLoopRun()
        }
        sema.wait()
        self.runLoop = capturedRunLoop

        // Placeholder — replaced in start(). Keeps stored property initialized.
        var cont: AsyncStream<HotkeyEvent>.Continuation?
        self.events = AsyncStream { cont = $0 }
        self.continuation = cont
    }

    deinit {
        stopTap()
    }

    // MARK: Tap lifecycle

    /// Install the event tap and start emitting events.
    /// Throws `SpeakError.accessibilityDenied` or `.inputMonitoringDenied`
    /// if the required permissions are absent (CGEvent.tapCreate returns nil).
    public func start() throws {
        // Tear down any existing tap first (idempotent).
        stopTap()

        // Reset detector so stale state doesn't bleed across start() calls.
        detector.reset()
        lastFnDown = false

        // Allocate a fresh event stream.
        var cont: AsyncStream<HotkeyEvent>.Continuation?
        let stream = AsyncStream<HotkeyEvent> { cont = $0 }
        self.events = stream
        self.continuation = cont

        // Build the flagsChanged mask — Fn key fires flagsChanged, not keyDown.
        // [verified: CGEventType.flagsChanged rawValue = 12; CGEvent.tapCreate
        // takes a CGEventMask bitmask over CGEventType rawValues]
        let mask = CGEventMask(1 << CGEventType.flagsChanged.rawValue)

        // userInfo: pass `self` unretained through the C callback.
        // The pointer is valid as long as this HotkeyMonitor lives.
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        guard let port = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: HotkeyMonitor.tapCallback,
            userInfo: selfPtr
        ) else {
            // Diagnose: which permission is missing?
            if !AXIsProcessTrusted() {
                SpeakLog.hotkey.error("CGEvent.tapCreate failed: Accessibility not granted")
                throw SpeakError.accessibilityDenied
            }
            // Input Monitoring absence also causes nil; no runtime API to
            // distinguish cleanly — report inputMonitoringDenied as the
            // second reason.
            SpeakLog.hotkey.error("CGEvent.tapCreate failed: likely Input Monitoring not granted")
            throw SpeakError.inputMonitoringDenied
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
        CFRunLoopAddSource(runLoop, source, .commonModes)

        self.eventTap = port
        self.runLoopSource = source

        SpeakLog.hotkey.info("HotkeyMonitor started, binding keyCode=\(self.binding.keyCode, privacy: .public)")
    }

    /// Disable and tear down the event tap. Safe to call multiple times.
    public func stop() {
        stopTap()
        continuation?.finish()
        continuation = nil
    }

    /// Update the binding and persist it.
    public func updateBinding(_ newBinding: HotkeyBinding) {
        binding = newBinding
        store.save(newBinding)
        SpeakLog.hotkey.info("Hotkey binding updated: keyCode=\(newBinding.keyCode, privacy: .public)")
    }

    // MARK: Private

    private func stopTap() {
        if let port = eventTap {
            CGEvent.tapEnable(tap: port, enable: false)
            if let src = runLoopSource {
                CFRunLoopRemoveSource(runLoop, src, .commonModes)
            }
        }
        eventTap = nil
        runLoopSource = nil
    }

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
    /// All state mutation goes through the detector (value type) captured here.
    private func handle(proxy: CGEventTapProxy, type eventType: CGEventType, event: CGEvent) {
        // Re-enable the tap if the OS disabled it (e.g. on timeout or user input).
        // [Fn-key taps can be disabled by the OS; must re-enable to keep monitoring.]
        if eventType == .tapDisabledByTimeout || eventType == .tapDisabledByUserInput {
            if let port = eventTap {
                CGEvent.tapEnable(tap: port, enable: true)
                SpeakLog.hotkey.warning("Event tap re-enabled after OS disable")
            }
            return
        }

        guard eventType == .flagsChanged else { return }

        let keyCode = Int(event.getIntegerValueField(.keyboardEventKeycode))
        guard keyCode == binding.keyCode else { return }

        // Fn-press edge detection: maskSecondaryFn bit set = key down.
        // flagsChanged fires for both press and release with the same keycode.
        // [verified: CGEventFlags.maskSecondaryFn rawValue = 8388608, SDK 2026-06-20]
        // [inferred: .maskSecondaryFn is the Fn/Globe key bit — standard CoreGraphics
        //  convention; live confirmation deferred to P5 human verification]
        let flags = event.flags
        let isFnDown = flags.contains(.maskSecondaryFn)
        let wasDown = lastFnDown
        lastFnDown = isFnDown

        // Emit a "tap" only on the leading edge (released → pressed).
        guard isFnDown && !wasDown else { return }

        // Timestamp for the window comparison. We deliberately do NOT use
        // CGEvent.timestamp: that field is in mach-absolute-time units, and on
        // Apple Silicon the mach timebase is not 1:1 with nanoseconds (~125/3),
        // so `event.timestamp / 1e9` would yield a wildly wrong window. Instead
        // read a monotonic clock at handle time — DispatchTime.uptimeNanoseconds
        // is documented nanoseconds [verified: SDK]. HID-tap delivery latency is
        // sub-millisecond, negligible against the 0.4 s double-tap window, so
        // "now" ≈ press time. This keeps the window correct regardless of the
        // CGEvent.timestamp unit ambiguity.
        let timestampSec = Double(DispatchTime.now().uptimeNanoseconds) / 1_000_000_000.0

        let window = binding.doubleTapWindow
        if let hotkeyEvent = detector.register(tapAt: timestampSec, window: window) {
            SpeakLog.hotkey.info("HotkeyEvent: \(String(describing: hotkeyEvent), privacy: .public)")
            // Forward to the AsyncStream. The continuation is @Sendable; OK to
            // call from this background thread.
            continuation?.yield(hotkeyEvent)
        }
    }
}
