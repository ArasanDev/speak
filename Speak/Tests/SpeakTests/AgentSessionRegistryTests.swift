// SpeakTests/AgentSessionRegistryTests.swift
//
// AVB-6 (specs/agent-voice-bridge.md §7.1): the in-memory session registry
// behind `speak_register_session`. Exercises register/re-register/touch/
// staleness and capability negotiation purely through the actor's public API
// — no CLI wire, no MCP layer (those are covered separately).

import Foundation
import Testing
@testable import SpeakCore

private final class FakeClock: @unchecked Sendable {
    var now: Date
    init(_ now: Date) { self.now = now }
}

@Suite("AgentSessionRegistry")
struct AgentSessionRegistryTests {
    @Test("register() with no sessionId mints a UUID")
    func registerMintsID() async {
        let registry = AgentSessionRegistry()
        let session = await registry.register(
            sessionId: nil, provider: "codex", label: "task-1",
            workingDirectory: nil, requestedCapabilities: []
        )
        #expect(UUID(uuidString: session.sessionId) != nil)
        #expect(session.state == .active)
    }

    @Test("register() with an existing sessionId re-registers (updates fields, no duplicate)")
    func reRegisterUpdatesInPlace() async {
        let registry = AgentSessionRegistry()
        let first = await registry.register(
            sessionId: "fixed-id", provider: "codex", label: "first label",
            workingDirectory: "/a", requestedCapabilities: ["notify"]
        )
        let second = await registry.register(
            sessionId: "fixed-id", provider: "codex", label: "second label",
            workingDirectory: "/b", requestedCapabilities: ["say"]
        )
        #expect(first.sessionId == second.sessionId)
        let all = await registry.list()
        #expect(all.count == 1)
        #expect(all.first?.label == "second label")
        #expect(all.first?.workingDirectory == "/b")
        #expect(all.first?.capabilities == ["say"])
    }

    @Test("capability negotiation is the intersection of requested with supportedCapabilities, in supported order")
    func capabilityIntersection() async {
        let registry = AgentSessionRegistry()
        let session = await registry.register(
            sessionId: nil, provider: "claude-code", label: "l",
            workingDirectory: nil,
            requestedCapabilities: ["status", "unknown_cap", "notify", "screen_read"]
        )
        #expect(session.capabilities == ["notify", "status"])
    }

    @Test("capability negotiation drops unknown capabilities silently, never errors")
    func unknownCapabilitiesDroppedSilently() async {
        let registry = AgentSessionRegistry()
        let session = await registry.register(
            sessionId: nil, provider: "p", label: "l", workingDirectory: nil,
            requestedCapabilities: ["read_files", "open_microphone"]
        )
        #expect(session.capabilities.isEmpty)
    }

    @Test("touch() on a known session updates lastSeen and returns true")
    func touchKnownSession() async {
        let clock = FakeClock(Date(timeIntervalSince1970: 1_000))
        let registry = AgentSessionRegistry(now: { clock.now })
        let session = await registry.register(
            sessionId: nil, provider: "codex", label: "l", workingDirectory: nil, requestedCapabilities: []
        )
        clock.now = clock.now.addingTimeInterval(60)
        let known = await registry.touch(sessionId: session.sessionId)
        #expect(known)
        let all = await registry.list()
        #expect(all.first?.lastSeen == clock.now)
    }

    @Test("touch() on an unknown sessionId is a no-op and returns false")
    func touchUnknownSession() async {
        let registry = AgentSessionRegistry()
        let known = await registry.touch(sessionId: "never-registered")
        #expect(!known)
        let all = await registry.list()
        #expect(all.isEmpty)
    }

    @Test("isKnown() reflects registration without mutating lastSeen")
    func isKnownDoesNotTouch() async {
        let clock = FakeClock(Date(timeIntervalSince1970: 1_000))
        let registry = AgentSessionRegistry(now: { clock.now })
        let session = await registry.register(
            sessionId: nil, provider: "codex", label: "l", workingDirectory: nil, requestedCapabilities: []
        )
        clock.now = clock.now.addingTimeInterval(60)
        #expect(await registry.isKnown(sessionId: session.sessionId))
        let all = await registry.list()
        #expect(all.first?.lastSeen == Date(timeIntervalSince1970: 1_000))
    }

    @Test("list() marks a session stale once lastSeen exceeds staleThreshold, active just under it")
    func stalenessCutoff() async {
        let clock = FakeClock(Date(timeIntervalSince1970: 10_000))
        let registry = AgentSessionRegistry(now: { clock.now })
        let session = await registry.register(
            sessionId: nil, provider: "codex", label: "l", workingDirectory: nil, requestedCapabilities: []
        )

        clock.now = clock.now.addingTimeInterval(AgentSessionRegistry.staleThreshold - 1)
        var all = await registry.list()
        #expect(all.first { $0.sessionId == session.sessionId }?.state == .active)

        clock.now = clock.now.addingTimeInterval(2)  // now 1s past the threshold
        all = await registry.list()
        #expect(all.first { $0.sessionId == session.sessionId }?.state == .stale)
    }

    @Test("AgentSession round-trips through Codable")
    func agentSessionCodableRoundTrip() throws {
        let session = AgentSession(
            sessionId: "id-1", provider: "codex", label: "task", workingDirectory: "/repo",
            capabilities: ["notify", "say"], state: .active, lastSeen: Date(timeIntervalSince1970: 42)
        )
        let data = try JSONEncoder().encode(session)
        let decoded = try JSONDecoder().decode(AgentSession.self, from: data)
        #expect(decoded == session)
    }
}
