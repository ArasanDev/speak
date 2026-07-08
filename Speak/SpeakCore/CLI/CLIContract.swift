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
// H-3 EXTENSION (specs/horizon-voice-os.md Pillar 3 — MCP Agent Bridge):
//   Request:  JSON `{"cmd": "say", "text": "...", "interrupt"?: bool}`
//             JSON `{"cmd": "ask", "question": "...", "timeout"?: number}`
//             JSON `{"cmd": "confirm", "question": "...", "timeout"?: number}`
//   Reply:    say:     `{"ok": bool, "error"?: string}` — accept-ack, mirrors start/stop.
//             ask:     `{"ok": bool, "answer"?: string, "error"?: string}` — `answer` is
//                       the raw transcript text (empty string is a valid answer).
//             confirm: `{"ok": bool, "confirmed"?: bool, "error"?: string}` — `confirmed`
//                       is nil (with `ok == true`) when the spoken answer was neither a
//                       recognized yes/no nor a cancel phrase ("unclear"); the CLI-side
//                       backend surfaces that as its own failure case.
//
//   `ask`/`confirm` block on a real human speech round-trip (question TTS + a full
//   dictation session), which can legitimately take tens of seconds — the fixed 3 s
//   `sendTimeoutSeconds` used by start/stop/status/say is wrong for these two commands.
//   `CLIRequest.timeout` (seconds) is the caller's requested ceiling; `CLIContract
//   .askConfirmDefaultTimeoutSeconds` is the fallback when the caller doesn't specify
//   one. `CFMessagePortTransport.send(_:timeoutSeconds:)` takes a per-call override so
//   the CLI-tool side can wait long enough without changing the default for the other
//   three commands. [decision: H-3]
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
    ///
    /// Used as-is for `start`/`stop`/`status`/`say` (all accept-acks or synchronous
    /// state reads — none waits on human speech). [decision: H-3]
    public static let sendTimeoutSeconds: TimeInterval = 3.0

    /// Default timeout in seconds for `ask`/`confirm` when the caller does not supply
    /// an explicit `CLIRequest.timeout`. These commands speak a question and then run a
    /// full dictation round-trip — 60 s is generous for a human to notice the prompt,
    /// think, and answer, while still failing a truly-abandoned request rather than
    /// hanging the CLI process forever. [decision: H-3]
    public static let askConfirmDefaultTimeoutSeconds: TimeInterval = 60.0
}

// MARK: - CLICommand (request)

/// A command sent by the CLI tool to the running app over the named CFMessagePort.
public enum CLICommand: String, Codable, Sendable {
    case start
    case stop
    case status
    /// H-3: speak text aloud (accept-ack — mirrors start/stop). [decision: H-3]
    case say
    /// H-3: speak a question, then listen for a spoken answer and return the transcript. [decision: H-3]
    case ask
    /// H-3: speak a yes/no question, then listen and return a deterministic yes/no/unclear. [decision: H-3]
    case confirm
}

/// The JSON envelope wrapping a `CLICommand` over the wire.
///
/// {"cmd": "start"|"stop"|"status"}
/// {"cmd": "say", "text": "...", "interrupt"?: bool}
/// {"cmd": "ask"|"confirm", "question": "...", "timeout"?: number}
public struct CLIRequest: Codable, Sendable {
    public let cmd: CLICommand
    /// `say`: the text to speak aloud.
    public let text: String?
    /// `say`: cut off any speech currently playing before speaking this. [decision: H-3]
    public let interrupt: Bool?
    /// `ask`/`confirm`: the question to speak, then listen for.
    public let question: String?
    /// `ask`/`confirm`: caller-requested timeout in seconds for the round-trip.
    /// Falls back to `CLIContract.askConfirmDefaultTimeoutSeconds` when nil. [decision: H-3]
    public let timeout: Double?

    public init(cmd: CLICommand, text: String? = nil, interrupt: Bool? = nil,
                question: String? = nil, timeout: Double? = nil) {
        self.cmd = cmd
        self.text = text
        self.interrupt = interrupt
        self.question = question
        self.timeout = timeout
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
    /// Present in `ask` replies: the raw transcript text of the spoken answer.
    public let answer: String?
    /// Present in `confirm` replies when `ok == true`: `true`/`false` for a recognized
    /// yes/no answer, `nil` when the spoken answer was unclear (neither yes, no, nor
    /// cancel) — see `YesNoCancelExtractor`. [decision: H-3]
    public let confirmed: Bool?

    // MARK: - Factory helpers

    /// Accepted-ack for start/stop/say.
    public static func accepted() -> CLIReply {
        CLIReply(ok: true, error: nil, state: nil, binding: nil, answer: nil, confirmed: nil)
    }

    /// Error reply with a human-readable reason.
    public static func failure(_ message: String) -> CLIReply {
        CLIReply(ok: false, error: message, state: nil, binding: nil, answer: nil, confirmed: nil)
    }

    /// Status reply carrying live icon + binding.
    public static func status(state: CLIState, binding: String) -> CLIReply {
        CLIReply(ok: true, error: nil, state: state, binding: binding, answer: nil, confirmed: nil)
    }

    /// `ask` reply carrying the spoken answer's transcript text.
    public static func asked(_ answer: String) -> CLIReply {
        CLIReply(ok: true, error: nil, state: nil, binding: nil, answer: answer, confirmed: nil)
    }

    /// `confirm` reply carrying a deterministic yes/no, or `nil` when the spoken
    /// answer didn't match a recognized yes/no/cancel phrase ("unclear"). [decision: H-3]
    public static func confirmed(_ value: Bool?) -> CLIReply {
        CLIReply(ok: true, error: nil, state: nil, binding: nil, answer: nil, confirmed: value)
    }

    public init(ok: Bool, error: String?, state: CLIState?, binding: String?,
                answer: String? = nil, confirmed: Bool? = nil) {
        self.ok = ok
        self.error = error
        self.state = state
        self.binding = binding
        self.answer = answer
        self.confirmed = confirmed
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
    /// Send a request and synchronously wait for the reply, using the transport's
    /// default timeout (`CLIContract.sendTimeoutSeconds`).
    ///
    /// - Returns: the decoded `CLIReply`.
    /// - Throws: `CLITransportError` if the port is unreachable or the reply
    ///   cannot be decoded.
    func send(_ request: CLIRequest) throws -> CLIReply

    /// Send a request and synchronously wait for the reply, with an explicit
    /// per-call timeout override — used by `ask`/`confirm`, which need much longer
    /// than the 3 s default (see `CLIContract.askConfirmDefaultTimeoutSeconds`).
    /// [decision: H-3]
    func send(_ request: CLIRequest, timeoutSeconds: TimeInterval) throws -> CLIReply
}

extension CLITransport {
    /// Default-timeout convenience — forwards to the explicit-timeout overload so
    /// conforming types only need to implement one method. [decision: H-3]
    public func send(_ request: CLIRequest) throws -> CLIReply {
        try send(request, timeoutSeconds: CLIContract.sendTimeoutSeconds)
    }
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

    public func send(_ request: CLIRequest, timeoutSeconds: TimeInterval) throws -> CLIReply {
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
        let timeoutMs = Int32(timeoutSeconds * 1000)  // [decision: H-3 — caller-supplied override]
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
