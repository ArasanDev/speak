// SpeakCore/AgentBridge/AgentBridgeServer.swift
//
// The MCP request dispatcher: decodes an inbound JSON-RPC message, routes it
// to the right handler (initialize / notifications/initialized / ping /
// tools/list / tools/call), and returns the outbound message to send (or
// `nil` when nothing should be sent). Pure Foundation, no I/O — the stdio
// read/write loop lives in `Speak/MCP/main.swift`; this actor is exercised in
// tests purely through in-memory `JSONRPCInbound`/`Data` values.
//
// Protocol version implemented: 2025-11-25, with 2025-06-18 also accepted
// (see MCPProtocolVersion.negotiate). [verified from:
// https://modelcontextprotocol.io/specification/2025-11-25/ — basic/lifecycle,
// basic/utilities/ping, server/tools — fetched 2026-07-06]

import Foundation

public actor AgentBridgeServer {
    private let backend: any BridgeBackend

    /// Tracks whether `notifications/initialized` has been received. Not
    /// enforced as a hard gate in this slice (a strict server could reject
    /// early requests with `invalidRequest`) — logged only, so a client that
    /// pipelines `tools/list` before the handshake fully completes still
    /// gets an answer. [decision H-3: lenient over strict for a v0 slice]
    private var didInitialize = false

    public init(backend: any BridgeBackend) {
        self.backend = backend
    }

    /// Handle one already-decoded inbound message. Returns the outbound
    /// message to send, or `nil` when nothing should be sent — a
    /// notification (including a successfully-handled
    /// `notifications/initialized`), or a malformed notification we can't
    /// meaningfully answer.
    public func handle(_ inbound: JSONRPCInbound) async -> JSONRPCOutbound? {
        switch inbound.method {
        case "initialize":
            return handleInitialize(inbound)

        case "notifications/initialized":
            didInitialize = true
            SpeakLog.agentBridge.info("AgentBridgeServer: client sent notifications/initialized.")
            return nil

        case "ping":
            // ping is always a request; a notification named "ping" has no
            // id to reply to.
            guard let id = inbound.id else { return nil }
            return .success(id: id, result: .object([:]))

        case "tools/list":
            guard let id = inbound.id else { return nil }
            logIfNotInitialized(inbound.method)
            return .success(id: id, result: .object(["tools": .array(AgentBridgeTools.all.map { $0.asJSONValue })]))

        case "tools/call":
            guard let id = inbound.id else { return nil }
            logIfNotInitialized(inbound.method)
            return await handleToolsCall(id: id, params: inbound.params)

        default:
            // Unknown REQUESTS get -32601 (Method not found); unknown
            // NOTIFICATIONS are silently ignored — a notification has no id
            // to reply on, and JSON-RPC gives the receiver no channel to
            // complain through. [decision H-3]
            guard let id = inbound.id else {
                SpeakLog.agentBridge.info(
                    "AgentBridgeServer: ignoring unknown notification '\(inbound.method, privacy: .public)'.")
                return nil
            }
            return .failure(
                id: id,
                error: JSONRPCErrorObject(code: JSONRPCErrorCode.methodNotFound,
                                           message: "Method not found: \(inbound.method)")
            )
        }
    }

    /// Convenience entry point: decode one line's raw JSON bytes, dispatch,
    /// and re-encode the reply (or return `nil` for no-reply cases). This is
    /// the single call `Speak/MCP/main.swift` makes per stdin line — still no
    /// file I/O here, only byte buffers in and out, so it stays testable with
    /// in-memory `Data` (see AgentBridgeServerTests).
    public func handleLine(_ data: Data) async -> Data? {
        let inbound: JSONRPCInbound
        do {
            inbound = try JSONRPCCodec.decodeInbound(data)
        } catch {
            // Parse error (JSON-RPC 2.0 §5.1): the request's own id could not
            // be recovered, so the reply's id MUST be null.
            let outbound = JSONRPCOutbound.failure(
                id: nil,
                error: JSONRPCErrorObject(code: JSONRPCErrorCode.parseError,
                                           message: "Parse error: \(error.localizedDescription)")
            )
            return try? JSONRPCCodec.encodeOutbound(outbound)
        }
        guard let outbound = await handle(inbound) else { return nil }
        return try? JSONRPCCodec.encodeOutbound(outbound)
    }

    // MARK: - initialize

    private func handleInitialize(_ inbound: JSONRPCInbound) -> JSONRPCOutbound? {
        guard let id = inbound.id else {
            // initialize is always a request per the lifecycle spec; a
            // notification named "initialize" is malformed and has no id to
            // reply to.
            return nil
        }
        let requested = inbound.params?.objectValue?["protocolVersion"]?.stringValue ?? MCPProtocolVersion.latest
        let negotiated = MCPProtocolVersion.negotiate(requested: requested)
        let result = MCPInitializeResult.speakMCP(protocolVersion: negotiated)
        SpeakLog.agentBridge.info(
            "AgentBridgeServer: initialize — client requested \(requested, privacy: .public), serving \(negotiated, privacy: .public)."
        )
        return .success(id: id, result: result.asJSONValue)
    }

    // MARK: - tools/call

    private func handleToolsCall(id: JSONRPCID, params: JSONValue?) async -> JSONRPCOutbound {
        guard let call = MCPToolCallRequest(params: params) else {
            return .failure(
                id: id,
                error: JSONRPCErrorObject(code: JSONRPCErrorCode.invalidParams,
                                           message: "tools/call requires a string 'name' field.")
            )
        }
        guard AgentBridgeTools.all.contains(where: { $0.name == call.name }) else {
            // Matches the MCP tools spec's own protocol-error example
            // verbatim: an unknown tool is -32602, not a tool execution error.
            return .failure(
                id: id,
                error: JSONRPCErrorObject(code: JSONRPCErrorCode.invalidParams,
                                           message: "Unknown tool: \(call.name)")
            )
        }
        let result = await runTool(call)
        return .success(id: id, result: result.asJSONValue)
    }

    private func runTool(_ call: MCPToolCallRequest) async -> MCPToolCallResult {
        // AVB-6: every tool below accepts an optional 'sessionId' — absent
        // means "exactly today's behavior" for all of them. [decision: AVB-6]
        let sessionId = call.arguments["sessionId"]?.stringValue

        switch call.name {
        case "speak_register_session":
            return await runRegisterSessionTool(call)

        case "speak_status":
            let outcome = await backend.status(sessionId: sessionId)
            return Self.render(outcome.value, sessionNote: outcome.sessionNote)

        case "speak_notify":
            return await runNotifyTool(call, sessionId: sessionId)

        case "speak_say":
            return await runSayTool(call, sessionId: sessionId)

        case "speak_ask":
            return await runAskTool(call, sessionId: sessionId)

        case "speak_confirm":
            return await runConfirmTool(call, sessionId: sessionId)

        case "speak_request_input":
            return await runRequestInputTool(call, sessionId: sessionId)

        case "speak_submit_call":
            return await runSubmitCallTool(call, sessionId: sessionId)

        case "speak_get_call":
            return await runGetCallTool(call, sessionId: sessionId)

        default:
            // Unreachable: handleToolsCall already checked membership in
            // AgentBridgeTools.all before calling runTool.
            return .error("Unknown tool: \(call.name)")
        }
    }

    private func runNotifyTool(_ call: MCPToolCallRequest, sessionId: String?) async -> MCPToolCallResult {
        guard let summary = call.arguments["summary"]?.stringValue?
            .trimmingCharacters(in: .whitespacesAndNewlines), !summary.isEmpty else {
            return .error("speak_notify requires a non-empty 'summary' argument.")
        }
        let kind = call.arguments["kind"]?.stringValue ?? "completion"
        let allowedKinds = ["completion", "blocked", "warning", "requested"]
        guard allowedKinds.contains(kind) else {
            return .error("speak_notify 'kind' must be completion, blocked, warning, or requested.")
        }
        let interrupt = call.arguments["interrupt"]?.boolValue ?? false
        switch await backend.say(text: summary, interrupt: interrupt, sessionId: sessionId) {
        case .success(let outcome):
            return .text(Self.appendingNote("notification accepted (kind: \(kind)).", outcome.sessionNote))
        case .failure(let reason):
            return .error(reason.description)
        }
    }

    private func runSayTool(_ call: MCPToolCallRequest, sessionId: String?) async -> MCPToolCallResult {
        guard let text = call.arguments["text"]?.stringValue, !text.isEmpty else {
            return .error("speak_say requires a non-empty 'text' argument.")
        }
        let interrupt = call.arguments["interrupt"]?.boolValue ?? false
        switch await backend.say(text: text, interrupt: interrupt, sessionId: sessionId) {
        case .success(let outcome): return .text(Self.appendingNote("spoken.", outcome.sessionNote))
        case .failure(let reason): return .error(reason.description)
        }
    }

    private func runAskTool(_ call: MCPToolCallRequest, sessionId: String?) async -> MCPToolCallResult {
        guard let question = call.arguments["question"]?.stringValue, !question.isEmpty else {
            return .error("speak_ask requires a non-empty 'question' argument.")
        }
        let timeout = call.arguments["timeout"]?.doubleValue
        switch await backend.ask(question: question, timeoutSeconds: timeout, sessionId: sessionId) {
        case .success(let outcome): return .text(Self.appendingNote(outcome.value, outcome.sessionNote))
        case .failure(let reason): return .error(reason.description)
        }
    }

    private func runConfirmTool(_ call: MCPToolCallRequest, sessionId: String?) async -> MCPToolCallResult {
        guard let question = call.arguments["question"]?.stringValue, !question.isEmpty else {
            return .error("speak_confirm requires a non-empty 'question' argument.")
        }
        switch await backend.confirm(question: question, sessionId: sessionId) {
        case .success(let outcome):
            return .text(Self.appendingNote(outcome.value ? "yes" : "no", outcome.sessionNote))
        case .failure(let reason): return .error(reason.description)
        }
    }

    // MARK: - AVB-6 speak_register_session

    private func runRegisterSessionTool(_ call: MCPToolCallRequest) async -> MCPToolCallResult {
        guard let provider = call.arguments["provider"]?.stringValue, !provider.isEmpty else {
            return .error("speak_register_session requires a non-empty 'provider' argument.")
        }
        guard let label = call.arguments["label"]?.stringValue, !label.isEmpty else {
            return .error("speak_register_session requires a non-empty 'label' argument.")
        }
        let workingDirectory = call.arguments["cwd"]?.stringValue
        let requestedCapabilities = call.arguments["capabilities"]?.arrayValue?.compactMap { $0.stringValue } ?? []
        let existingSessionId = call.arguments["sessionId"]?.stringValue

        let result = await backend.registerSession(
            sessionId: existingSessionId,
            provider: provider,
            label: label,
            workingDirectory: workingDirectory,
            requestedCapabilities: requestedCapabilities
        )
        switch result {
        case .success(let registration):
            let fields: [String: JSONValue] = [
                "sessionId": .string(registration.sessionId),
                "capabilities": .array(registration.capabilities.map { .string($0) })
            ]
            let data = (try? JSONEncoder().encode(JSONValue.object(fields))) ?? Data()
            let jsonString = String(data: data, encoding: .utf8) ?? "{}"
            return .text(jsonString)
        case .failure(let reason):
            return .error(reason.description)
        }
    }

    /// Appends an AVB-6 sessionNote to a successful tool result's text, when
    /// present. `nil` note (no sessionId supplied, or a recognized one) leaves
    /// the text unchanged. [decision: AVB-6]
    private static func appendingNote(_ text: String, _ note: String?) -> String {
        guard let note else { return text }
        return "\(text)\n\(note)"
    }

    // MARK: - AVB-5 speak_request_input

    private func runRequestInputTool(_ call: MCPToolCallRequest, sessionId: String?) async -> MCPToolCallResult {
        guard let requestId = call.arguments["requestId"]?.stringValue, !requestId.isEmpty else {
            return .error("speak_request_input requires a non-empty 'requestId' argument.")
        }
        guard let prompt = call.arguments["prompt"]?.stringValue, !prompt.isEmpty else {
            return .error("speak_request_input requires a non-empty 'prompt' argument.")
        }
        guard let modeRaw = call.arguments["mode"]?.stringValue, let mode = RequestInputMode(rawValue: modeRaw) else {
            return .error("speak_request_input 'mode' must be one of freeform, choice, approval.")
        }
        let choices = call.arguments["choices"]?.arrayValue?.compactMap { $0.stringValue }
        if mode == .choice, (choices ?? []).isEmpty {
            return .error("speak_request_input mode 'choice' requires a non-empty 'choices' array.")
        }

        let result = await backend.requestInput(RequestInputCall(
            requestId: requestId,
            idempotencyKey: call.arguments["idempotencyKey"]?.stringValue,
            prompt: prompt,
            mode: mode,
            choices: choices,
            timeoutSeconds: call.arguments["timeout"]?.doubleValue,
            consequence: call.arguments["consequence"]?.stringValue,
            spokenSummary: call.arguments["spokenSummary"]?.stringValue,
            sessionId: sessionId
        ))
        switch result {
        case .success(let outcome):
            // [decision: AVB-5 — locked] In choice/approval mode, an `.answered`
            // outcome with no matched choice is an ambiguous spoken answer — a
            // tool execution error, never a false-positive success. Freeform
            // never has this ambiguity (choice is always nil by design there).
            if mode != .freeform, case .answered(_, nil) = outcome.value {
                let expected = mode == .choice ? "any of the offered choices" : "a recognizable yes/no"
                return .error("speak_request_input got an answer that didn't match \(expected).")
            }
            return Self.renderRequestInput(outcome.value, sessionNote: outcome.sessionNote)
        case .failure(let reason):
            return .error(reason.description)
        }
    }

    /// Structured `{outcome, text?, choice?}` JSON, serialized into the one text
    /// content block `MCPContentBlock` supports (no structured-content block type
    /// exists in this hand-written MCP layer — matches the rest of this file's
    /// "no schema-generation library" posture). [decision: AVB-5]
    private static func renderRequestInput(_ outcome: HumanResponseOutcome, sessionNote: String?) -> MCPToolCallResult {
        var fields: [String: JSONValue] = [:]
        switch outcome {
        case .answered(let text, let choice):
            fields["outcome"] = .string("answered")
            if let text { fields["text"] = .string(text) }
            if let choice { fields["choice"] = .string(choice) }
        case .declined:
            fields["outcome"] = .string("declined")
        case .cancelled:
            fields["outcome"] = .string("cancelled")
        case .timedOut:
            fields["outcome"] = .string("timedOut")
        case .busy:
            fields["outcome"] = .string("busy")
        }
        if let sessionNote { fields["sessionNote"] = .string(sessionNote) }
        let data = (try? JSONEncoder().encode(JSONValue.object(fields))) ?? Data()
        let jsonString = String(data: data, encoding: .utf8) ?? "{}"
        return .text(jsonString)
    }

    // MARK: - AVB-7 speak_submit_call / speak_get_call

    private func runSubmitCallTool(_ call: MCPToolCallRequest, sessionId: String?) async -> MCPToolCallResult {
        guard let sessionId, !sessionId.isEmpty else {
            return .error("speak_submit_call requires a 'sessionId' — call speak_register_session first.")
        }
        guard let requestId = call.arguments["requestId"]?.stringValue, !requestId.isEmpty else {
            return .error("speak_submit_call requires a non-empty 'requestId' argument.")
        }
        guard let prompt = call.arguments["prompt"]?.stringValue, !prompt.isEmpty else {
            return .error("speak_submit_call requires a non-empty 'prompt' argument.")
        }
        guard let modeRaw = call.arguments["mode"]?.stringValue, let mode = RequestInputMode(rawValue: modeRaw) else {
            return .error("speak_submit_call 'mode' must be one of freeform, choice, approval.")
        }
        let choices = call.arguments["choices"]?.arrayValue?.compactMap { $0.stringValue } ?? []
        if mode == .choice, choices.isEmpty {
            return .error("speak_submit_call mode 'choice' requires a non-empty 'choices' array.")
        }
        let urgency = call.arguments["urgency"]?.stringValue.flatMap(AgentCallUrgency.init(rawValue:)) ?? .normal
        // [decision: AVB-7 orchestrator amendment 1] Never nil past this point —
        // an abandoned agent must not leave an immortal pending call in the inbox.
        let expiresInSeconds = call.arguments["expiresInSeconds"]?.doubleValue
            ?? AgentCallDefaults.defaultExpirySeconds

        let args = SubmitCallArguments(
            requestId: requestId,
            idempotencyKey: call.arguments["idempotencyKey"]?.stringValue,
            prompt: prompt,
            mode: mode,
            choices: choices,
            consequence: call.arguments["consequence"]?.stringValue,
            spokenSummary: call.arguments["spokenSummary"]?.stringValue,
            urgency: urgency,
            expiresInSeconds: expiresInSeconds,
            sessionId: sessionId
        )
        switch await backend.submitCall(args) {
        case .success(let outcome):
            return Self.renderSubmitCall(outcome.value, sessionNote: outcome.sessionNote)
        case .failure(let reason):
            return .error(reason.description)
        }
    }

    private func runGetCallTool(_ call: MCPToolCallRequest, sessionId: String?) async -> MCPToolCallResult {
        guard let sessionId, !sessionId.isEmpty else {
            return .error("speak_get_call requires a 'sessionId' — call speak_register_session first.")
        }
        guard let callIdString = call.arguments["callId"]?.stringValue, let callId = UUID(uuidString: callIdString) else {
            return .error("speak_get_call requires a valid 'callId' argument.")
        }
        switch await backend.getCall(callId: callId, sessionId: sessionId) {
        case .success(let outcome):
            guard let agentCall = outcome.value else {
                return .error("speak_get_call: no such call for this session.")
            }
            return Self.renderAgentCall(agentCall, extraFields: [:], sessionNote: outcome.sessionNote)
        case .failure(let reason):
            return .error(reason.description)
        }
    }

    private static func renderSubmitCall(_ outcome: AgentCallSubmitOutcome, sessionNote: String?) -> MCPToolCallResult {
        renderAgentCall(outcome.call, extraFields: ["duplicate": .bool(outcome.duplicate)], sessionNote: sessionNote)
    }

    /// Shared `{callId, state, ...}` JSON rendering for both `speak_submit_call`
    /// and `speak_get_call` — one shape for both tools, matching
    /// `renderRequestInput`'s "no schema-generation library" posture.
    /// [decision: AVB-7]
    private static func renderAgentCall(
        _ agentCall: AgentCall, extraFields: [String: JSONValue], sessionNote: String?
    ) -> MCPToolCallResult {
        var fields: [String: JSONValue] = [
            "callId": .string(agentCall.id.uuidString),
            "state": .string(agentCall.state.rawValue)
        ]
        if let response = agentCall.response {
            switch response {
            case .answered(let text, let choice):
                if let text { fields["text"] = .string(text) }
                if let choice { fields["choice"] = .string(choice) }
            default:
                break
            }
        }
        for (key, value) in extraFields { fields[key] = value }
        if let sessionNote { fields["sessionNote"] = .string(sessionNote) }
        let data = (try? JSONEncoder().encode(JSONValue.object(fields))) ?? Data()
        let jsonString = String(data: data, encoding: .utf8) ?? "{}"
        return .text(jsonString)
    }

    private static func render(_ report: BridgeStatusReport, sessionNote: String?) -> MCPToolCallResult {
        guard report.appRunning else {
            return .error(report.detail ?? BridgeUnavailable.appNotRunning.reason)
        }
        var lines = ["speak is running.", "state: \(report.engineState ?? "unknown")"]
        if let binding = report.hotkeyBinding { lines.append("hotkey: \(binding)") }
        if let detail = report.detail { lines.append(detail) }
        if let sessionNote { lines.append(sessionNote) }
        return .text(lines.joined(separator: "\n"))
    }

    private func logIfNotInitialized(_ method: String) {
        guard !didInitialize else { return }
        SpeakLog.agentBridge.info(
            "AgentBridgeServer: '\(method, privacy: .public)' received before notifications/initialized — serving anyway (lenient).")
    }
}
