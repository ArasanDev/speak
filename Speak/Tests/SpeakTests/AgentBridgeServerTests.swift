// SpeakTests/AgentBridgeServerTests.swift
//
// H-3: MCP agent-bridge vertical slice (specs/horizon-voice-os.md Pillar 3).
// Full request/response conformance for the JSON-RPC/MCP protocol layer in
// SpeakCore/AgentBridge/ — initialize, tools/list, tools/call happy + error
// paths — driven entirely through in-memory `JSONRPCInbound`/`Data` values
// (no stdin/stdout, no live speak.app). `CLIBridgeBackend` is covered
// separately with `StubCLITransport` (already defined in
// CLIContractTests.swift, reused here).

import Foundation
import Testing
@testable import SpeakCore

// MARK: - Test double

/// A configurable `BridgeBackend` for exercising `AgentBridgeServer` without
/// any real transport — the seam pattern used throughout SpeakCore
/// (MockCleaner-equivalent for the AgentBridge layer).
/// `internal` (not `private`) so `AgentBridgeServerAVB7Tests.swift` (split out
/// for [lint] type_body_length) can reuse it. [decision: AVB-7]
final class StubBridgeBackend: BridgeBackend, @unchecked Sendable {
    var statusResult: BridgeStatusReport
    var sayResult: Result<Void, BridgeUnavailable>
    var askResult: Result<String, BridgeUnavailable>
    var confirmResult: Result<Bool, BridgeUnavailable>
    var requestInputResult: Result<HumanResponseOutcome, BridgeUnavailable>
    var registerSessionResult: Result<(sessionId: String, capabilities: [String]), BridgeUnavailable>
    var submitCallResult: Result<AgentCallSubmitOutcome, BridgeUnavailable>
    var getCallResult: Result<AgentCall?, BridgeUnavailable>
    /// Set to make the corresponding tool call's `BridgeOutcome.sessionNote` non-nil.
    var sessionNote: String?
    private(set) var lastSaidText: String?
    private(set) var lastInterrupt: Bool?
    private(set) var lastRequestInputMode: RequestInputMode?
    private(set) var lastRequestInputChoices: [String]?
    private(set) var lastSessionId: String?
    private(set) var lastRegisterProvider: String?
    private(set) var lastRegisterLabel: String?
    private(set) var lastRegisterCapabilities: [String]?
    private(set) var lastSubmitCallArgs: SubmitCallArguments?
    private(set) var lastGetCallId: UUID?

    init(
        status: BridgeStatusReport = BridgeStatusReport(
            appRunning: true, engineState: "idle", hotkeyBinding: "Fn ×2", detail: nil
        ),
        say: Result<Void, BridgeUnavailable> = .success(()),
        ask: Result<String, BridgeUnavailable> = .success("blue"),
        confirm: Result<Bool, BridgeUnavailable> = .success(true),
        requestInput: Result<HumanResponseOutcome, BridgeUnavailable> = .success(.answered(text: "blue", choice: nil)),
        registerSession: Result<(sessionId: String, capabilities: [String]), BridgeUnavailable> =
            .success((sessionId: "generated-id", capabilities: ["notify", "say"])),
        submitCall: Result<AgentCallSubmitOutcome, BridgeUnavailable>? = nil,
        getCall: Result<AgentCall?, BridgeUnavailable> = .success(nil),
        sessionNote: String? = nil
    ) {
        self.statusResult = status
        self.sayResult = say
        self.askResult = ask
        self.confirmResult = confirm
        self.requestInputResult = requestInput
        self.registerSessionResult = registerSession
        self.submitCallResult = submitCall ?? .success(
            AgentCallSubmitOutcome(
                call: AgentCall(
                    id: UUID(), sessionId: "s1", requestId: "r1", idempotencyKey: nil, prompt: "p",
                    mode: .freeform, choices: [], consequence: nil, spokenSummary: nil, urgency: .normal,
                    state: .pending, createdAt: Date(), expiresAt: Date().addingTimeInterval(86_400)
                ),
                duplicate: false
            )
        )
        self.getCallResult = getCall
        self.sessionNote = sessionNote
    }

    func status(sessionId: String?) async -> BridgeOutcome<BridgeStatusReport> {
        lastSessionId = sessionId
        return BridgeOutcome(statusResult, sessionNote: sessionNote)
    }
    func say(text: String, interrupt: Bool, sessionId: String?) async -> Result<BridgeOutcome<Void>, BridgeUnavailable> {
        lastSaidText = text
        lastInterrupt = interrupt
        lastSessionId = sessionId
        return sayResult.map { BridgeOutcome($0, sessionNote: sessionNote) }
    }
    func ask(
        question: String, timeoutSeconds: Double?, sessionId: String?
    ) async -> Result<BridgeOutcome<String>, BridgeUnavailable> {
        lastSessionId = sessionId
        return askResult.map { BridgeOutcome($0, sessionNote: sessionNote) }
    }
    func confirm(question: String, sessionId: String?) async -> Result<BridgeOutcome<Bool>, BridgeUnavailable> {
        lastSessionId = sessionId
        return confirmResult.map { BridgeOutcome($0, sessionNote: sessionNote) }
    }

    func requestInput(
        _ call: RequestInputCall
    ) async -> Result<BridgeOutcome<HumanResponseOutcome>, BridgeUnavailable> {
        lastRequestInputMode = call.mode
        lastRequestInputChoices = call.choices
        lastSessionId = call.sessionId
        return requestInputResult.map { BridgeOutcome($0, sessionNote: sessionNote) }
    }

    func registerSession(
        sessionId: String?,
        provider: String,
        label: String,
        workingDirectory: String?,
        requestedCapabilities: [String]
    ) async -> Result<(sessionId: String, capabilities: [String]), BridgeUnavailable> {
        lastSessionId = sessionId
        lastRegisterProvider = provider
        lastRegisterLabel = label
        lastRegisterCapabilities = requestedCapabilities
        return registerSessionResult
    }

    func submitCall(_ args: SubmitCallArguments) async -> Result<BridgeOutcome<AgentCallSubmitOutcome>, BridgeUnavailable> {
        lastSubmitCallArgs = args
        lastSessionId = args.sessionId
        return submitCallResult.map { BridgeOutcome($0, sessionNote: sessionNote) }
    }

    func getCall(callId: UUID, sessionId: String?) async -> Result<BridgeOutcome<AgentCall?>, BridgeUnavailable> {
        lastGetCallId = callId
        lastSessionId = sessionId
        return getCallResult.map { BridgeOutcome($0, sessionNote: sessionNote) }
    }
}

// MARK: - JSONValue codec

@Suite("JSONValue codec")
struct JSONValueCodecTests {
    @Test("round-trips every case")
    func roundTrip() throws {
        let value: JSONValue = .object([
            "s": .string("hi"),
            "n": .number(3.5),
            "b": .bool(true),
            "nul": .null,
            "arr": .array([.number(1), .number(2)])
        ])
        let data = try JSONEncoder().encode(value)
        let decoded = try JSONDecoder().decode(JSONValue.self, from: data)
        #expect(decoded == value)
    }

    @Test("literal conveniences build the expected shape")
    func literals() {
        let schema: JSONValue = ["type": "object", "required": ["text"]]
        #expect(schema.objectValue?["type"]?.stringValue == "object")
        #expect(schema.objectValue?["required"]?.arrayValue?.first?.stringValue == "text")
    }
}

// MARK: - JSON-RPC envelope

@Suite("JSON-RPC envelope")
struct JSONRPCEnvelopeTests {
    @Test("decodes a request (id present) as non-notification")
    func decodesRequest() throws {
        let data = Data(#"{"jsonrpc":"2.0","id":1,"method":"ping"}"#.utf8)
        let inbound = try JSONRPCCodec.decodeInbound(data)
        #expect(inbound.id == .number(1))
        #expect(inbound.method == "ping")
        #expect(!inbound.isNotification)
    }

    @Test("decodes a notification (no id) as isNotification")
    func decodesNotification() throws {
        let data = Data(#"{"jsonrpc":"2.0","method":"notifications/initialized"}"#.utf8)
        let inbound = try JSONRPCCodec.decodeInbound(data)
        #expect(inbound.id == nil)
        #expect(inbound.isNotification)
    }

    @Test("string ids round-trip")
    func stringID() throws {
        let data = Data(#"{"jsonrpc":"2.0","id":"abc","method":"ping"}"#.utf8)
        let inbound = try JSONRPCCodec.decodeInbound(data)
        #expect(inbound.id == .string("abc"))
    }

    @Test("malformed JSON throws")
    func malformedThrows() {
        #expect(throws: (any Error).self) {
            try JSONRPCCodec.decodeInbound(Data("not-json".utf8))
        }
    }

    @Test("success response omits the error key")
    func successOmitsError() throws {
        let outbound = JSONRPCOutbound.success(id: .number(1), result: .object([:]))
        let data = try JSONRPCCodec.encodeOutbound(outbound)
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(json["result"] != nil)
        #expect(json["error"] == nil)
    }

    @Test("failure response omits the result key and carries the error code")
    func failureOmitsResult() throws {
        let outbound = JSONRPCOutbound.failure(
            id: .number(2),
            error: JSONRPCErrorObject(code: JSONRPCErrorCode.methodNotFound, message: "nope")
        )
        let data = try JSONRPCCodec.encodeOutbound(outbound)
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(json["result"] == nil)
        let error = try #require(json["error"] as? [String: Any])
        #expect(error["code"] as? Int == -32601)
    }

    @Test("a parse-error failure encodes a null id")
    func parseErrorHasNullID() throws {
        let outbound = JSONRPCOutbound.failure(
            id: nil,
            error: JSONRPCErrorObject(code: JSONRPCErrorCode.parseError, message: "bad")
        )
        let data = try JSONRPCCodec.encodeOutbound(outbound)
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(json["id"] is NSNull)
    }
}

// MARK: - Protocol version negotiation

@Suite("MCPProtocolVersion")
struct MCPProtocolVersionTests {
    @Test("echoes back the latest version when requested")
    func echoesLatest() {
        #expect(MCPProtocolVersion.negotiate(requested: "2025-11-25") == "2025-11-25")
    }

    @Test("echoes back Claude Code's current version (2025-06-18) unchanged")
    func echoesClaudeCodeVersion() {
        #expect(MCPProtocolVersion.negotiate(requested: "2025-06-18") == "2025-06-18")
    }

    @Test("falls back to latest for an unsupported version")
    func fallsBackForUnsupported() {
        #expect(MCPProtocolVersion.negotiate(requested: "1999-01-01") == MCPProtocolVersion.latest)
    }
}

// MARK: - AgentBridgeServer: initialize / notifications / ping

@Suite("AgentBridgeServer handshake")
struct AgentBridgeServerHandshakeTests {
    @Test("initialize negotiates the requested protocol version and returns serverInfo")
    func initializeHappyPath() async throws {
        let server = AgentBridgeServer(backend: StubBridgeBackend())
        let inbound = JSONRPCInbound(
            id: .number(1), method: "initialize",
            params: .object(["protocolVersion": .string("2025-06-18"), "capabilities": .object([:]),
                              "clientInfo": .object(["name": .string("Claude Code"), "version": .string("1.0")])])
        )
        let outbound = try #require(await server.handle(inbound))
        #expect(outbound.error == nil)
        let result = try #require(outbound.result?.objectValue)
        #expect(result["protocolVersion"]?.stringValue == "2025-06-18")
        #expect(result["serverInfo"]?.objectValue?["name"]?.stringValue == "speak-mcp")
        #expect(result["capabilities"]?.objectValue?["tools"] != nil)
    }

    @Test("initialize falls back to the latest version for an unsupported request")
    func initializeUnsupportedVersion() async throws {
        let server = AgentBridgeServer(backend: StubBridgeBackend())
        let inbound = JSONRPCInbound(id: .number(1), method: "initialize",
                                     params: .object(["protocolVersion": .string("1999-01-01")]))
        let outbound = try #require(await server.handle(inbound))
        #expect(outbound.result?.objectValue?["protocolVersion"]?.stringValue == MCPProtocolVersion.latest)
    }

    @Test("notifications/initialized produces no reply")
    func initializedNotificationNoReply() async {
        let server = AgentBridgeServer(backend: StubBridgeBackend())
        let inbound = JSONRPCInbound(id: nil, method: "notifications/initialized", params: nil)
        let outbound = await server.handle(inbound)
        #expect(outbound == nil)
    }

    @Test("ping returns an empty result object")
    func pingReturnsEmptyResult() async throws {
        let server = AgentBridgeServer(backend: StubBridgeBackend())
        let inbound = JSONRPCInbound(id: .string("123"), method: "ping", params: nil)
        let outbound = try #require(await server.handle(inbound))
        #expect(outbound.id == .string("123"))
        #expect(outbound.result?.objectValue?.isEmpty == true)
    }

    @Test("an unknown method as a request returns -32601")
    func unknownMethodRequest() async throws {
        let server = AgentBridgeServer(backend: StubBridgeBackend())
        let inbound = JSONRPCInbound(id: .number(9), method: "resources/list", params: nil)
        let outbound = try #require(await server.handle(inbound))
        #expect(outbound.error?.code == JSONRPCErrorCode.methodNotFound)
    }

    @Test("an unknown method as a notification produces no reply (never errors a notification)")
    func unknownMethodNotification() async {
        let server = AgentBridgeServer(backend: StubBridgeBackend())
        let inbound = JSONRPCInbound(id: nil, method: "notifications/whatever", params: nil)
        let outbound = await server.handle(inbound)
        #expect(outbound == nil)
    }
}

// MARK: - AgentBridgeServer: tools/list

@Suite("AgentBridgeServer tools/list")
struct AgentBridgeServerToolsListTests {
    @Test("lists the product notification tool, speak_request_input, and its compatibility wrappers")
    func listsAllTools() async throws {
        let server = AgentBridgeServer(backend: StubBridgeBackend())
        let inbound = JSONRPCInbound(id: .number(1), method: "tools/list", params: nil)
        let outbound = try #require(await server.handle(inbound))
        let tools = try #require(outbound.result?.objectValue?["tools"]?.arrayValue)
        let names = Set(tools.compactMap { $0.objectValue?["name"]?.stringValue })
        #expect(names == [
            "speak_register_session", "speak_notify", "speak_say", "speak_ask", "speak_confirm",
            "speak_request_input", "speak_status", "speak_submit_call", "speak_get_call"
        ])
    }

    @Test("speak_notify requires a summary and constrains notification kinds")
    func notifySchema() async throws {
        let server = AgentBridgeServer(backend: StubBridgeBackend())
        let inbound = JSONRPCInbound(id: .number(1), method: "tools/list", params: nil)
        let outbound = try #require(await server.handle(inbound))
        let tools = try #require(outbound.result?.objectValue?["tools"]?.arrayValue)
        let notify = try #require(tools.first { $0.objectValue?["name"]?.stringValue == "speak_notify" })
        let schema = try #require(notify.objectValue?["inputSchema"]?.objectValue)
        #expect(schema["required"]?.arrayValue?.first?.stringValue == "summary")
        let kinds = schema["properties"]?.objectValue?["kind"]?.objectValue?["enum"]?.arrayValue?
            .compactMap(\.stringValue)
        #expect(kinds == ["completion", "blocked", "warning", "requested"])
    }

    @Test("every tool has a non-empty description and an object inputSchema")
    func toolsHaveSchemas() async throws {
        let server = AgentBridgeServer(backend: StubBridgeBackend())
        let inbound = JSONRPCInbound(id: .number(1), method: "tools/list", params: nil)
        let outbound = try #require(await server.handle(inbound))
        let tools = try #require(outbound.result?.objectValue?["tools"]?.arrayValue)
        for tool in tools {
            let obj = try #require(tool.objectValue)
            let description = obj["description"]?.stringValue ?? ""
            #expect(description.isEmpty == false)
            #expect(obj["inputSchema"]?.objectValue?["type"]?.stringValue == "object")
        }
    }

    @Test("speak_status takes no required arguments")
    func statusHasNoRequiredArgs() async throws {
        let server = AgentBridgeServer(backend: StubBridgeBackend())
        let inbound = JSONRPCInbound(id: .number(1), method: "tools/list", params: nil)
        let outbound = try #require(await server.handle(inbound))
        let tools = try #require(outbound.result?.objectValue?["tools"]?.arrayValue)
        let status = try #require(tools.first { $0.objectValue?["name"]?.stringValue == "speak_status" })
        #expect(status.objectValue?["inputSchema"]?.objectValue?["required"] == nil)
    }
}

// MARK: - AgentBridgeServer: tools/call

@Suite("AgentBridgeServer tools/call")
struct AgentBridgeServerToolsCallTests {
    private func call(_ server: AgentBridgeServer, name: String, arguments: [String: JSONValue] = [:]) async throws -> JSONRPCOutbound {
        let params: JSONValue = .object(["name": .string(name), "arguments": .object(arguments)])
        let inbound = JSONRPCInbound(id: .number(1), method: "tools/call", params: params)
        return try #require(await server.handle(inbound))
    }

    @Test("speak_status happy path reports running state, isError=false")
    func statusHappyPath() async throws {
        let backend = StubBridgeBackend(status: BridgeStatusReport(
            appRunning: true, engineState: "listening", hotkeyBinding: "Fn ×2", detail: nil
        ))
        let server = AgentBridgeServer(backend: backend)
        let outbound = try await call(server, name: "speak_status")
        let result = try #require(outbound.result?.objectValue)
        #expect(result["isError"]?.boolValue == false)
        let text = result["content"]?.arrayValue?.first?.objectValue?["text"]?.stringValue ?? ""
        #expect(text.contains("listening"))
    }

    @Test("speak_status when the app is not running is a tool execution error")
    func statusAppNotRunning() async throws {
        let backend = StubBridgeBackend(status: BridgeStatusReport(
            appRunning: false, engineState: nil, hotkeyBinding: nil, detail: BridgeUnavailable.appNotRunning.reason
        ))
        let server = AgentBridgeServer(backend: backend)
        let outbound = try await call(server, name: "speak_status")
        let result = try #require(outbound.result?.objectValue)
        #expect(result["isError"]?.boolValue == true)
        #expect(outbound.error == nil)  // still a JSON-RPC success — this is a tool-level error
    }

    @Test("speak_say with a running backend is a clean success result")
    func saySucceeds() async throws {
        let server = AgentBridgeServer(backend: StubBridgeBackend())
        let outbound = try await call(server, name: "speak_say", arguments: ["text": .string("hello")])
        let result = try #require(outbound.result?.objectValue)
        #expect(result["isError"]?.boolValue == nil || result["isError"]?.boolValue == false)
        #expect(outbound.error == nil)
    }

    @Test("speak_notify speaks only its trimmed summary and forwards interruption policy")
    func notifySucceeds() async throws {
        let backend = StubBridgeBackend()
        let server = AgentBridgeServer(backend: backend)
        let outbound = try await call(server, name: "speak_notify", arguments: [
            "summary": .string("  Build finished.  "),
            "kind": .string("completion"),
            "detail": .string("A long diff stays visual."),
            "interrupt": .bool(true)
        ])
        let result = try #require(outbound.result?.objectValue)
        #expect(result["isError"]?.boolValue == nil || result["isError"]?.boolValue == false)
        #expect(backend.lastSaidText == "Build finished.")
        #expect(backend.lastInterrupt == true)
        let text = result["content"]?.arrayValue?.first?.objectValue?["text"]?.stringValue ?? ""
        #expect(text.contains("completion"))
    }

    @Test("speak_notify rejects missing summaries and unknown kinds")
    func notifyValidation() async throws {
        let server = AgentBridgeServer(backend: StubBridgeBackend())
        let missing = try await call(server, name: "speak_notify")
        #expect(missing.result?.objectValue?["isError"]?.boolValue == true)

        let unknownKind = try await call(server, name: "speak_notify", arguments: [
            "summary": .string("Done"), "kind": .string("routine")
        ])
        #expect(unknownKind.result?.objectValue?["isError"]?.boolValue == true)
    }

    @Test("speak_say missing the required 'text' argument is a tool execution error")
    func sayMissingText() async throws {
        let server = AgentBridgeServer(backend: StubBridgeBackend())
        let outbound = try await call(server, name: "speak_say")
        let result = try #require(outbound.result?.objectValue)
        #expect(result["isError"]?.boolValue == true)
    }

    @Test("speak_ask with a running backend returns the spoken answer as text")
    func askSucceeds() async throws {
        let server = AgentBridgeServer(backend: StubBridgeBackend())
        let outbound = try await call(server, name: "speak_ask", arguments: ["question": .string("coffee or tea?")])
        let result = try #require(outbound.result?.objectValue)
        #expect(result["isError"]?.boolValue == nil || result["isError"]?.boolValue == false)
        let text = result["content"]?.arrayValue?.first?.objectValue?["text"]?.stringValue ?? ""
        #expect(text == "blue")
    }

    @Test("speak_ask reports a clean tool execution error (not a protocol error) when the backend times out")
    func askTimeoutIsToolError() async throws {
        let server = AgentBridgeServer(backend: StubBridgeBackend(ask: .failure(.timedOut("speak_ask"))))
        let outbound = try await call(server, name: "speak_ask", arguments: ["question": .string("q?")])
        let result = try #require(outbound.result?.objectValue)
        #expect(result["isError"]?.boolValue == true)
        #expect(outbound.error == nil)
    }

    @Test("speak_confirm with a running backend returns a deterministic yes/no")
    func confirmSucceeds() async throws {
        let server = AgentBridgeServer(backend: StubBridgeBackend())
        let outbound = try await call(server, name: "speak_confirm", arguments: ["question": .string("proceed?")])
        let result = try #require(outbound.result?.objectValue)
        #expect(result["isError"]?.boolValue == nil || result["isError"]?.boolValue == false)
        let text = result["content"]?.arrayValue?.first?.objectValue?["text"]?.stringValue ?? ""
        #expect(text == "yes")
    }

    @Test("speak_confirm reports a clean tool execution error when the answer is unclear")
    func confirmUnclearIsToolError() async throws {
        let server = AgentBridgeServer(backend: StubBridgeBackend(confirm: .failure(.unclearAnswer("speak_confirm"))))
        let outbound = try await call(server, name: "speak_confirm", arguments: ["question": .string("q?")])
        let result = try #require(outbound.result?.objectValue)
        #expect(result["isError"]?.boolValue == true)
        #expect(outbound.error == nil)
    }

    // MARK: - AVB-5 speak_request_input

    @Test("speak_request_input freeform happy path returns {outcome: answered, text}")
    func requestInputFreeformAnswered() async throws {
        let backend = StubBridgeBackend(requestInput: .success(.answered(text: "blue please", choice: nil)))
        let server = AgentBridgeServer(backend: backend)
        let outbound = try await call(server, name: "speak_request_input", arguments: [
            "requestId": .string("r1"), "prompt": .string("what color?"), "mode": .string("freeform")
        ])
        let result = try #require(outbound.result?.objectValue)
        #expect(result["isError"]?.boolValue == nil || result["isError"]?.boolValue == false)
        let text = try #require(result["content"]?.arrayValue?.first?.objectValue?["text"]?.stringValue)
        let json = try #require(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
        #expect(json["outcome"] as? String == "answered")
        #expect(json["text"] as? String == "blue please")
        #expect(json["choice"] == nil)
        #expect(backend.lastRequestInputMode == .freeform)
    }

    @Test("speak_request_input approval matched choice returns {outcome: answered, choice: approved}")
    func requestInputApprovalApproved() async throws {
        let backend = StubBridgeBackend(requestInput: .success(.answered(text: "yes", choice: "approved")))
        let server = AgentBridgeServer(backend: backend)
        let outbound = try await call(server, name: "speak_request_input", arguments: [
            "requestId": .string("r2"), "prompt": .string("deploy?"), "mode": .string("approval")
        ])
        let result = try #require(outbound.result?.objectValue)
        #expect(result["isError"]?.boolValue == nil || result["isError"]?.boolValue == false)
        let text = try #require(result["content"]?.arrayValue?.first?.objectValue?["text"]?.stringValue)
        let json = try #require(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
        #expect(json["outcome"] as? String == "answered")
        #expect(json["choice"] as? String == "approved")
    }

    @Test("speak_request_input choice mode matched choice returns {outcome: answered, choice}")
    func requestInputChoiceMatched() async throws {
        let backend = StubBridgeBackend(requestInput: .success(.answered(text: "rollback", choice: "rollback")))
        let server = AgentBridgeServer(backend: backend)
        let outbound = try await call(server, name: "speak_request_input", arguments: [
            "requestId": .string("r3"), "prompt": .string("rollback or forward?"), "mode": .string("choice"),
            "choices": .array([.string("rollback"), .string("forward")])
        ])
        let result = try #require(outbound.result?.objectValue)
        #expect(result["isError"]?.boolValue == nil || result["isError"]?.boolValue == false)
        #expect(backend.lastRequestInputChoices == ["rollback", "forward"])
    }

    @Test("speak_request_input declined maps to {outcome: declined}, never a false success text")
    func requestInputDeclined() async throws {
        let backend = StubBridgeBackend(requestInput: .success(.declined))
        let server = AgentBridgeServer(backend: backend)
        let outbound = try await call(server, name: "speak_request_input", arguments: [
            "requestId": .string("r4"), "prompt": .string("deploy?"), "mode": .string("approval")
        ])
        let result = try #require(outbound.result?.objectValue)
        #expect(result["isError"]?.boolValue == nil || result["isError"]?.boolValue == false)
        let text = try #require(result["content"]?.arrayValue?.first?.objectValue?["text"]?.stringValue)
        let json = try #require(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
        #expect(json["outcome"] as? String == "declined")
    }

    @Test("speak_request_input cancelled/timedOut/busy each round-trip their own outcome tag",
          arguments: [
            (HumanResponseOutcome.cancelled, "cancelled"),
            (HumanResponseOutcome.timedOut, "timedOut"),
            (HumanResponseOutcome.busy, "busy")
          ])
    func requestInputLifecycleOutcomes(outcome: HumanResponseOutcome, expectedTag: String) async throws {
        let backend = StubBridgeBackend(requestInput: .success(outcome))
        let server = AgentBridgeServer(backend: backend)
        let outbound = try await call(server, name: "speak_request_input", arguments: [
            "requestId": .string("r5"), "prompt": .string("q?"), "mode": .string("freeform")
        ])
        let result = try #require(outbound.result?.objectValue)
        #expect(result["isError"]?.boolValue == nil || result["isError"]?.boolValue == false)
        let text = try #require(result["content"]?.arrayValue?.first?.objectValue?["text"]?.stringValue)
        let json = try #require(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
        #expect(json["outcome"] as? String == expectedTag)
    }

    @Test("speak_request_input in choice mode with a non-matching answer is a tool execution error, not answered")
    func requestInputAmbiguousChoiceIsError() async throws {
        let backend = StubBridgeBackend(requestInput: .success(.answered(text: "something else", choice: nil)))
        let server = AgentBridgeServer(backend: backend)
        let outbound = try await call(server, name: "speak_request_input", arguments: [
            "requestId": .string("r6"), "prompt": .string("rollback or forward?"), "mode": .string("choice"),
            "choices": .array([.string("rollback"), .string("forward")])
        ])
        let result = try #require(outbound.result?.objectValue)
        #expect(result["isError"]?.boolValue == true)
    }

    @Test("speak_request_input in approval mode with an unrecognized answer is a tool execution error")
    func requestInputAmbiguousApprovalIsError() async throws {
        let backend = StubBridgeBackend(requestInput: .success(.answered(text: "maybe idk", choice: nil)))
        let server = AgentBridgeServer(backend: backend)
        let outbound = try await call(server, name: "speak_request_input", arguments: [
            "requestId": .string("r7"), "prompt": .string("deploy?"), "mode": .string("approval")
        ])
        let result = try #require(outbound.result?.objectValue)
        #expect(result["isError"]?.boolValue == true)
    }

    @Test("speak_request_input in freeform mode never treats a nil choice as an error")
    func requestInputFreeformNeverAmbiguous() async throws {
        let backend = StubBridgeBackend(requestInput: .success(.answered(text: "anything", choice: nil)))
        let server = AgentBridgeServer(backend: backend)
        let outbound = try await call(server, name: "speak_request_input", arguments: [
            "requestId": .string("r8"), "prompt": .string("q?"), "mode": .string("freeform")
        ])
        let result = try #require(outbound.result?.objectValue)
        #expect(result["isError"]?.boolValue == nil || result["isError"]?.boolValue == false)
    }

    @Test("speak_request_input requires a non-empty requestId")
    func requestInputRequiresRequestId() async throws {
        let server = AgentBridgeServer(backend: StubBridgeBackend())
        let outbound = try await call(server, name: "speak_request_input", arguments: [
            "prompt": .string("q?"), "mode": .string("freeform")
        ])
        #expect(outbound.result?.objectValue?["isError"]?.boolValue == true)
    }

    @Test("speak_request_input requires a non-empty prompt")
    func requestInputRequiresPrompt() async throws {
        let server = AgentBridgeServer(backend: StubBridgeBackend())
        let outbound = try await call(server, name: "speak_request_input", arguments: [
            "requestId": .string("r9"), "mode": .string("freeform")
        ])
        #expect(outbound.result?.objectValue?["isError"]?.boolValue == true)
    }

    @Test("speak_request_input rejects an unrecognized mode")
    func requestInputRejectsBadMode() async throws {
        let server = AgentBridgeServer(backend: StubBridgeBackend())
        let outbound = try await call(server, name: "speak_request_input", arguments: [
            "requestId": .string("r10"), "prompt": .string("q?"), "mode": .string("bogus")
        ])
        #expect(outbound.result?.objectValue?["isError"]?.boolValue == true)
    }

    @Test("speak_request_input mode 'choice' requires a non-empty 'choices' array")
    func requestInputChoiceRequiresChoices() async throws {
        let server = AgentBridgeServer(backend: StubBridgeBackend())
        let outbound = try await call(server, name: "speak_request_input", arguments: [
            "requestId": .string("r11"), "prompt": .string("q?"), "mode": .string("choice")
        ])
        #expect(outbound.result?.objectValue?["isError"]?.boolValue == true)
    }

    @Test("speak_request_input surfaces a busy backend result as a clean tool execution error")
    func requestInputBackendUnavailableIsToolError() async throws {
        let backend = StubBridgeBackend(requestInput: .failure(.appNotRunning))
        let server = AgentBridgeServer(backend: backend)
        let outbound = try await call(server, name: "speak_request_input", arguments: [
            "requestId": .string("r12"), "prompt": .string("q?"), "mode": .string("freeform")
        ])
        let result = try #require(outbound.result?.objectValue)
        #expect(result["isError"]?.boolValue == true)
        #expect(outbound.error == nil)
    }

    // MARK: - AVB-6 speak_register_session + sessionId threading

    @Test("speak_register_session happy path returns {sessionId, capabilities} and forwards provider/label/cwd")
    func registerSessionHappyPath() async throws {
        let backend = StubBridgeBackend(
            registerSession: .success((sessionId: "generated-1", capabilities: ["notify", "say"]))
        )
        let server = AgentBridgeServer(backend: backend)
        let outbound = try await call(server, name: "speak_register_session", arguments: [
            "provider": .string("codex"), "label": .string("fix bug"), "cwd": .string("/repo"),
            "capabilities": .array([.string("notify"), .string("say"), .string("open_microphone")])
        ])
        let result = try #require(outbound.result?.objectValue)
        #expect(result["isError"]?.boolValue == nil || result["isError"]?.boolValue == false)
        let text = try #require(result["content"]?.arrayValue?.first?.objectValue?["text"]?.stringValue)
        let json = try #require(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
        #expect(json["sessionId"] as? String == "generated-1")
        #expect(json["capabilities"] as? [String] == ["notify", "say"])
        #expect(backend.lastRegisterProvider == "codex")
        #expect(backend.lastRegisterLabel == "fix bug")
        #expect(backend.lastRegisterCapabilities == ["notify", "say", "open_microphone"])
    }

    @Test("speak_register_session requires a non-empty provider and label")
    func registerSessionRequiresProviderAndLabel() async throws {
        let server = AgentBridgeServer(backend: StubBridgeBackend())
        let missingProvider = try await call(server, name: "speak_register_session", arguments: [
            "label": .string("l")
        ])
        #expect(missingProvider.result?.objectValue?["isError"]?.boolValue == true)

        let missingLabel = try await call(server, name: "speak_register_session", arguments: [
            "provider": .string("codex")
        ])
        #expect(missingLabel.result?.objectValue?["isError"]?.boolValue == true)
    }

    @Test("speak_register_session surfaces an app-not-running backend failure as a tool execution error")
    func registerSessionAppNotRunningIsToolError() async throws {
        let backend = StubBridgeBackend(registerSession: .failure(.appNotRunning))
        let server = AgentBridgeServer(backend: backend)
        let outbound = try await call(server, name: "speak_register_session", arguments: [
            "provider": .string("codex"), "label": .string("l")
        ])
        let result = try #require(outbound.result?.objectValue)
        #expect(result["isError"]?.boolValue == true)
        #expect(outbound.error == nil)
    }

    @Test("speak_say forwards a supplied sessionId to the backend")
    func sayForwardsSessionId() async throws {
        let backend = StubBridgeBackend()
        let server = AgentBridgeServer(backend: backend)
        _ = try await call(server, name: "speak_say", arguments: [
            "text": .string("hi"), "sessionId": .string("sess-1")
        ])
        #expect(backend.lastSessionId == "sess-1")
    }

    @Test("speak_status result text includes the unregistered-session note when the backend reports one")
    func statusIncludesUnregisteredSessionNote() async throws {
        let backend = StubBridgeBackend(sessionNote: "note: sessionId 'sess-x' is not a registered session (call speak_register_session first) — proceeded anyway.")
        let server = AgentBridgeServer(backend: backend)
        let outbound = try await call(server, name: "speak_status", arguments: ["sessionId": .string("sess-x")])
        let result = try #require(outbound.result?.objectValue)
        let text = result["content"]?.arrayValue?.first?.objectValue?["text"]?.stringValue ?? ""
        #expect(text.contains("not a registered session"))
    }

    @Test("speak_status omits any note when no sessionId is supplied")
    func statusOmitsNoteWhenNoSessionId() async throws {
        let server = AgentBridgeServer(backend: StubBridgeBackend())
        let outbound = try await call(server, name: "speak_status")
        let result = try #require(outbound.result?.objectValue)
        let text = result["content"]?.arrayValue?.first?.objectValue?["text"]?.stringValue ?? ""
        #expect(!text.contains("not a registered session"))
    }

    @Test("an unknown tool name is a JSON-RPC protocol error (-32602), not a tool result")
    func unknownToolIsProtocolError() async throws {
        let server = AgentBridgeServer(backend: StubBridgeBackend())
        let outbound = try await call(server, name: "speak_teleport")
        #expect(outbound.error?.code == JSONRPCErrorCode.invalidParams)
        #expect(outbound.result == nil)
    }

    @Test("tools/call with no 'name' field is a protocol error")
    func missingNameIsProtocolError() async throws {
        let server = AgentBridgeServer(backend: StubBridgeBackend())
        let inbound = JSONRPCInbound(id: .number(1), method: "tools/call", params: .object(["arguments": .object([:])]))
        let outbound = try #require(await server.handle(inbound))
        #expect(outbound.error?.code == JSONRPCErrorCode.invalidParams)
    }
}

// MARK: - handleLine: full in-memory transport round trip

@Suite("AgentBridgeServer.handleLine (in-memory transport)")
struct AgentBridgeServerHandleLineTests {
    @Test("a raw initialize request line round-trips to a well-formed reply line")
    func initializeLineRoundTrip() async throws {
        let server = AgentBridgeServer(backend: StubBridgeBackend())
        let line = Data(#"""
        {"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"claude-code","version":"1.0"}}}
        """#.utf8)
        let replyData = try #require(await server.handleLine(line))
        let json = try #require(JSONSerialization.jsonObject(with: replyData) as? [String: Any])
        #expect(json["jsonrpc"] as? String == "2.0")
        let result = try #require(json["result"] as? [String: Any])
        #expect(result["protocolVersion"] as? String == "2025-06-18")
    }

    @Test("a malformed line produces a JSON-RPC parse error with a null id")
    func malformedLineProducesParseError() async throws {
        let server = AgentBridgeServer(backend: StubBridgeBackend())
        let replyData = try #require(await server.handleLine(Data("{not json".utf8)))
        let json = try #require(JSONSerialization.jsonObject(with: replyData) as? [String: Any])
        #expect(json["id"] is NSNull)
        let error = try #require(json["error"] as? [String: Any])
        #expect(error["code"] as? Int == JSONRPCErrorCode.parseError)
    }

    @Test("a notification line produces no reply bytes")
    func notificationLineProducesNoReply() async {
        let server = AgentBridgeServer(backend: StubBridgeBackend())
        let line = Data(#"{"jsonrpc":"2.0","method":"notifications/initialized"}"#.utf8)
        let replyData = await server.handleLine(line)
        #expect(replyData == nil)
    }

    @Test("a full tools/call line round-trips a text content block")
    func toolsCallLineRoundTrip() async throws {
        let backend = StubBridgeBackend(status: BridgeStatusReport(
            appRunning: true, engineState: "idle", hotkeyBinding: nil, detail: nil
        ))
        let server = AgentBridgeServer(backend: backend)
        let line = Data(#"""
        {"jsonrpc":"2.0","id":"call-1","method":"tools/call","params":{"name":"speak_status","arguments":{}}}
        """#.utf8)
        let replyData = try #require(await server.handleLine(line))
        let json = try #require(JSONSerialization.jsonObject(with: replyData) as? [String: Any])
        #expect(json["id"] as? String == "call-1")
        let result = try #require(json["result"] as? [String: Any])
        #expect(result["isError"] as? Bool == false)
    }
}

// MARK: - CLIBridgeBackend (real backend, reusing existing CLI IPC seam)

@Suite("CLIBridgeBackend")
struct CLIBridgeBackendTests {
    @Test("status() maps a successful CLIReply into a running BridgeStatusReport")
    func statusMapsSuccess() async {
        let stub = StubCLITransport(reply: .status(state: .listening, binding: "Fn ×2"))
        let backend = CLIBridgeBackend(transport: stub)
        let outcome = await backend.status(sessionId: nil)
        let report = outcome.value
        #expect(report.appRunning)
        #expect(report.engineState == "listening")
        #expect(report.hotkeyBinding == "Fn ×2")
        #expect(stub.lastCommand == .status)
    }

    @Test("status() maps portNotFound into appRunning=false with a clear detail")
    func statusMapsPortNotFound() async {
        let stub = StubCLITransport(error: .portNotFound)
        let backend = CLIBridgeBackend(transport: stub)
        let outcome = await backend.status(sessionId: nil)
        let report = outcome.value
        #expect(!report.appRunning)
        #expect(report.detail?.contains("not running") == true)
    }

    @Test("say() maps an accepted CLIReply to success and sends a .say command")
    func sayMapsAcceptedToSuccess() async {
        let stub = StubCLITransport(reply: .accepted())
        let backend = CLIBridgeBackend(transport: stub)
        let result = await backend.say(text: "hi", interrupt: true, sessionId: nil)
        guard case .success = result else {
            Issue.record("expected success, got \(result)")
            return
        }
        #expect(stub.lastCommand == .say)
        #expect(stub.lastTimeoutSeconds == CLIContract.sendTimeoutSeconds)
    }

    @Test("say() maps portNotFound to .appNotRunning")
    func sayMapsPortNotFoundToAppNotRunning() async {
        let backend = CLIBridgeBackend(transport: StubCLITransport(error: .portNotFound))
        let result = await backend.say(text: "hi", interrupt: false, sessionId: nil)
        guard case .failure(let reason) = result else {
            Issue.record("expected failure, got \(result)")
            return
        }
        #expect(reason == .appNotRunning)
    }

    @Test("say() maps an ok=false CLIReply to a failure carrying the app's error string")
    func sayMapsFailureReply() async {
        let backend = CLIBridgeBackend(transport: StubCLITransport(reply: .failure("no voice output")))
        let result = await backend.say(text: "hi", interrupt: false, sessionId: nil)
        guard case .failure(let reason) = result else {
            Issue.record("expected failure, got \(result)")
            return
        }
        #expect(reason.description.contains("no voice output"))
    }

    @Test("ask() maps a CLIReply with an answer to success, using the long ask/confirm timeout")
    func askMapsAnsweredToSuccess() async {
        let stub = StubCLITransport(reply: .asked("blue please"))
        let backend = CLIBridgeBackend(transport: stub)
        let result = await backend.ask(question: "coffee or tea?", timeoutSeconds: 10, sessionId: nil)
        guard case .success(let outcome) = result else {
            Issue.record("expected success, got \(result)")
            return
        }
        #expect(outcome.value == "blue please")
        #expect(stub.lastCommand == .ask)
        #expect(stub.lastTimeoutSeconds == 15)  // caller's 10s + the 5s wire-call buffer
    }

    @Test("ask() falls back to CLIContract.askConfirmDefaultTimeoutSeconds when the caller supplies none")
    func askUsesDefaultTimeoutWhenNilRequested() async {
        let stub = StubCLITransport(reply: .asked("ok"))
        let backend = CLIBridgeBackend(transport: stub)
        _ = await backend.ask(question: "q?", timeoutSeconds: nil, sessionId: nil)
        #expect(stub.lastTimeoutSeconds == CLIContract.askConfirmDefaultTimeoutSeconds + 5)
    }

    @Test("ask() maps a transport timeout to .timedOut")
    func askMapsTransportTimeout() async {
        let backend = CLIBridgeBackend(transport: StubCLITransport(error: .timeout))
        let result = await backend.ask(question: "q?", timeoutSeconds: 5, sessionId: nil)
        guard case .failure(let reason) = result else {
            Issue.record("expected failure, got \(result)")
            return
        }
        #expect(reason.description.contains("timed out"))
    }

    @Test("ask() maps portNotFound to .appNotRunning")
    func askMapsPortNotFound() async {
        let backend = CLIBridgeBackend(transport: StubCLITransport(error: .portNotFound))
        let result = await backend.ask(question: "q?", timeoutSeconds: 5, sessionId: nil)
        guard case .failure(let reason) = result else {
            Issue.record("expected failure, got \(result)")
            return
        }
        #expect(reason == .appNotRunning)
    }

    @Test("confirm() maps confirmed=true to success(true)")
    func confirmMapsTrue() async {
        let stub = StubCLITransport(reply: .confirmed(true))
        let backend = CLIBridgeBackend(transport: stub)
        let result = await backend.confirm(question: "proceed?", sessionId: nil)
        guard case .success(let outcome) = result else {
            Issue.record("expected success, got \(result)")
            return
        }
        #expect(outcome.value == true)
        #expect(stub.lastCommand == .confirm)
    }

    @Test("confirm() maps confirmed=false to success(false)")
    func confirmMapsFalse() async {
        let backend = CLIBridgeBackend(transport: StubCLITransport(reply: .confirmed(false)))
        let result = await backend.confirm(question: "proceed?", sessionId: nil)
        guard case .success(let outcome) = result else {
            Issue.record("expected success, got \(result)")
            return
        }
        #expect(outcome.value == false)
    }

    @Test("confirm() maps ok=true/confirmed=nil (unclear answer) to a failure, never a guessed bool")
    func confirmMapsUnclearToFailure() async {
        let backend = CLIBridgeBackend(transport: StubCLITransport(reply: .confirmed(nil)))
        let result = await backend.confirm(question: "proceed?", sessionId: nil)
        guard case .failure(let reason) = result else {
            Issue.record("expected failure, got \(result)")
            return
        }
        #expect(reason.description.contains("recognizable"))
    }

    @Test("confirm() maps a transport timeout to .timedOut")
    func confirmMapsTransportTimeout() async {
        let backend = CLIBridgeBackend(transport: StubCLITransport(error: .timeout))
        let result = await backend.confirm(question: "q?", sessionId: nil)
        guard case .failure(let reason) = result else {
            Issue.record("expected failure, got \(result)")
            return
        }
        #expect(reason.description.contains("timed out"))
    }
}
