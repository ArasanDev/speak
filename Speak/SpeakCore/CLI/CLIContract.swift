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

@preconcurrency import CoreFoundation
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
    nonisolated(unsafe) public static let portName: CFString = "com.speak.app.cli" as CFString

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
    /// AVB-5 (specs/agent-voice-bridge.md §6): speak a prompt in one of three modes
    /// (freeform/choice/approval), then listen and return exactly one of the five
    /// canonical `HumanResponseOutcome` outcomes. `.ask`/`.confirm` remain on the wire
    /// unchanged for existing clients; `speak_ask`/`speak_confirm` are now thin
    /// adapters implemented in terms of this workflow at the app layer
    /// (`DictationController.cliAsk`/`cliConfirm` call `cliRequestInput` internally).
    /// [decision: AVB-5]
    case requestInput
    /// AVB-6 (specs/agent-voice-bridge.md §7.1): register (or re-register, if
    /// `sessionId` is already known) an `AgentSession` and negotiate
    /// capabilities. Fast/synchronous, in-memory — handled like `.status`, not
    /// like `.ask`/`.confirm`/`.requestInput` (no mic, no human round-trip).
    /// [decision: AVB-6]
    case registerSession
    /// AVB-7 (specs/avb7-durable-calls-design.md): `speak_submit_call`. Fast,
    /// no mic, no pump — a direct actor read/write on `AgentCallStore`, replied
    /// inline. [decision: AVB-7]
    case submitCall
    /// AVB-7: `speak_get_call`. Same shape as `.submitCall` — no server-side wait,
    /// caller polls on its own interval. [decision: AVB-7]
    case getCall
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
    /// `ask`/`confirm`/`requestInput`: caller-requested timeout in seconds for the
    /// round-trip. Falls back to `CLIContract.askConfirmDefaultTimeoutSeconds` when
    /// nil. [decision: H-3]
    public let timeout: Double?

    // MARK: - AVB-5 requestInput fields

    /// `requestInput`: caller-supplied request identifier (spec §3 `AgentCall`).
    public let requestId: String?
    /// `requestInput`: optional idempotency key — a duplicate call for an
    /// in-flight request is refused as `.busy`, never queued (in-flight dedupe
    /// only; no durable replay in this slice). [decision: AVB-5]
    public let idempotencyKey: String?
    /// `requestInput`: the prompt to speak (unless `spokenSummary` overrides it)
    /// and listen for an answer to.
    public let prompt: String?
    /// `requestInput`: which of the three interaction shapes this request is.
    public let mode: RequestInputMode?
    /// `requestInput`: required (and non-empty) iff `mode == .choice`.
    public let choices: [String]?
    /// `requestInput`: optional human-readable statement of what answering
    /// implies — reserved for future presentation; not currently spoken.
    public let consequence: String?
    /// `requestInput`: what to actually speak aloud; defaults to `prompt` when nil.
    public let spokenSummary: String?

    // MARK: - AVB-6 session fields

    /// `say`/`ask`/`confirm`/`requestInput`/`status`: optional session
    /// attribution (spec §7.1). `registerSession`: optional existing
    /// sessionId to re-register instead of minting a new one. [decision: AVB-6]
    public let sessionId: String?
    /// `registerSession`: the agent client/provider identifier.
    public let provider: String?
    /// `registerSession`: human-readable label for the session.
    public let label: String?
    /// `registerSession`: the agent's working directory/repository, if known.
    public let workingDirectory: String?
    /// `registerSession`: capabilities the caller is requesting. The reply's
    /// `capabilities` is the intersection with what speak supports.
    public let requestedCapabilities: [String]?

    // MARK: - AVB-7 durable-call fields

    /// `getCall`: the id of the `AgentCall` to look up.
    public let callId: String?
    /// `submitCall`: caller-supplied urgency hint (never authority over presentation).
    public let urgency: AgentCallUrgency?
    /// `submitCall`: relative expiry window in seconds from submission time. Always
    /// concrete (never nil) when the request originates from `speak_submit_call` —
    /// the MCP tool layer applies `AgentCallDefaults.defaultExpirySeconds` before
    /// this field is populated. `nil` only for the internal `requestInput` durable
    /// side effect, which never goes over this wire path. [decision: AVB-7]
    public let expiresInSeconds: Double?

    public init(cmd: CLICommand, text: String? = nil, interrupt: Bool? = nil,
                question: String? = nil, timeout: Double? = nil,
                requestId: String? = nil, idempotencyKey: String? = nil,
                prompt: String? = nil, mode: RequestInputMode? = nil,
                choices: [String]? = nil, consequence: String? = nil,
                spokenSummary: String? = nil, sessionId: String? = nil,
                provider: String? = nil, label: String? = nil,
                workingDirectory: String? = nil, requestedCapabilities: [String]? = nil,
                callId: String? = nil, urgency: AgentCallUrgency? = nil,
                expiresInSeconds: Double? = nil) {
        self.cmd = cmd
        self.text = text
        self.interrupt = interrupt
        self.question = question
        self.timeout = timeout
        self.requestId = requestId
        self.idempotencyKey = idempotencyKey
        self.prompt = prompt
        self.mode = mode
        self.choices = choices
        self.consequence = consequence
        self.spokenSummary = spokenSummary
        self.sessionId = sessionId
        self.provider = provider
        self.label = label
        self.workingDirectory = workingDirectory
        self.requestedCapabilities = requestedCapabilities
        self.callId = callId
        self.urgency = urgency
        self.expiresInSeconds = expiresInSeconds
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
    /// Present in `requestInput` replies: the raw-value name of the
    /// `HumanResponseOutcome` case ("answered"/"declined"/"cancelled"/
    /// "timedOut"/"busy"). [decision: AVB-5]
    public let outcome: String?
    /// Present in `requestInput` replies only for an `.answered` outcome that
    /// matched a specific option — `.approval`'s "approved", or one of
    /// `.choice`'s `choices`. `answer` (above) carries the raw transcript text
    /// for the same case. [decision: AVB-5]
    public let choice: String?
    /// Present in `registerSession` replies: the (possibly server-generated)
    /// sessionId. [decision: AVB-6]
    public let sessionId: String?
    /// Present in `registerSession` replies: the negotiated capabilities —
    /// the intersection of the request's `requestedCapabilities` with what
    /// speak actually supports this slice. [decision: AVB-6]
    public let capabilities: [String]?
    /// Present on any reply when the request carried a `sessionId` that was
    /// not found in the registry — the call still proceeded normally
    /// (compatibility first). `nil` when no `sessionId` was supplied, or when
    /// it was supplied and recognized. [decision: AVB-6]
    public let sessionNote: String?

    // MARK: - AVB-7 durable-call fields

    /// Present in `submitCall`/`getCall` replies: the `AgentCall` — freshly created
    /// or the existing duplicate for `submitCall`; the looked-up call (or `nil` for
    /// not-found/isolation-mismatch, never an error) for `getCall`. Shared,
    /// Codable, not re-encoded across the MCP-process ↔ app-process boundary.
    /// [decision: AVB-7]
    public let agentCall: AgentCall?
    /// Present in `submitCall` replies only: `true` when this call was NOT newly
    /// created — the (sessionId, idempotencyKey) pair already had a live call, and
    /// `agentCall` carries the EXISTING one. [decision: AVB-7]
    public let duplicateSubmission: Bool?

    // MARK: - Factory helpers

    /// Accepted-ack for start/stop/say.
    public static func accepted(sessionNote: String? = nil) -> CLIReply {
        CLIReply(ok: true, error: nil, state: nil, binding: nil, answer: nil, confirmed: nil, sessionNote: sessionNote)
    }

    /// Error reply with a human-readable reason.
    public static func failure(_ message: String) -> CLIReply {
        CLIReply(ok: false, error: message, state: nil, binding: nil, answer: nil, confirmed: nil)
    }

    /// Status reply carrying live icon + binding.
    public static func status(state: CLIState, binding: String, sessionNote: String? = nil) -> CLIReply {
        CLIReply(ok: true, error: nil, state: state, binding: binding, answer: nil, confirmed: nil,
                 sessionNote: sessionNote)
    }

    /// `ask` reply carrying the spoken answer's transcript text.
    public static func asked(_ answer: String, sessionNote: String? = nil) -> CLIReply {
        CLIReply(ok: true, error: nil, state: nil, binding: nil, answer: answer, confirmed: nil,
                 sessionNote: sessionNote)
    }

    /// `confirm` reply carrying a deterministic yes/no, or `nil` when the spoken
    /// answer didn't match a recognized yes/no/cancel phrase ("unclear"). [decision: H-3]
    public static func confirmed(_ value: Bool?, sessionNote: String? = nil) -> CLIReply {
        CLIReply(ok: true, error: nil, state: nil, binding: nil, answer: nil, confirmed: value,
                 sessionNote: sessionNote)
    }

    /// `registerSession` reply carrying the (possibly re-used) sessionId and
    /// negotiated capabilities. [decision: AVB-6]
    public static func registered(sessionId: String, capabilities: [String]) -> CLIReply {
        CLIReply(ok: true, error: nil, state: nil, binding: nil, answer: nil, confirmed: nil,
                 sessionId: sessionId, capabilities: capabilities)
    }

    /// `requestInput` reply carrying one of the five canonical
    /// `HumanResponseOutcome` outcomes. Always `ok: true` — a refused/expired/
    /// cancelled request is a legitimate outcome, not a transport failure;
    /// `.failure(_:)` is reserved for malformed requests (bad mode, missing
    /// prompt) and internal errors. [decision: AVB-5]
    public static func requestInputResult(_ outcome: HumanResponseOutcome, sessionNote: String? = nil) -> CLIReply {
        switch outcome {
        case .answered(let text, let choice):
            return CLIReply(ok: true, error: nil, state: nil, binding: nil, answer: text,
                             confirmed: nil, outcome: "answered", choice: choice, sessionNote: sessionNote)
        case .declined:
            return CLIReply(ok: true, error: nil, state: nil, binding: nil, answer: nil,
                             confirmed: nil, outcome: "declined", choice: nil, sessionNote: sessionNote)
        case .cancelled:
            return CLIReply(ok: true, error: nil, state: nil, binding: nil, answer: nil,
                             confirmed: nil, outcome: "cancelled", choice: nil, sessionNote: sessionNote)
        case .timedOut:
            return CLIReply(ok: true, error: nil, state: nil, binding: nil, answer: nil,
                             confirmed: nil, outcome: "timedOut", choice: nil, sessionNote: sessionNote)
        case .busy:
            return CLIReply(ok: true, error: nil, state: nil, binding: nil, answer: nil,
                             confirmed: nil, outcome: "busy", choice: nil, sessionNote: sessionNote)
        }
    }

    public init(ok: Bool, error: String?, state: CLIState?, binding: String?,
                answer: String? = nil, confirmed: Bool? = nil,
                outcome: String? = nil, choice: String? = nil,
                sessionId: String? = nil, capabilities: [String]? = nil,
                sessionNote: String? = nil,
                agentCall: AgentCall? = nil, duplicateSubmission: Bool? = nil) {
        self.ok = ok
        self.error = error
        self.state = state
        self.binding = binding
        self.answer = answer
        self.confirmed = confirmed
        self.outcome = outcome
        self.choice = choice
        self.sessionId = sessionId
        self.capabilities = capabilities
        self.sessionNote = sessionNote
        self.agentCall = agentCall
        self.duplicateSubmission = duplicateSubmission
    }

    /// `submitCall` reply carrying the created (or, on a duplicate submission,
    /// existing) `AgentCall`. [decision: AVB-7]
    public static func callSubmitted(_ call: AgentCall, duplicate: Bool) -> CLIReply {
        CLIReply(ok: true, error: nil, state: nil, binding: nil, agentCall: call, duplicateSubmission: duplicate)
    }

    /// `getCall` reply carrying the looked-up `AgentCall`, or `nil` for
    /// not-found/isolation-mismatch (never an error — spec §8). [decision: AVB-7]
    public static func callStatus(_ call: AgentCall?) -> CLIReply {
        CLIReply(ok: true, error: nil, state: nil, binding: nil, agentCall: call)
    }

    /// Decode a `requestInput` reply's `outcome`/`answer`/`choice` fields back
    /// into a `HumanResponseOutcome`. `nil` when `outcome` is missing/unrecognized
    /// — the caller (`CLIBridgeBackend`) treats that as a transport error rather
    /// than guessing. [decision: AVB-5]
    public func decodedHumanResponseOutcome() -> HumanResponseOutcome? {
        switch outcome {
        case "answered": return .answered(text: answer, choice: choice)
        case "declined": return .declined
        case "cancelled": return .cancelled
        case "timedOut": return .timedOut
        case "busy": return .busy
        default: return nil
        }
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
