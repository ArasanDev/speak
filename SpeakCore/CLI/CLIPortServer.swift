// SpeakCore/CLI/CLIPortServer.swift
//
// Server-side CFMessagePort registration for the CLI IPC channel.
//
// Called once from `DictationController.startMonitoring()` (after the
// XCTestConfigurationFilePath early-return guard in AppDelegate) so the port is
// live only when the app is running as a real menubar instance.
//
// Threading contract:
//   - `CLIPortServer` is created and retained by `DictationController` (MainActor).
//   - The CFMessagePort callback is `@convention(c)` — cannot capture Swift context.
//     We route context through `CFMessagePortContext.info` using an unretained
//     Unmanaged reference to the `CLIPortServer` instance (the server lives for
//     the app lifetime — there is no UAF risk). [decision: W2.3]
//   - The port's run-loop source is scheduled on `CFRunLoopGetMain()` so the
//     callback fires on the main thread.
//   - `--status` reads the live state synchronously inside the callback using
//     `MainActor.assumeIsolated` (we are already on the main thread). [decision: W2.3]
//   - `--start`/`--stop` dispatch a `Task { @MainActor in ... }` and return an
//     accept-ack immediately. The dictation transition may not have completed
//     when the reply is delivered. [decision: W2.3]
//
// Idempotency:
//   The handler gates on `DictationController.icon` before dispatching:
//     start: no-op if icon != .idle  (already recording or processing)
//     stop:  no-op if icon != .listening  (already idle or processing)
//   This matches the Escape-handler guard at DictationController:307 and reuses
//   the same private beginDictation/endDictation path. [decision: W2.3]

import Foundation
import os

// MARK: - CLICommandHandler protocol

/// The subset of `DictationController` that `CLIPortServer` needs.
/// Keeping this narrow avoids a circular import and makes the server
/// independently testable via a stub. [decision: W2.3]
@MainActor
public protocol CLICommandHandler: AnyObject {
    /// The current app icon state — used to gate idempotent commands.
    var icon: MenubarIcon { get }
    /// The current hotkey binding display string (e.g. "⌘ Right Command ×2").
    var currentHotkeyDisplayString: String { get }
    /// Start a dictation session. No-op if already listening/processing.
    func cliBeginDictation()
    /// End the current dictation session. No-op if not listening.
    func cliEndDictation()
}

// MARK: - CLIPortServer

/// Registers and owns a local CFMessagePort server that the `speak` CLI tool
/// connects to for `--start`, `--stop`, and `--status` commands.
///
/// Ownership: one instance per app lifetime, retained by `DictationController`.
/// `invalidate()` is called on deinit and when monitoring stops (not currently
/// used — the app terminates instead).
public final class CLIPortServer {

    // MARK: - Private state

    private var port: CFMessagePort?
    private var runLoopSource: CFRunLoopSource?

    // Unretained reference used by the C callback.
    // The server lives for the app lifetime; the weak reference is a belt-
    // and-suspenders guard for any hypothetical early teardown.
    private weak var handler: (any CLICommandHandler)?

    // MARK: - Init / teardown

    public init() {}

    deinit {
        invalidate()
    }

    /// Register the named local port and schedule it on the main run loop.
    ///
    /// Must be called from the main thread (or main actor) after the app is live.
    /// Safe to call multiple times — no-ops if already registered.
    ///
    /// - Parameter handler: The `CLICommandHandler` that handles dispatched commands.
    public func register(handler: any CLICommandHandler) {
        guard port == nil else {
            SpeakLog.cli.warning("CLIPortServer.register: already registered — no-op.")
            return
        }

        self.handler = handler

        // Build the context with an unretained pointer to self.
        // The C callback reconstructs `CLIPortServer` from `context.info`.
        // `self` outlives the port (deinit calls invalidate()) so no UAF.
        var context = CFMessagePortContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )

        // Create the local named port. `shouldFreeInfo` is false — we own context.
        var shouldFreeInfo: DarwinBoolean = false
        guard let localPort = CFMessagePortCreateLocal(
            nil,                        // allocator
            CLIContract.portName,       // "com.speak.app.cli"
            CLIPortServer.portCallback, // @convention(c) callback
            &context,
            &shouldFreeInfo
        ) else {
            let portName = CLIContract.portName as String
            SpeakLog.cli.error(
                // swiftlint:disable:next line_length
                "CLIPortServer: failed to create local CFMessagePort '\(portName, privacy: .public)' — already registered?"
            )
            return
        }

        port = localPort

        // Schedule on the main run loop so the callback fires on the main thread.
        let source = CFMessagePortCreateRunLoopSource(nil, localPort, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
        runLoopSource = source

        SpeakLog.cli.info(
            "CLIPortServer: registered on port '\(CLIContract.portName as String, privacy: .public)'."
        )
    }

    /// Invalidate the port and remove it from the run loop.
    ///
    /// Called automatically on deinit.
    public func invalidate() {
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .defaultMode)
            runLoopSource = nil
        }
        if let existingPort = port {
            CFMessagePortInvalidate(existingPort)
            port = nil
        }
    }

    // MARK: - C callback (must be @convention(c))

    /// Called by CFRunLoop on the main thread when a CLI tool message arrives.
    ///
    /// Reconstructs `CLIPortServer` from `info` (the context pointer), decodes
    /// the JSON request, and dispatches accordingly.
    ///
    /// Return value: a `CFData` containing the JSON-encoded `CLIReply`. The reply
    /// must be non-nil for synchronous request/reply mode to work; on any error
    /// we return a failure reply rather than nil so the CLI tool always gets a
    /// response (prevents a 3-second timeout on the CLI side).
    private static let portCallback: CFMessagePortCallBack = { _, _, data, info -> Unmanaged<CFData>? in
        // Reconstruct self from the context info pointer.
        guard let info else {
            return CLIPortServer.encodeReply(.failure("internal: nil context"))
        }
        let server = Unmanaged<CLIPortServer>.fromOpaque(info).takeUnretainedValue()
        return server.handle(data: data as Data?)
    }

    // MARK: - Dispatch logic

    /// Decode the incoming request and build a reply.
    ///
    /// Called on the main thread. Reads `handler.icon` via `MainActor.assumeIsolated`
    /// (we are already on main — see scheduling above).
    private func handle(data: Data?) -> Unmanaged<CFData>? {
        guard let data else {
            SpeakLog.cli.error("CLIPortServer: received nil data — returning failure reply.")
            return CLIPortServer.encodeReply(.failure("no request data"))
        }

        let request: CLIRequest
        do {
            request = try CLIRequest.decode(data)
        } catch {
            SpeakLog.cli.error(
                "CLIPortServer: failed to decode request — \(error.localizedDescription, privacy: .public)"
            )
            return CLIPortServer.encodeReply(.failure("bad request JSON: \(error.localizedDescription)"))
        }

        guard let cmdHandler = handler else {
            SpeakLog.cli.error("CLIPortServer: handler deallocated — returning failure reply.")
            return CLIPortServer.encodeReply(.failure("internal: handler unavailable"))
        }

        // We are on the main thread; the MainActor is available.
        // Read handler state synchronously for status; dispatch Tasks for start/stop.
        let reply: CLIReply = MainActor.assumeIsolated {
            switch request.cmd {

            case .status:
                // Synchronous: read live state and reply inline.
                let state = CLIState(from: cmdHandler.icon)
                let binding = cmdHandler.currentHotkeyDisplayString
                SpeakLog.cli.info("CLIPortServer: status — state=\(state.rawValue, privacy: .public)")
                SpeakLog.cli.info("CLIPortServer: status — binding=\(binding, privacy: .public)")
                return .status(state: state, binding: binding)

            case .start:
                // Idempotency gate: only dispatch if idle.
                // If already listening or processing, reply ok=true (the user's
                // desired state — recording — is already true or in flight).
                // [decision: W2.3 — accept-ack; transition is async]
                guard cmdHandler.icon == .idle else {
                    let iconDescription = String(describing: cmdHandler.icon)
                    SpeakLog.cli.info(
                        "CLIPortServer: --start ignored — not idle (icon=\(iconDescription, privacy: .public))"
                    )
                    return .accepted()  // already in desired or transitional state
                }
                cmdHandler.cliBeginDictation()
                SpeakLog.cli.info("CLIPortServer: --start dispatched.")
                return .accepted()

            case .stop:
                // Idempotency gate: only dispatch if listening.
                // If already idle/processing/done, reply ok=true — no work needed.
                // [decision: W2.3 — accept-ack; transition is async]
                guard cmdHandler.icon == .listening else {
                    let iconDescription = String(describing: cmdHandler.icon)
                    SpeakLog.cli.info(
                        "CLIPortServer: --stop ignored — not listening (icon=\(iconDescription, privacy: .public))"
                    )
                    return .accepted()  // already stopped or in transition
                }
                cmdHandler.cliEndDictation()
                SpeakLog.cli.info("CLIPortServer: --stop dispatched.")
                return .accepted()
            }
        }

        return CLIPortServer.encodeReply(reply)
    }

    // MARK: - Encode reply to CFData

    /// Encode a `CLIReply` to a retained `CFData` for the port callback return.
    ///
    /// On encoding failure (should never happen with a well-formed Codable type)
    /// we return a minimal ASCII fallback so the CLI still gets a response.
    private static func encodeReply(_ reply: CLIReply) -> Unmanaged<CFData>? {
        let data: Data
        do {
            data = try reply.encode()
        } catch {
            SpeakLog.cli.error(
                "CLIPortServer: failed to encode reply — \(error.localizedDescription, privacy: .public)"
            )
            // Fallback: a minimal ASCII error payload so the client doesn't hang.
            let fallback = #"{"ok":false,"error":"encoding error"}"#
            data = Data(fallback.utf8)
        }
        return Unmanaged.passRetained(data as CFData)
    }
}
