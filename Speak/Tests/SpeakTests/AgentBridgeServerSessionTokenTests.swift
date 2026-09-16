// SpeakTests/AgentBridgeServerSessionTokenTests.swift
//
// session-capability-token: `speak_register_session` reply shape + the
// per-process sessionToken cache in `AgentBridgeServer`. Split out of
// AgentBridgeServerTests.swift to keep that file under SwiftLint's
// `file_length` cap — same pattern as AgentBridgeServerAVB7Tests.swift, reusing
// the same `internal` `StubBridgeBackend` test double declared there.
// [decision: session-capability-token]

import Foundation
import Testing
@testable import SpeakCore

@Suite("AgentBridgeServer tools/call — session-capability-token")
struct AgentBridgeServerSessionTokenTests {
    private func call(_ server: AgentBridgeServer, name: String, arguments: [String: JSONValue] = [:]) async throws -> JSONRPCOutbound {
        let params: JSONValue = .object(["name": .string(name), "arguments": .object(arguments)])
        let inbound = JSONRPCInbound(id: .number(1), method: "tools/call", params: params)
        return try #require(await server.handle(inbound))
    }

    @Test("speak_register_session happy path returns {sessionId, sessionToken, capabilities} and forwards provider/label/cwd")
    func registerSessionHappyPath() async throws {
        let backend = StubBridgeBackend(
            registerSession: .success((sessionId: "generated-1", sessionToken: "tok-1", capabilities: ["notify", "say"]))
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
        #expect(json["sessionToken"] as? String == "tok-1")
        #expect(json["capabilities"] as? [String] == ["notify", "say"])
        #expect(backend.lastRegisterProvider == "codex")
        #expect(backend.lastRegisterLabel == "fix bug")
        #expect(backend.lastRegisterCapabilities == ["notify", "say", "open_microphone"])
    }

    @Test("a session registered via this server gets its cached sessionToken auto-attached to later calls")
    func cachedSessionTokenAutoAttached() async throws {
        let backend = StubBridgeBackend(
            registerSession: .success((sessionId: "generated-1", sessionToken: "tok-1", capabilities: []))
        )
        let server = AgentBridgeServer(backend: backend)
        _ = try await call(server, name: "speak_register_session", arguments: [
            "provider": .string("codex"), "label": "task"
        ])
        // Later call names the session but NOT the token — the cached token
        // captured from the register reply must ride along.
        _ = try await call(server, name: "speak_say", arguments: [
            "text": .string("hi"), "sessionId": .string("generated-1")
        ])
        #expect(backend.lastSessionId == "generated-1")
        #expect(backend.lastSessionToken == "tok-1")
    }

    @Test("an explicit sessionToken argument wins over the cached token")
    func explicitSessionTokenWins() async throws {
        let backend = StubBridgeBackend(
            registerSession: .success((sessionId: "generated-1", sessionToken: "tok-1", capabilities: []))
        )
        let server = AgentBridgeServer(backend: backend)
        _ = try await call(server, name: "speak_register_session", arguments: [
            "provider": .string("codex"), "label": "task"
        ])
        _ = try await call(server, name: "speak_say", arguments: [
            "text": .string("hi"), "sessionId": .string("generated-1"), "sessionToken": .string("explicit-tok")
        ])
        #expect(backend.lastSessionToken == "explicit-tok")
    }

    @Test("a sessionId registered elsewhere (no cached token) sends no token — app fails closed")
    func unknownSessionIdSendsNoToken() async throws {
        let backend = StubBridgeBackend()
        let server = AgentBridgeServer(backend: backend)
        _ = try await call(server, name: "speak_say", arguments: [
            "text": .string("hi"), "sessionId": .string("sess-foreign")
        ])
        #expect(backend.lastSessionId == "sess-foreign")
        #expect(backend.lastSessionToken == nil)
    }

    @Test("speak_register_session forwards a presented sessionToken when re-registering")
    func registerSessionForwardsPresentedToken() async throws {
        let backend = StubBridgeBackend(
            registerSession: .success((sessionId: "sess-1", sessionToken: "tok-1", capabilities: []))
        )
        let server = AgentBridgeServer(backend: backend)
        _ = try await call(server, name: "speak_register_session", arguments: [
            "provider": .string("codex"), "label": "reconnect",
            "sessionId": .string("sess-1"), "sessionToken": .string("tok-1")
        ])
        #expect(backend.lastSessionId == "sess-1")
        #expect(backend.lastRegisterSessionToken == "tok-1")
    }

    @Test("speak_submit_call carries the cached sessionToken for its sessionId")
    func submitCallCarriesCachedToken() async throws {
        let backend = StubBridgeBackend(
            registerSession: .success((sessionId: "sess-9", sessionToken: "tok-9", capabilities: []))
        )
        let server = AgentBridgeServer(backend: backend)
        _ = try await call(server, name: "speak_register_session", arguments: [
            "provider": .string("codex"), "label": "task"
        ])
        _ = try await call(server, name: "speak_submit_call", arguments: [
            "requestId": .string("r1"), "prompt": .string("p"), "mode": .string("freeform"),
            "sessionId": .string("sess-9")
        ])
        #expect(backend.lastSubmitCallArgs?.sessionToken == "tok-9")
    }
}
