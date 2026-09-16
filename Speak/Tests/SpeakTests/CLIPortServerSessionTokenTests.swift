// SpeakTests/CLIPortServerSessionTokenTests.swift
//
// session-capability-token: the IPC auth seam. `sessionId` alone is ASSERTED
// identity — every request that carries one must also present the opaque
// `sessionToken` issued by `registerSession`. Drives `CLIPortServer.dispatch`
// (the request → reply table, same code path the CFMessagePort callback uses)
// against a stub `CLICommandHandler` backed by a real `AgentSessionRegistry`
// and a real temp-file `AgentCallStore` — no live port needed.
//
// The required matrix:
//   - register issues a token;
//   - wrong-token getCall is byte-for-byte indistinguishable from an
//     unknown-session getCall (never "exists but wrong token");
//   - same-token re-register is allowed (idempotent reconnect);
//   - different-token re-register is REJECTED (never silently rotated);
//   - a session-scoped call with no token is denied (fail closed).

import Foundation
import Testing
@testable import SpeakCore

// MARK: - Stub CLICommandHandler

/// Thin `CLICommandHandler` conforming stub that delegates session semantics
/// to a REAL `AgentSessionRegistry` and call storage to a REAL temp-file
/// `AgentCallStore` — the auth gates under test live in the registry, and the
/// store's own sessionId isolation is exercised end-to-end.
@MainActor
private final class StubCLICommandHandler: CLICommandHandler {
    let registry = AgentSessionRegistry()
    let store: AgentCallStore

    init(store: AgentCallStore) {
        self.store = store
    }

    var icon: MenubarIcon { .idle }
    var currentHotkeyDisplayString: String { "Fn ×2" }
    var agentCallStore: any AgentCallStoring { store }

    func cliBeginDictation() {}
    func cliEndDictation() {}
    func cliSay(text: String, interrupt: Bool) {}
    func cliAsk(question: String, timeoutSeconds: TimeInterval, precomputedCallId: UUID?) async -> CLIAskOutcome {
        .timedOut
    }
    func cliConfirm(question: String, timeoutSeconds: TimeInterval, precomputedCallId: UUID?) async -> CLIConfirmOutcome {
        .timedOut
    }
    func cliRequestInput(
        requestId: String, idempotencyKey: String?, prompt: String, mode: RequestInputMode,
        choices: [String], timeoutSeconds: TimeInterval, consequence: String?,
        spokenSummary: String?, precomputedCallId: UUID?
    ) async -> HumanResponseOutcome {
        .busy
    }
    func cliTouchSession(_ sessionId: String, sessionToken: String?) -> Bool {
        registry.touch(sessionId: sessionId, sessionToken: sessionToken)
    }
    func cliRegisterSession(
        sessionId: String?, provider: String, label: String, workingDirectory: String?,
        requestedCapabilities: [String], sessionToken: String?
    ) -> CLIRegisterSessionOutcome {
        switch registry.register(
            sessionId: sessionId, provider: provider, label: label,
            workingDirectory: workingDirectory, requestedCapabilities: requestedCapabilities,
            sessionToken: sessionToken
        ) {
        case .registered(let session, let token):
            return .registered(sessionId: session.sessionId, sessionToken: token, capabilities: session.capabilities)
        case .rejected:
            return .rejected
        }
    }
    func cliIsSessionAuthenticated(sessionId: String, sessionToken: String?) -> Bool {
        registry.isAuthenticated(sessionId: sessionId, sessionToken: sessionToken)
    }
}

// MARK: - Suite

@Suite("CLIPortServer session-token authentication")
@MainActor
struct CLIPortServerSessionTokenTests {

    private func makeFixture() throws -> (CLIPortServer, StubCLICommandHandler) {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("agent-calls-port-test-\(UUID().uuidString)", isDirectory: false)
            .appendingPathExtension("sqlite")
        let store = try AgentCallStore(databaseURL: url)
        let handler = StubCLICommandHandler(store: store)
        return (CLIPortServer(), handler)
    }

    private func registerSession(
        _ server: CLIPortServer, handler: StubCLICommandHandler,
        sessionId: String? = nil, sessionToken: String? = nil
    ) -> CLIReply {
        server.dispatch(CLIRequest(
            cmd: .registerSession, sessionId: sessionId, sessionToken: sessionToken,
            provider: "codex", label: "task"
        ), handler: handler)
    }

    // MARK: - register issues a token

    @Test("registerSession reply carries a freshly-issued opaque token")
    func registerIssuesToken() throws {
        let (server, handler) = try makeFixture()
        let reply = registerSession(server, handler: handler)
        #expect(reply.ok)
        #expect(reply.sessionId != nil)
        #expect(UUID(uuidString: reply.sessionToken ?? "") != nil)
    }

    // MARK: - re-registration semantics

    @Test("re-registering a known sessionId with the SAME token is allowed (idempotent reconnect)")
    func reRegisterSameTokenAllowed() throws {
        let (server, handler) = try makeFixture()
        let first = registerSession(server, handler: handler, sessionId: "sess-1")
        let token = try #require(first.sessionToken)

        let second = registerSession(server, handler: handler, sessionId: "sess-1", sessionToken: token)
        #expect(second.ok)
        #expect(second.sessionId == "sess-1")
        #expect(second.sessionToken == token)  // never rotated on reconnect
    }

    @Test("re-registering a known sessionId with a DIFFERENT token is rejected (no silent rotation)")
    func reRegisterDifferentTokenRejected() throws {
        let (server, handler) = try makeFixture()
        _ = registerSession(server, handler: handler, sessionId: "sess-1")

        let hijack = registerSession(server, handler: handler, sessionId: "sess-1", sessionToken: "attacker")
        #expect(!hijack.ok)
        #expect(hijack.sessionToken == nil)

        // And with NO token — the pre-token hijack path — same refusal.
        let noToken = registerSession(server, handler: handler, sessionId: "sess-1")
        #expect(!noToken.ok)
    }

    // MARK: - session-scoped call gates

    @Test("submitCall with no sessionToken is denied even for a registered sessionId")
    func submitCallWithoutTokenDenied() throws {
        let (server, handler) = try makeFixture()
        let registered = registerSession(server, handler: handler, sessionId: "sess-1")
        #expect(registered.ok)

        let reply = server.dispatch(CLIRequest(
            cmd: .submitCall, requestId: "r1", prompt: "deploy?", mode: .approval,
            sessionId: "sess-1", expiresInSeconds: 3600
        ), handler: handler)
        #expect(!reply.ok)
        #expect(reply.error?.contains("speak_register_session") == true)
    }

    @Test("submitCall with the issued sessionToken creates the durable call")
    func submitCallWithTokenAccepted() throws {
        let (server, handler) = try makeFixture()
        let token = try #require(registerSession(server, handler: handler, sessionId: "sess-1").sessionToken)

        let reply = server.dispatch(CLIRequest(
            cmd: .submitCall, requestId: "r1", prompt: "deploy?", mode: .approval,
            sessionId: "sess-1", sessionToken: token, expiresInSeconds: 3600
        ), handler: handler)
        #expect(reply.ok)
        #expect(reply.agentCall?.sessionId == "sess-1")
    }

    @Test("submitCall with a WRONG sessionToken is denied identically to an unknown session")
    func submitCallWrongTokenDenied() throws {
        let (server, handler) = try makeFixture()
        _ = registerSession(server, handler: handler, sessionId: "sess-1")

        let wrongToken = server.dispatch(CLIRequest(
            cmd: .submitCall, requestId: "r1", prompt: "deploy?", mode: .approval,
            sessionId: "sess-1", sessionToken: "not-the-token", expiresInSeconds: 3600
        ), handler: handler)
        let unknownSession = server.dispatch(CLIRequest(
            cmd: .submitCall, requestId: "r1", prompt: "deploy?", mode: .approval,
            sessionId: "never-registered", expiresInSeconds: 3600
        ), handler: handler)
        #expect(!wrongToken.ok)
        #expect(wrongToken.error == unknownSession.error)  // indistinguishable — no "exists but wrong token" leak
    }

    @Test("getCall with a wrong token is byte-for-byte identical to an unknown-session getCall")
    func getCallWrongTokenIndistinguishable() throws {
        let (server, handler) = try makeFixture()
        let token = try #require(registerSession(server, handler: handler, sessionId: "sess-1").sessionToken)

        // Plant a real call owned by sess-1 so "exists but wrong token" is a
        // meaningful case, not a trivially-absent row.
        let submitted = server.dispatch(CLIRequest(
            cmd: .submitCall, requestId: "r1", prompt: "deploy?", mode: .approval,
            sessionId: "sess-1", sessionToken: token, expiresInSeconds: 3600
        ), handler: handler)
        let callId = try #require(submitted.agentCall?.id.uuidString)

        let wrongToken = server.dispatch(CLIRequest(
            cmd: .getCall, sessionId: "sess-1", sessionToken: "attacker-token", callId: callId
        ), handler: handler)
        let unknownSession = server.dispatch(CLIRequest(
            cmd: .getCall, sessionId: "never-registered", callId: callId
        ), handler: handler)
        #expect(!wrongToken.ok)
        #expect(!unknownSession.ok)
        #expect(wrongToken.error == unknownSession.error)
        #expect(wrongToken.agentCall == nil)
    }

    @Test("getCall with the issued token returns the session's own call")
    func getCallWithTokenReadsOwnCall() throws {
        let (server, handler) = try makeFixture()
        let token = try #require(registerSession(server, handler: handler, sessionId: "sess-1").sessionToken)
        let submitted = server.dispatch(CLIRequest(
            cmd: .submitCall, requestId: "r1", prompt: "deploy?", mode: .approval,
            sessionId: "sess-1", sessionToken: token, expiresInSeconds: 3600
        ), handler: handler)
        let callId = try #require(submitted.agentCall?.id.uuidString)

        let reply = server.dispatch(CLIRequest(
            cmd: .getCall, sessionId: "sess-1", sessionToken: token, callId: callId
        ), handler: handler)
        #expect(reply.ok)
        #expect(reply.agentCall?.id.uuidString == callId)
    }

    // MARK: - advisory tools fail closed via the sessionNote

    @Test("say with a sessionId but no token proceeds but reports the session as unregistered")
    func sayWithoutTokenGetsUnregisteredNote() throws {
        let (server, handler) = try makeFixture()
        let token = try #require(registerSession(server, handler: handler, sessionId: "sess-1").sessionToken)

        let noToken = server.dispatch(CLIRequest(
            cmd: .say, text: "hello", sessionId: "sess-1"
        ), handler: handler)
        #expect(noToken.ok)
        #expect(noToken.sessionNote?.contains("not a registered session") == true)

        let wrongToken = server.dispatch(CLIRequest(
            cmd: .say, text: "hello", sessionId: "sess-1", sessionToken: "attacker"
        ), handler: handler)
        #expect(wrongToken.ok)
        #expect(wrongToken.sessionNote == noToken.sessionNote)  // indistinguishable from unknown session

        let withToken = server.dispatch(CLIRequest(
            cmd: .say, text: "hello", sessionId: "sess-1", sessionToken: token
        ), handler: handler)
        #expect(withToken.ok)
        #expect(withToken.sessionNote == nil)
    }
}
