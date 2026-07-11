// SpeakTests/AgentCallStoreTests.swift
//
// AVB-7 (specs/avb7-durable-calls-design.md): the SQLite-backed durable-call
// store. Exercises the state machine, CAS races, idempotency race, session
// isolation, recovery/expiry, and schema idempotence purely through the
// actor's public API — matching `AgentSessionRegistryTests`'s no-wire-layer
// shape. Each test opens a fresh temp-file database (never in-memory: the
// design doc's schema/recovery tests need a real reopen).

import Foundation
import Testing
@testable import SpeakCore

private func makeTempStoreURL() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("agent-calls-test-\(UUID().uuidString)", isDirectory: false)
        .appendingPathExtension("sqlite")
}

@Suite("AgentCallStore")
struct AgentCallStoreTests {

    // MARK: - Schema

    @Test("opening a fresh DB creates the table; opening twice is a no-op")
    func schemaIdempotence() async throws {
        let url = makeTempStoreURL()
        defer { try? FileManager.default.removeItem(at: url) }

        let first = try AgentCallStore(databaseURL: url)
        _ = try await first.submit(AgentCallSubmission(
            sessionId: "s1", requestId: "r1", idempotencyKey: nil, prompt: "p", mode: .freeform,
            choices: [], consequence: nil, spokenSummary: nil, urgency: .normal, expiresAt: nil
        ))
        // Reopening the same file must not throw and must see the prior row.
        let second = try AgentCallStore(databaseURL: url)
        let all = try await second.pendingAndPresented()
        #expect(all.count == 1)
    }

    // MARK: - State machine

    @Test("submit() creates a pending call")
    func submitCreatesPending() async throws {
        let store = try AgentCallStore(databaseURL: makeTempStoreURL())
        let result = try await store.submit(AgentCallSubmission(
                sessionId: "s1", requestId: "r1", idempotencyKey: nil, prompt: "proceed?", mode: .approval,
                choices: [], consequence: nil, spokenSummary: nil, urgency: .high, expiresAt: nil
            ))
        guard case .created(let call) = result else {
            Issue.record("expected .created")
            return
        }
        #expect(call.state == .pending)
        #expect(call.urgency == .high)
    }

    @Test("markPresented transitions pending → presented; no-op on an already-terminal call")
    func markPresentedTransition() async throws {
        let store = try AgentCallStore(databaseURL: makeTempStoreURL())
        let call = try await createCall(store)
        try await store.markPresented(id: call.id)
        let fetched = try await store.get(id: call.id, requestingSessionId: call.sessionId)
        #expect(fetched?.state == .presented)

        // Resolve to terminal, then markPresented again — documented no-op, never a crash.
        try await store.resolve(id: call.id, outcome: .declined)
        try await store.markPresented(id: call.id)
        let afterTerminal = try await store.get(id: call.id, requestingSessionId: call.sessionId)
        #expect(afterTerminal?.state == .declined)
    }

    @Test("resolve() is a documented no-op on an already-terminal call — never crashes")
    func resolveNoOpOnTerminal() async throws {
        let store = try AgentCallStore(databaseURL: makeTempStoreURL())
        let call = try await createCall(store)
        let firstResolve = try await store.resolve(id: call.id, outcome: .answered(text: "yes", choice: "approved"))
        #expect(firstResolve == true)
        let secondResolve = try await store.resolve(id: call.id, outcome: .declined)
        #expect(secondResolve == false)
        let fetched = try await store.get(id: call.id, requestingSessionId: call.sessionId)
        // The loser's write never overwrote the winner's terminal state.
        #expect(fetched?.state == .answered)
    }

    @Test("resolve() maps every HumanResponseOutcome to its AgentCallState")
    func resolveStateMapping() async throws {
        let store = try AgentCallStore(databaseURL: makeTempStoreURL())
        let cases: [(HumanResponseOutcome, AgentCallState)] = [
            (.answered(text: "hi", choice: nil), .answered),
            (.declined, .declined),
            (.cancelled, .cancelled),
            (.timedOut, .timedOut),
            (.busy, .cancelled)
        ]
        for (outcome, expectedState) in cases {
            let call = try await createCall(store)
            try await store.resolve(id: call.id, outcome: outcome)
            let fetched = try await store.get(id: call.id, requestingSessionId: call.sessionId)
            #expect(fetched?.state == expectedState)
        }
    }

    // MARK: - CAS race

    @Test("two concurrent resolve() calls on one id — exactly one wins")
    func resolveRaceExactlyOneWinner() async throws {
        let store = try AgentCallStore(databaseURL: makeTempStoreURL())
        let call = try await createCall(store)

        async let first = store.resolve(id: call.id, outcome: .declined)
        async let second = store.resolve(id: call.id, outcome: .cancelled)
        let results = try await [first, second]

        #expect(results.filter { $0 }.count == 1)
        #expect(results.filter { !$0 }.count == 1)
    }

    // MARK: - Idempotency race

    @Test("two concurrent submit() calls, same (sessionId, key) — one created, one duplicate pointing at the same id")
    func idempotencyRaceExactlyOneCreated() async throws {
        let store = try AgentCallStore(databaseURL: makeTempStoreURL())
        async let first = store.submit(AgentCallSubmission(
                sessionId: "s1", requestId: "r1", idempotencyKey: "k1", prompt: "p", mode: .freeform,
                choices: [], consequence: nil, spokenSummary: nil, urgency: .normal, expiresAt: nil
            ))
        async let second = store.submit(AgentCallSubmission(
                sessionId: "s1", requestId: "r2", idempotencyKey: "k1", prompt: "p", mode: .freeform,
                choices: [], consequence: nil, spokenSummary: nil, urgency: .normal, expiresAt: nil
            ))
        let results = try await [first, second]

        var createdIds: [UUID] = []
        var duplicateIds: [UUID] = []
        for result in results {
            switch result {
            case .created(let call): createdIds.append(call.id)
            case .duplicateSubmission(let existingCallId): duplicateIds.append(existingCallId)
            }
        }
        #expect(createdIds.count == 1)
        #expect(duplicateIds.count == 1)
        #expect(createdIds == duplicateIds)
    }

    @Test("distinct idempotency keys never collide")
    func distinctKeysNeverCollide() async throws {
        let store = try AgentCallStore(databaseURL: makeTempStoreURL())
        let first = try await store.submit(AgentCallSubmission(
                sessionId: "s1", requestId: "r1", idempotencyKey: "k1", prompt: "p", mode: .freeform,
                choices: [], consequence: nil, spokenSummary: nil, urgency: .normal, expiresAt: nil
            ))
        let second = try await store.submit(AgentCallSubmission(
                sessionId: "s1", requestId: "r2", idempotencyKey: "k2", prompt: "p", mode: .freeform,
                choices: [], consequence: nil, spokenSummary: nil, urgency: .normal, expiresAt: nil
            ))
        guard case .created = first, case .created = second else {
            Issue.record("expected both .created")
            return
        }
    }

    // Renamed from the original "nilKeysNeverCollide": that test varies
    // `idempotencyKey` (nil vs nil) with a FIXED, non-nil `sessionId` — it
    // covers nil idempotencyKey, not nil sessionId. Kept as-is (still a real,
    // useful case) but retitled to say what it actually tests; the nil-session
    // case it was mislabeled as is covered separately below. [decision: AVB-7]
    @Test("nil idempotency keys never collide with each other (fixed non-nil sessionId)")
    func nilIdempotencyKeysNeverCollide() async throws {
        let store = try AgentCallStore(databaseURL: makeTempStoreURL())
        let first = try await store.submit(AgentCallSubmission(
                sessionId: "s1", requestId: "r1", idempotencyKey: nil, prompt: "p", mode: .freeform,
                choices: [], consequence: nil, spokenSummary: nil, urgency: .normal, expiresAt: nil
            ))
        let second = try await store.submit(AgentCallSubmission(
                sessionId: "s1", requestId: "r2", idempotencyKey: nil, prompt: "p", mode: .freeform,
                choices: [], consequence: nil, spokenSummary: nil, urgency: .normal, expiresAt: nil
            ))
        guard case .created = first, case .created = second else {
            Issue.record("expected both .created")
            return
        }
    }

    @Test("two nil-session submits with the SAME idempotencyKey collide — the real FIX 2 case")
    func nilSessionSameIdempotencyKeyCollides() async throws {
        let store = try AgentCallStore(databaseURL: makeTempStoreURL())
        let first = try await store.submit(AgentCallSubmission(
            sessionId: nil, requestId: "r1", idempotencyKey: "k1", prompt: "p", mode: .freeform,
            choices: [], consequence: nil, spokenSummary: nil, urgency: .normal, expiresAt: nil
        ))
        let second = try await store.submit(AgentCallSubmission(
            sessionId: nil, requestId: "r2", idempotencyKey: "k1", prompt: "p", mode: .freeform,
            choices: [], consequence: nil, spokenSummary: nil, urgency: .normal, expiresAt: nil
        ))
        guard case .created(let createdCall) = first else {
            Issue.record("expected first to be .created")
            return
        }
        guard case .duplicateSubmission(let existingCallId) = second else {
            Issue.record("expected second to be .duplicateSubmission")
            return
        }
        #expect(existingCallId == createdCall.id)
        #expect(createdCall.sessionId == nil)
    }

    @Test("nil-session submits with DIFFERENT idempotencyKeys never collide")
    func nilSessionDistinctKeysNeverCollide() async throws {
        let store = try AgentCallStore(databaseURL: makeTempStoreURL())
        let first = try await store.submit(AgentCallSubmission(
            sessionId: nil, requestId: "r1", idempotencyKey: "k1", prompt: "p", mode: .freeform,
            choices: [], consequence: nil, spokenSummary: nil, urgency: .normal, expiresAt: nil
        ))
        let second = try await store.submit(AgentCallSubmission(
            sessionId: nil, requestId: "r2", idempotencyKey: "k2", prompt: "p", mode: .freeform,
            choices: [], consequence: nil, spokenSummary: nil, urgency: .normal, expiresAt: nil
        ))
        guard case .created = first, case .created = second else {
            Issue.record("expected both .created")
            return
        }
    }

    // MARK: - Isolation

    @Test("get(id:requestingSessionId:) is nil for a mismatched session")
    func isolationMismatch() async throws {
        let store = try AgentCallStore(databaseURL: makeTempStoreURL())
        let call = try await createCall(store, sessionId: "owner")
        let mismatched = try await store.get(id: call.id, requestingSessionId: "someone-else")
        #expect(mismatched == nil)
        let matching = try await store.get(id: call.id, requestingSessionId: "owner")
        #expect(matching != nil)
    }

    @Test("a nil-session call is only visible to a nil-session requester")
    func nilSessionIsolation() async throws {
        let store = try AgentCallStore(databaseURL: makeTempStoreURL())
        let call = try await createCall(store, sessionId: nil)
        let wrongRequester = try await store.get(id: call.id, requestingSessionId: "someone")
        #expect(wrongRequester == nil)
        let rightRequester = try await store.get(id: call.id, requestingSessionId: nil)
        #expect(rightRequester != nil)
    }

    @Test("get() returns nil for an unknown id")
    func unknownIDReturnsNil() async throws {
        let store = try AgentCallStore(databaseURL: makeTempStoreURL())
        let result = try await store.get(id: UUID(), requestingSessionId: "anyone")
        #expect(result == nil)
    }

    // MARK: - Recovery / expiry

    @Test("a pending row with a past expiresAt becomes .expired after expireOverdue(now:); a future one is untouched")
    func expireOverdueSweep() async throws {
        let store = try AgentCallStore(databaseURL: makeTempStoreURL())
        let past = Date().addingTimeInterval(-10)
        let future = Date().addingTimeInterval(10_000)

        let expiredCandidate = try await createCall(store, expiresAt: past)
        let liveCandidate = try await createCall(store, expiresAt: future)
        let noExpiryCandidate = try await createCall(store, expiresAt: nil)

        try await store.expireOverdue(now: Date())

        let expired = try await store.get(id: expiredCandidate.id, requestingSessionId: expiredCandidate.sessionId)
        let live = try await store.get(id: liveCandidate.id, requestingSessionId: liveCandidate.sessionId)
        let noExpiry = try await store.get(id: noExpiryCandidate.id, requestingSessionId: noExpiryCandidate.sessionId)

        #expect(expired?.state == .expired)
        #expect(live?.state == .pending)
        #expect(noExpiry?.state == .pending)
    }

    @Test("expireOverdue never touches an already-terminal call")
    func expireOverdueSkipsTerminal() async throws {
        let store = try AgentCallStore(databaseURL: makeTempStoreURL())
        let past = Date().addingTimeInterval(-10)
        let call = try await createCall(store, expiresAt: past)
        try await store.resolve(id: call.id, outcome: .declined)

        try await store.expireOverdue(now: Date())

        let fetched = try await store.get(id: call.id, requestingSessionId: call.sessionId)
        #expect(fetched?.state == .declined)
    }

    // MARK: - Lazy expiry (FIX 1: expiry must fire on every read path, not just at launch)

    @Test("get() lazily expires a presented call whose expiresAt has passed — never calling expireOverdue directly")
    func getLazilyExpiresPastDeadline() async throws {
        let store = try AgentCallStore(databaseURL: makeTempStoreURL())
        let past = Date().addingTimeInterval(-10)
        let call = try await createCall(store, expiresAt: past)
        try await store.markPresented(id: call.id)

        // No explicit expireOverdue() call anywhere in this test — get() itself
        // must sweep before reading, or an always-running app would see this
        // call stuck `presented` forever past its deadline.
        let fetched = try await store.get(id: call.id, requestingSessionId: call.sessionId)
        #expect(fetched?.state == .expired)
    }

    @Test("pendingAndPresented() lazily excludes a call whose expiresAt has passed — never calling expireOverdue directly")
    func pendingAndPresentedLazilyExcludesExpired() async throws {
        let store = try AgentCallStore(databaseURL: makeTempStoreURL())
        let past = Date().addingTimeInterval(-10)
        let expiredCandidate = try await createCall(store, expiresAt: past)
        let liveCandidate = try await createCall(store, expiresAt: Date().addingTimeInterval(10_000))

        let inbox = try await store.pendingAndPresented()
        #expect(!inbox.map(\.id).contains(expiredCandidate.id))
        #expect(inbox.map(\.id).contains(liveCandidate.id))
    }

    @Test("a resolve() racing a lazy expiry read — exactly one wins, never both")
    func resolveRacesLazyExpiry() async throws {
        let store = try AgentCallStore(databaseURL: makeTempStoreURL())
        let past = Date().addingTimeInterval(-10)
        let call = try await createCall(store, expiresAt: past)

        // Both operations hit the actor concurrently; actor isolation
        // serializes them, but which one "wins" the terminal state is exactly
        // the CAS question this locks down: whichever runs first claims the
        // non-terminal row, the other's WHERE clause then matches nothing.
        async let resolved: Bool = store.resolve(id: call.id, outcome: .declined)
        async let fetched: AgentCall? = store.get(id: call.id, requestingSessionId: call.sessionId)
        _ = try await (resolved, fetched)

        let finalState = try await store.get(id: call.id, requestingSessionId: call.sessionId)?.state
        // Whichever won, the result is a single well-defined terminal state —
        // never left non-terminal, and never corrupted by both writes applying.
        #expect(finalState == .declined || finalState == .expired)
    }

    // MARK: - pendingAndPresented

    @Test("pendingAndPresented excludes terminal calls")
    func pendingAndPresentedExcludesTerminal() async throws {
        let store = try AgentCallStore(databaseURL: makeTempStoreURL())
        let pending = try await createCall(store)
        let resolved = try await createCall(store)
        try await store.resolve(id: resolved.id, outcome: .declined)

        let inbox = try await store.pendingAndPresented()
        #expect(inbox.map(\.id).contains(pending.id))
        #expect(!inbox.map(\.id).contains(resolved.id))
    }

    // MARK: - Helpers

    @discardableResult
    private func createCall(
        _ store: AgentCallStore, sessionId: String? = "s1", expiresAt: Date? = nil
    ) async throws -> AgentCall {
        let result = try await store.submit(AgentCallSubmission(
            sessionId: sessionId, requestId: UUID().uuidString, idempotencyKey: nil, prompt: "p",
            mode: .freeform, choices: [], consequence: nil, spokenSummary: nil, urgency: .normal,
            expiresAt: expiresAt
        ))
        guard case .created(let call) = result else {
            Issue.record("expected .created")
            throw SpeakError.unknown("test helper: submit did not create")
        }
        return call
    }
}
