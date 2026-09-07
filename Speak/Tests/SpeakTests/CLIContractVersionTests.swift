// SpeakTests/CLIContractVersionTests.swift
//
// output-conversation-reconnect §4: `CLIContract.bridgeContractVersion` guard.
// `speak.app` and `speak-mcp` are separate build products that can drift out
// of sync (a stale `speak-mcp` left over from `make install-mcp-user` talking
// to a freshly rebuilt `speak.app`, or vice versa). A version-skewed pair must
// surface as a loud, actionable `speak_status` error naming
// `make install-mcp-user` — never a plausible-looking normal reply.
//
// Split out of AgentBridgeServerTests.swift (which is already at the
// file_length lint ceiling) rather than appended there.

import Foundation
import Testing
@testable import SpeakCore

@Suite("CLIContract bridgeContractVersion guard")
struct CLIContractVersionTests {

    @Test("status() surfaces a contract-version mismatch as a loud, actionable error")
    func statusMapsContractVersionMismatch() async {
        // Simulate a stale/newer running app by hand-building a reply with a
        // contractVersion that doesn't match CLIContract.bridgeContractVersion —
        // a plain `.status(...)` factory call always stamps the current
        // in-process version, so a real skew can only be reached this way in
        // a single-binary test.
        let staleReply = CLIReply(
            ok: true, error: nil, state: .listening, binding: "Fn ×2",
            contractVersion: CLIContract.bridgeContractVersion + 1
        )
        let stub = StubCLITransport(reply: staleReply)
        let backend = CLIBridgeBackend(transport: stub)
        let outcome = await backend.status(sessionId: nil)
        let report = outcome.value
        #expect(report.appRunning) // the app IS running — this is a version problem, not a reachability one
        #expect(report.contractMismatch)
        #expect(report.detail?.contains("make install-mcp-user") == true)
    }

    @Test("status() reports no mismatch when versions agree")
    func statusMapsMatchingVersion() async {
        let stub = StubCLITransport(reply: .status(state: .idle, binding: "Fn ×2"))
        let backend = CLIBridgeBackend(transport: stub)
        let outcome = await backend.status(sessionId: nil)
        let report = outcome.value
        #expect(report.appRunning)
        #expect(!report.contractMismatch)
        #expect(report.detail == nil)
    }

    @Test("status() treats a pre-versioning app (nil contractVersion) as a mismatch")
    func statusMapsMissingVersionAsMismatch() async {
        let unversionedReply = CLIReply(
            ok: true, error: nil, state: .idle, binding: "Fn ×2", contractVersion: nil
        )
        let stub = StubCLITransport(reply: unversionedReply)
        let backend = CLIBridgeBackend(transport: stub)
        let outcome = await backend.status(sessionId: nil)
        let report = outcome.value
        #expect(report.contractMismatch)
        #expect(report.detail?.contains("pre-versioning") == true)
    }

    @Test("render() turns a contract-version mismatch into an MCP tool error, not a normal status reply")
    func renderTurnsContractMismatchIntoError() async throws {
        let staleReply = CLIReply(
            ok: true, error: nil, state: .listening, binding: "Fn ×2",
            contractVersion: CLIContract.bridgeContractVersion + 1
        )
        let stub = StubCLITransport(reply: staleReply)
        let server = AgentBridgeServer(backend: CLIBridgeBackend(transport: stub))
        let line = Data(#"""
        {"jsonrpc":"2.0","id":"call-1","method":"tools/call","params":{"name":"speak_status","arguments":{}}}
        """#.utf8)
        let replyData = try #require(await server.handleLine(line))
        let json = try #require(JSONSerialization.jsonObject(with: replyData) as? [String: Any])
        let result = try #require(json["result"] as? [String: Any])
        #expect(result["isError"] as? Bool == true)
    }
}
