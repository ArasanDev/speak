// SpeakCore/CLI/CLIContract.swift
//
// Shared contract between the `speak` menubar app and the `speak` CLI tool.
// Both the app (port server) and the CLI tool (port client) import SpeakCore,
// so constants and Codable types live here — not in either binary directly.
//
// WIRE FORMAT (decision W2.3):
//   Request:  JSON `{"cmd": "start"|"stop"|"status"}`
//   Reply:    JSON `{"ok": bool, "error"?: string}` for start/stop (accept-ack)
//             JSON `{"ok": bool, "state": "idle"|"listening"|"processing", "binding": "<displayString>"}` for status
//
//   Note: start/stop replies are **accept-acks** — the command was dispatched to
//   the main actor but the dictation transition may not have completed yet.
//   status is **synchronous**: the reply reflects the live icon+binding state
//   at the instant the port callback ran. [decision: W2.3]
//
// MenubarIcon → CLIState mapping [decision: W2.3]:
//   .idle       → "idle"
//   .listening  → "listening"
//   .processing → "processing"
//   .done       → "idle"    (transient flash; stable target is idle)
//   .error      → "idle"    (recovery state; no actionable CLI state)
//
// PORT NAME [decision: W2.3]:
//   Derived from the app bundle id so there is no bare string magic.
//   The app bundle id is "com.speak.app" (project.yml PRODUCT_BUNDLE_IDENTIFIER).
//   Port name = com.speak.app.cli
//   The app side may assert:
//     assert(CLIContract.portName == Bundle.main.bundleIdentifier! + ".cli")
//
// TRANSPORT PROTOCOL:
//   `CLITransport` is a thin seam so the CLI tool can inject a stub in unit tests.
//   `CFMessagePortTransport` is the production client — synchronous request/reply.

import Foundation

// MARK: - Port name

/// The named CFMessagePort that the app registers on launch and the CLI connects to.
///
/// Derived from the app bundle id (com.speak.app). The ".cli" suffix scopes it so
/// a future second port (e.g. an XPC service) doesn't conflict.
/// [decision: W2.3 — constant here rather than Bundle.main so the CLI tool binary
///  (separate bundle, id "com.speak.cli") resolves the same string without
///  Bundle.main giving a different result]
public enum CLIContract {
    /// Port name: "com.speak.app.cli"
    /// Traces to: PRODUCT_BUNDLE_IDENTIFIER in project.yml ("com.speak.app") + ".cli"
    public static let portName: CFString = "com.speak.app.cli" as CFString

    /// Timeout in seconds for a synchronous CFMessagePort request.
    /// 3 s is generous for a same-user mach port that either answers immediately or
    /// never (app not running). [decision: W2.3]
    public static let sendTimeoutSeconds: TimeInterval = 3.0
}

// MARK: - CLICommand (request)

/// A command sent by the CLI tool to the running app over the named CFMessagePort.
public enum CLICommand: String, Codable, Sendable {
    case start
    case stop
    case status
}

/// The JSON envelope wrapping a `CLICommand` over the wire.
///
/// {"cmd": "start"|"stop"|"status"}
public struct CLIRequest: Codable, Sendable {
    public let cmd: CLICommand

    public init(cmd: CLICommand) {
        self.cmd = cmd
    }
}

// MARK: - CLIReply (response)

/// Wire state for the --status reply.
/// Coarser than `MenubarIcon` — done/error are transient and collapse to idle.
/// [decision: W2.3 — see MenubarIcon mapping at top of file]
public enum CLIState: String, Codable, Sendable {
    case idle
    case listening
    case processing
}

/// The JSON envelope for all replies from the app to the CLI tool.
///
/// start/stop:  {"ok": true|false, "error"?: "message"}
/// status:      {"ok": true, "state": "idle|listening|processing", "binding": "<displayString>"}
public struct CLIReply: Codable, Sendable {
    public let ok: Bool
    /// Human-readable error message when ok==false.
    public let error: String?
    /// Present in status replies: the active dictation state.
    public let state: CLIState?
    /// Present in status replies: the hotkey binding display string (e.g. "⌘ Right Command ×2").
    public let binding: String?

    // MARK: - Factory helpers

    /// Accepted-ack for start/stop.
    public static func accepted() -> CLIReply {
        CLIReply(ok: true, error: nil, state: nil, binding: nil)
    }

    /// Error reply with a human-readable reason.
    public static func failure(_ message: String) -> CLIReply {
        CLIReply(ok: false, error: message, state: nil, binding: nil)
    }

    /// Status reply carrying live icon + binding.
    public static func status(state: CLIState, binding: String) -> CLIReply {
        CLIReply(ok: true, error: nil, state: state, binding: binding)
    }

    public init(ok: Bool, error: String?, state: CLIState?, binding: String?) {
        self.ok = ok
        self.error = error
        self.state = state
        self.binding = binding
    }
}

// MARK: - MenubarIcon → CLIState

extension CLIState {
    /// Map a live `MenubarIcon` to the coarser CLI-visible state.
    ///
    /// `.done` and `.error` are transient or recovery states with no distinct CLI
    /// verb — collapse both to `.idle` (the stable target). [decision: W2.3]
    public init(from icon: MenubarIcon) {
        switch icon {
        case .idle:       self = .idle
        case .listening:  self = .listening
        case .processing: self = .processing
        case .done:       self = .idle    // transient; stable target is idle
        case .error:      self = .idle    // recovery state; no actionable CLI state
        }
    }
}

// MARK: - JSON encode/decode helpers

extension CLIRequest {
    /// Encode to UTF-8 JSON bytes for transmission over CFMessagePort.
    public func encode() throws -> Data {
        try JSONEncoder().encode(self)
    }

    /// Decode from UTF-8 JSON bytes received over CFMessagePort.
    public static func decode(_ data: Data) throws -> CLIRequest {
        try JSONDecoder().decode(CLIRequest.self, from: data)
    }
}

extension CLIReply {
    /// Encode to UTF-8 JSON bytes for transmission over CFMessagePort.
    public func encode() throws -> Data {
        try JSONEncoder().encode(self)
    }

    /// Decode from UTF-8 JSON bytes received over CFMessagePort.
    public static func decode(_ data: Data) throws -> CLIReply {
        try JSONDecoder().decode(CLIReply.self, from: data)
    }
}

// MARK: - CLITransport protocol

/// Transport seam — injectable for testing.
///
/// The production implementation uses a CFMessagePort named port.
/// Tests inject a stub that records calls and returns pre-canned replies.
public protocol CLITransport: Sendable {
    /// Send a request and synchronously wait for the reply.
    ///
    /// - Returns: the decoded `CLIReply`.
    /// - Throws: `CLITransportError` if the port is unreachable or the reply
    ///   cannot be decoded.
    func send(_ request: CLIRequest) throws -> CLIReply
}

/// Errors from a `CLITransport` send.
public enum CLITransportError: Error, CustomStringConvertible {
    /// The remote port could not be opened — app is not running.
    case portNotFound
    /// The IPC call timed out.
    case timeout
    /// The reply payload could not be decoded as `CLIReply` JSON.
    case badReply(String)
    /// CFMessagePortSendRequest returned an unexpected status code.
    case sendFailed(Int32)

    public var description: String {
        switch self {
        case .portNotFound:   return "speak is not running — start the app first."
        case .timeout:        return "timed out waiting for a reply from speak."
        case .badReply(let reason): return "malformed reply from speak: \(reason)"
        case .sendFailed(let status): return "CFMessagePort send error (status \(status))."
        }
    }
}

// MARK: - CFMessagePortTransport (production client)

/// Synchronous CFMessagePort client — the CLI tool's production transport.
///
/// Opens the named local port, sends the encoded request, and waits for a
/// synchronous reply. If the port is not registered (app not running) the open
/// call returns nil and we throw `CLITransportError.portNotFound`.
///
/// Same-user mach namespace: the port is only reachable by processes running as
/// the same user on the same machine. No networking, no sockets, no entitlements
/// required at notarization. [decision: W2.3 — transport rationale in
/// specs/acceleration-roadmap.md §3 Wave 2.3]
public final class CFMessagePortTransport: CLITransport, @unchecked Sendable {

    public init() {}

    public func send(_ request: CLIRequest) throws -> CLIReply {
        // Encode the request to UTF-8 JSON data.
        let requestData: Data
        do {
            requestData = try request.encode()
        } catch {
            throw CLITransportError.badReply("failed to encode request: \(error)")
        }

        // Open the named remote port. Returns nil if the app is not running.
        guard let port = CFMessagePortCreateRemote(
            nil,                                    // allocator
            CLIContract.portName                    // "com.speak.app.cli"
        ) else {
            throw CLITransportError.portNotFound
        }

        // Send synchronously and wait for a reply.
        var replyData: Unmanaged<CFData>?
        let cfData = requestData as CFData
        let timeoutMs = Int32(CLIContract.sendTimeoutSeconds * 1000)  // 3000 ms [decision: W2.3]
        let status = CFMessagePortSendRequest(
            port,
            0,           // msgid — unused; all messages carry their command in the JSON body
            cfData,
            CFTimeInterval(timeoutMs) / 1000.0,     // sendTimeout
            CFTimeInterval(timeoutMs) / 1000.0,     // rcvTimeout
            CFRunLoopMode.defaultMode.rawValue,
            &replyData
        )

        switch status {
        case kCFMessagePortSuccess:
            break

        case kCFMessagePortSendTimeout, kCFMessagePortReceiveTimeout:
            throw CLITransportError.timeout

        case kCFMessagePortIsInvalid, kCFMessagePortTransportError:
            throw CLITransportError.portNotFound

        default:
            throw CLITransportError.sendFailed(status)
        }

        guard let rawReply = replyData?.takeRetainedValue() as Data? else {
            throw CLITransportError.badReply("empty reply from speak")
        }

        do {
            return try CLIReply.decode(rawReply)
        } catch {
            throw CLITransportError.badReply(String(describing: error))
        }
    }
}
