// SpeakTests/AgentBridgeServerAVB7Tests.swift
//
// AVB-7 (specs/avb7-durable-calls-design.md): `speak_submit_call`/`speak_get_call`
// tool-layer tests. Split out of AgentBridgeServerTests.swift to keep that
// file's `AgentBridgeServerToolsCallTests` suite under SwiftLint's
// `type_body_length` cap — pure code motion, reuses the same `StubBridgeBackend`
// test double (declared there, `internal` so it's visible here).

import Foundation
import Testing
@testable import SpeakCore

@Suite("AgentBridgeServer tools/call — AVB-7 speak_submit_call / speak_get_call")
struct AgentBridgeServerAVB7Tests {
    private func call(_ server: AgentBridgeServer, name: String, arguments: [String: JSONValue] = [:]) async throws -> JSONRPCOutbound {
        let params: JSONValue = .object(["name": .string(name), "arguments": .object(arguments)])
        let inbound = JSONRPCInbound(id: .number(1), method: "tools/call", params: params)
        return try #require(await server.handle(inbound))
    }

    @Test("speak_submit_call requires a sessionId — tool execution error without one")
    func submitCallRequiresSessionId() async throws {
        let server = AgentBridgeServer(backend: StubBridgeBackend())
        let outbound = try await call(server, name: "speak_submit_call", arguments: [
            "requestId": .string("r1"), "prompt": .string("p"), "mode": .string("freeform")
        ])
        let result = try #require(outbound.result?.objectValue)
        #expect(result["isError"]?.boolValue == true)
    }

    @Test("speak_submit_call with a registered session returns the created call")
    func submitCallSucceeds() async throws {
        let backend = StubBridgeBackend()
        let server = AgentBridgeServer(backend: backend)
        let outbound = try await call(server, name: "speak_submit_call", arguments: [
            "requestId": .string("r1"), "prompt": .string("deploy?"), "mode": .string("approval"),
            "sessionId": .string("sess-1")
        ])
        let result = try #require(outbound.result?.objectValue)
        #expect(result["isError"]?.boolValue == nil || result["isError"]?.boolValue == false)
        let text = result["content"]?.arrayValue?.first?.objectValue?["text"]?.stringValue ?? ""
        #expect(text.contains("\"state\":\"pending\""))
        #expect(backend.lastSessionId == "sess-1")
    }

    @Test("speak_submit_call defaults expiresInSeconds to 24 hours when omitted")
    func submitCallDefaultsExpiry() async throws {
        let backend = StubBridgeBackend()
        let server = AgentBridgeServer(backend: backend)
        _ = try await call(server, name: "speak_submit_call", arguments: [
            "requestId": .string("r1"), "prompt": .string("p"), "mode": .string("freeform"),
            "sessionId": .string("sess-1")
        ])
        #expect(backend.lastSubmitCallArgs?.expiresInSeconds == AgentCallDefaults.defaultExpirySeconds)
    }

    @Test("speak_submit_call passes through an explicit expiresInSeconds instead of the default")
    func submitCallHonorsExplicitExpiry() async throws {
        let backend = StubBridgeBackend()
        let server = AgentBridgeServer(backend: backend)
        _ = try await call(server, name: "speak_submit_call", arguments: [
            "requestId": .string("r1"), "prompt": .string("p"), "mode": .string("freeform"),
            "sessionId": .string("sess-1"), "expiresInSeconds": .number(60)
        ])
        #expect(backend.lastSubmitCallArgs?.expiresInSeconds == 60)
    }

    @Test("speak_submit_call mode 'choice' with empty choices is a tool execution error")
    func submitCallChoiceRequiresChoices() async throws {
        let server = AgentBridgeServer(backend: StubBridgeBackend())
        let outbound = try await call(server, name: "speak_submit_call", arguments: [
            "requestId": .string("r1"), "prompt": .string("p"), "mode": .string("choice"),
            "sessionId": .string("sess-1")
        ])
        let result = try #require(outbound.result?.objectValue)
        #expect(result["isError"]?.boolValue == true)
    }

    @Test("speak_submit_call surfaces a duplicate submission")
    func submitCallDuplicateSurfaced() async throws {
        let existingId = UUID()
        let existingCall = AgentCall(
            id: existingId, sessionId: "sess-1", requestId: "r1", idempotencyKey: "k1", prompt: "p",
            mode: .freeform, choices: [], consequence: nil, spokenSummary: nil, urgency: .normal,
            state: .pending, createdAt: Date(), expiresAt: Date().addingTimeInterval(86_400)
        )
        let backend = StubBridgeBackend(submitCall: .success(AgentCallSubmitOutcome(call: existingCall, duplicate: true)))
        let server = AgentBridgeServer(backend: backend)
        let outbound = try await call(server, name: "speak_submit_call", arguments: [
            "requestId": .string("r2"), "idempotencyKey": .string("k1"), "prompt": .string("p"),
            "mode": .string("freeform"), "sessionId": .string("sess-1")
        ])
        let result = try #require(outbound.result?.objectValue)
        let text = result["content"]?.arrayValue?.first?.objectValue?["text"]?.stringValue ?? ""
        #expect(text.contains("\"duplicate\":true"))
        #expect(text.contains(existingId.uuidString))
    }

    @Test("speak_get_call requires a sessionId — tool execution error without one")
    func getCallRequiresSessionId() async throws {
        let server = AgentBridgeServer(backend: StubBridgeBackend())
        let outbound = try await call(server, name: "speak_get_call", arguments: ["callId": .string(UUID().uuidString)])
        let result = try #require(outbound.result?.objectValue)
        #expect(result["isError"]?.boolValue == true)
    }

    @Test("speak_get_call reports 'no such call' (never revealing existence) for a nil outcome")
    func getCallNilIsToolError() async throws {
        let server = AgentBridgeServer(backend: StubBridgeBackend(getCall: .success(nil)))
        let outbound = try await call(server, name: "speak_get_call", arguments: [
            "callId": .string(UUID().uuidString), "sessionId": .string("sess-1")
        ])
        let result = try #require(outbound.result?.objectValue)
        #expect(result["isError"]?.boolValue == true)
    }

    @Test("speak_get_call returns the call's terminal answer text/choice")
    func getCallReturnsAnswer() async throws {
        var answeredCall = AgentCall(
            id: UUID(), sessionId: "sess-1", requestId: "r1", idempotencyKey: nil, prompt: "p",
            mode: .choice, choices: ["a", "b"], consequence: nil, spokenSummary: nil, urgency: .normal,
            state: .answered, createdAt: Date(), expiresAt: nil
        )
        answeredCall.response = .answered(text: "a please", choice: "a")
        let server = AgentBridgeServer(backend: StubBridgeBackend(getCall: .success(answeredCall)))
        let outbound = try await call(server, name: "speak_get_call", arguments: [
            "callId": .string(answeredCall.id.uuidString), "sessionId": .string("sess-1")
        ])
        let result = try #require(outbound.result?.objectValue)
        let text = result["content"]?.arrayValue?.first?.objectValue?["text"]?.stringValue ?? ""
        #expect(text.contains("\"state\":\"answered\""))
        #expect(text.contains("\"choice\":\"a\""))
    }
}
