// SpeakTests/CLIContractTests.swift
//
// Unit tests for the CLI IPC contract (Wave 2.3):
//   1. CLIRequest / CLIReply JSON codec round-trips.
//   2. CLIState mapping from MenubarIcon.
//   3. Idempotency logic (pure state-transition function).
//   4. CLITransportError descriptions.
//   5. Stub CLITransport — verifies the protocol seam is testable without a
//      live CFMessagePort.

@testable import SpeakCore
import XCTest

final class CLIContractTests: XCTestCase {

    // MARK: - CLIRequest codec

    func testRequestEncodeDecodeStart() throws {
        let req = CLIRequest(cmd: .start)
        let data = try req.encode()
        let decoded = try CLIRequest.decode(data)
        XCTAssertEqual(decoded.cmd, .start)
    }

    func testRequestEncodeDecodeStop() throws {
        let req = CLIRequest(cmd: .stop)
        let data = try req.encode()
        let decoded = try CLIRequest.decode(data)
        XCTAssertEqual(decoded.cmd, .stop)
    }

    func testRequestEncodeDecodeStatus() throws {
        let req = CLIRequest(cmd: .status)
        let data = try req.encode()
        let decoded = try CLIRequest.decode(data)
        XCTAssertEqual(decoded.cmd, .status)
    }

    func testRequestJSONShape() throws {
        let req = CLIRequest(cmd: .start)
        let data = try req.encode()
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertEqual(json?["cmd"] as? String, "start")
    }

    func testRequestDecodeMalformedThrows() {
        let bad = Data("not-json".utf8)
        XCTAssertThrowsError(try CLIRequest.decode(bad))
    }

    func testRequestDecodeUnknownCommandThrows() {
        let bad = Data(#"{"cmd":"launch"}"#.utf8)
        XCTAssertThrowsError(try CLIRequest.decode(bad))
    }

    // MARK: - H-3 say/ask/confirm CLIRequest codec

    func testRequestEncodeDecodeSay() throws {
        let req = CLIRequest(cmd: .say, text: "hello there", interrupt: true)
        let data = try req.encode()
        let decoded = try CLIRequest.decode(data)
        XCTAssertEqual(decoded.cmd, .say)
        XCTAssertEqual(decoded.text, "hello there")
        XCTAssertEqual(decoded.interrupt, true)
    }

    func testRequestSayJSONShape() throws {
        let req = CLIRequest(cmd: .say, text: "hi", interrupt: false)
        let data = try req.encode()
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertEqual(json?["cmd"] as? String, "say")
        XCTAssertEqual(json?["text"] as? String, "hi")
        XCTAssertEqual(json?["interrupt"] as? Bool, false)
    }

    func testRequestEncodeDecodeAsk() throws {
        let req = CLIRequest(cmd: .ask, question: "coffee or tea?", timeout: 30)
        let data = try req.encode()
        let decoded = try CLIRequest.decode(data)
        XCTAssertEqual(decoded.cmd, .ask)
        XCTAssertEqual(decoded.question, "coffee or tea?")
        XCTAssertEqual(decoded.timeout, 30)
    }

    func testRequestEncodeDecodeConfirm() throws {
        let req = CLIRequest(cmd: .confirm, question: "proceed?", timeout: 60)
        let data = try req.encode()
        let decoded = try CLIRequest.decode(data)
        XCTAssertEqual(decoded.cmd, .confirm)
        XCTAssertEqual(decoded.question, "proceed?")
        XCTAssertEqual(decoded.timeout, 60)
    }

    func testRequestAskOmitsTimeoutWhenNil() throws {
        // Caller didn't specify a timeout — the field must be absent/null, not 0,
        // so the app side can fall back to `CLIContract.askConfirmDefaultTimeoutSeconds`.
        let req = CLIRequest(cmd: .ask, question: "q?")
        let data = try req.encode()
        let decoded = try CLIRequest.decode(data)
        XCTAssertNil(decoded.timeout)
    }

    // MARK: - CLIReply codec

    func testReplyAcceptedRoundTrip() throws {
        let reply = CLIReply.accepted()
        let data = try reply.encode()
        let decoded = try CLIReply.decode(data)
        XCTAssertTrue(decoded.ok)
        XCTAssertNil(decoded.error)
        XCTAssertNil(decoded.state)
        XCTAssertNil(decoded.binding)
    }

    func testReplyFailureRoundTrip() throws {
        let reply = CLIReply.failure("speak is not running")
        let data = try reply.encode()
        let decoded = try CLIReply.decode(data)
        XCTAssertFalse(decoded.ok)
        XCTAssertEqual(decoded.error, "speak is not running")
    }

    func testReplyStatusRoundTrip() throws {
        let reply = CLIReply.status(state: .listening, binding: "⌘ Right Command ×2")
        let data = try reply.encode()
        let decoded = try CLIReply.decode(data)
        XCTAssertTrue(decoded.ok)
        XCTAssertEqual(decoded.state, .listening)
        XCTAssertEqual(decoded.binding, "⌘ Right Command ×2")
        XCTAssertNil(decoded.error)
    }

    func testReplyStatusJsonShape() throws {
        let reply = CLIReply.status(state: .idle, binding: "Fn ×2")
        let data = try reply.encode()
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertEqual(json?["ok"] as? Bool, true)
        XCTAssertEqual(json?["state"] as? String, "idle")
        XCTAssertEqual(json?["binding"] as? String, "Fn ×2")
    }

    func testReplyDecodeMalformedThrows() {
        let bad = Data("not-json".utf8)
        XCTAssertThrowsError(try CLIReply.decode(bad))
    }

    // MARK: - H-3 say/ask/confirm CLIReply codec

    func testReplyAskedRoundTrip() throws {
        let reply = CLIReply.asked("blue please")
        let data = try reply.encode()
        let decoded = try CLIReply.decode(data)
        XCTAssertTrue(decoded.ok)
        XCTAssertEqual(decoded.answer, "blue please")
        XCTAssertNil(decoded.confirmed)
        XCTAssertNil(decoded.error)
    }

    func testReplyAskedAllowsEmptyStringAnswer() throws {
        // An empty transcript is a valid (if unusual) spoken answer — distinct
        // from "no answer arrived" (which the app maps to `.failure`, never
        // `.asked("")`). [decision: H-3]
        let reply = CLIReply.asked("")
        let data = try reply.encode()
        let decoded = try CLIReply.decode(data)
        XCTAssertTrue(decoded.ok)
        XCTAssertEqual(decoded.answer, "")
    }

    func testReplyConfirmedTrueRoundTrip() throws {
        let reply = CLIReply.confirmed(true)
        let data = try reply.encode()
        let decoded = try CLIReply.decode(data)
        XCTAssertTrue(decoded.ok)
        XCTAssertEqual(decoded.confirmed, true)
    }

    func testReplyConfirmedFalseRoundTrip() throws {
        let reply = CLIReply.confirmed(false)
        let data = try reply.encode()
        let decoded = try CLIReply.decode(data)
        XCTAssertTrue(decoded.ok)
        XCTAssertEqual(decoded.confirmed, false)
    }

    func testReplyConfirmedUnclearRoundTrip() throws {
        // ok == true but confirmed == nil is the wire shape for "unclear answer".
        let reply = CLIReply.confirmed(nil)
        let data = try reply.encode()
        let decoded = try CLIReply.decode(data)
        XCTAssertTrue(decoded.ok)
        XCTAssertNil(decoded.confirmed)
    }

    // MARK: - AVB-7 durable-call wire

    func testRequestEncodeDecodeSubmitCall() throws {
        let request = CLIRequest(
            cmd: .submitCall, requestId: "r1", idempotencyKey: "k1", prompt: "deploy?", mode: .approval,
            sessionId: "sess-1", urgency: .high, expiresInSeconds: 3600
        )
        let data = try request.encode()
        let decoded = try CLIRequest.decode(data)
        XCTAssertEqual(decoded.cmd, .submitCall)
        XCTAssertEqual(decoded.requestId, "r1")
        XCTAssertEqual(decoded.idempotencyKey, "k1")
        XCTAssertEqual(decoded.mode, .approval)
        XCTAssertEqual(decoded.urgency, .high)
        XCTAssertEqual(decoded.expiresInSeconds, 3600)
    }

    func testRequestEncodeDecodeGetCall() throws {
        let callId = UUID().uuidString
        let request = CLIRequest(cmd: .getCall, sessionId: "sess-1", callId: callId)
        let data = try request.encode()
        let decoded = try CLIRequest.decode(data)
        XCTAssertEqual(decoded.cmd, .getCall)
        XCTAssertEqual(decoded.callId, callId)
        XCTAssertEqual(decoded.sessionId, "sess-1")
    }

    func testReplyCallSubmittedRoundTrip() throws {
        let call = AgentCall(
            id: UUID(), sessionId: "sess-1", requestId: "r1", idempotencyKey: nil, prompt: "p",
            mode: .freeform, choices: [], consequence: nil, spokenSummary: nil, urgency: .normal,
            state: .pending, createdAt: Date(), expiresAt: Date().addingTimeInterval(86_400)
        )
        let reply = CLIReply.callSubmitted(call, duplicate: false)
        let data = try reply.encode()
        let decoded = try CLIReply.decode(data)
        XCTAssertTrue(decoded.ok)
        XCTAssertEqual(decoded.agentCall?.id, call.id)
        XCTAssertEqual(decoded.duplicateSubmission, false)
    }

    func testReplyCallStatusNilRoundTrip() throws {
        // nil = not found / isolation mismatch — still ok:true, never an error.
        let reply = CLIReply.callStatus(nil)
        let data = try reply.encode()
        let decoded = try CLIReply.decode(data)
        XCTAssertTrue(decoded.ok)
        XCTAssertNil(decoded.agentCall)
    }

    // MARK: - CLIState from MenubarIcon

    func testCLIStateFromIdle() {
        XCTAssertEqual(CLIState(from: .idle), .idle)
    }

    func testCLIStateFromListening() {
        XCTAssertEqual(CLIState(from: .listening), .listening)
    }

    func testCLIStateFromProcessing() {
        XCTAssertEqual(CLIState(from: .processing), .processing)
    }

    func testCLIStateFromDoneCollapsesToIdle() {
        // .done is a transient flash; stable target is idle. [decision: W2.3]
        XCTAssertEqual(CLIState(from: .done), .idle)
    }

    func testCLIStateFromErrorCollapsesToIdle() {
        // .error is a recovery state; collapse to idle. [decision: W2.3]
        XCTAssertEqual(CLIState(from: .error), .idle)
    }

    // MARK: - Idempotency decision table (pure, no live app)
    //
    // The idempotency gate lives in CLIPortServer.handle(data:) / MainActor.assumeIsolated.
    // We test the decision rules here as a pure mapping:
    //   start: ok=true  if icon == .idle   (dispatch begin)
    //   start: ok=true  if icon != .idle   (already in desired / transitional state — no-op)
    //   stop:  ok=true  if icon == .listening (dispatch end)
    //   stop:  ok=true  if icon != .listening (already idle or in transition — no-op)
    //
    // These cases verify the decision semantics; the `ok=true` in the no-op path is
    // intentional ("the desired state is already true"). [decision: W2.3]

    func testIdempotencyStartWhenIdle() {
        let result = idempotencyDecision(command: .start, icon: .idle)
        XCTAssertEqual(result, .dispatch, "start from idle should dispatch beginDictation")
    }

    func testIdempotencyStartWhenAlreadyListening() {
        let result = idempotencyDecision(command: .start, icon: .listening)
        XCTAssertEqual(result, .noOp, "start while listening is a no-op (already recording)")
    }

    func testIdempotencyStartWhenProcessing() {
        let result = idempotencyDecision(command: .start, icon: .processing)
        XCTAssertEqual(result, .noOp, "start while processing is a no-op")
    }

    func testIdempotencyStartWhenDone() {
        let result = idempotencyDecision(command: .start, icon: .done)
        XCTAssertEqual(result, .noOp, "start during done flash is a no-op")
    }

    func testIdempotencyStopWhenListening() {
        let result = idempotencyDecision(command: .stop, icon: .listening)
        XCTAssertEqual(result, .dispatch, "stop from listening should dispatch endDictation")
    }

    func testIdempotencyStopWhenIdle() {
        let result = idempotencyDecision(command: .stop, icon: .idle)
        XCTAssertEqual(result, .noOp, "stop when idle is a no-op (already stopped)")
    }

    func testIdempotencyStopWhenProcessing() {
        let result = idempotencyDecision(command: .stop, icon: .processing)
        XCTAssertEqual(result, .noOp, "stop while processing is a no-op (let it finish)")
    }

    func testIdempotencyStatusAlwaysReturnsRead() {
        // status always reads live state — it is never a no-op and never dispatches.
        for icon in [MenubarIcon.idle, .listening, .processing, .done, .error] {
            let result = idempotencyDecision(command: .status, icon: icon)
            XCTAssertEqual(result, .read, "status always reads")
        }
    }

    // MARK: - CLITransportError descriptions

    func testPortNotFoundDescription() {
        let err = CLITransportError.portNotFound
        XCTAssertTrue(err.description.contains("not running"), "portNotFound should mention 'not running'")
    }

    func testTimeoutDescription() {
        let err = CLITransportError.timeout
        XCTAssertTrue(err.description.contains("timed out"), "timeout should mention 'timed out'")
    }

    func testBadReplyDescription() {
        let err = CLITransportError.badReply("unexpected EOF")
        XCTAssertTrue(err.description.contains("unexpected EOF"))
    }

    func testSendFailedDescription() {
        let err = CLITransportError.sendFailed(-1)
        XCTAssertTrue(err.description.contains("-1"))
    }

    // MARK: - Stub CLITransport (protocol seam test)

    func testStubTransportReceivesRequest() throws {
        let stub = StubCLITransport(reply: .accepted())
        let reply = try stub.send(CLIRequest(cmd: .start))
        XCTAssertTrue(reply.ok)
        XCTAssertEqual(stub.lastCommand, .start)
    }

    func testDefaultSendUsesDefaultTimeout() throws {
        // The protocol-extension `send(_:)` convenience must forward
        // `CLIContract.sendTimeoutSeconds` — never a bespoke value — to the
        // explicit-timeout overload. [decision: H-3]
        let stub = StubCLITransport(reply: .accepted())
        _ = try stub.send(CLIRequest(cmd: .start))
        XCTAssertEqual(stub.lastTimeoutSeconds, CLIContract.sendTimeoutSeconds)
    }

    func testExplicitTimeoutOverrideIsPlumbedThrough() throws {
        // `ask`/`confirm` need a much longer timeout than the 3 s default — verify
        // the override actually reaches the transport call, not just the default.
        // [decision: H-3]
        let stub = StubCLITransport(reply: .asked("yes"))
        _ = try stub.send(CLIRequest(cmd: .ask, question: "q?", timeout: 45), timeoutSeconds: 45)
        XCTAssertEqual(stub.lastTimeoutSeconds, 45)
        XCTAssertEqual(stub.lastCommand, .ask)
    }

    func testStubTransportThrowsPortNotFound() {
        let stub = StubCLITransport(error: .portNotFound)
        XCTAssertThrowsError(try stub.send(CLIRequest(cmd: .status))) { error in
            guard case CLITransportError.portNotFound = error else {
                return XCTFail("expected portNotFound, got \(error)")
            }
        }
    }

    // MARK: - Port name constant

    func testPortNameContainsBundleId() {
        // The port name must trace to the app bundle id ("com.speak.app").
        // It does so by construction: the constant is the literal "com.speak.app.cli".
        // This test guards against an accidental rename. [decision: W2.3]
        let name = CLIContract.portName as String
        XCTAssertTrue(name.hasPrefix("com.speak.app"), "port name must trace to com.speak.app")
        XCTAssertTrue(name.hasSuffix(".cli"), "port name must have .cli suffix")
    }

    func testPortNameIsExactValue() {
        XCTAssertEqual(CLIContract.portName as String, "com.speak.app.cli")
    }

    // MARK: - H-3 ask/confirm default timeout constant

    func testAskConfirmDefaultTimeoutIsSixtySeconds() {
        // Guards against an accidental change to the documented default — callers
        // (CLIBridgeBackend, the MCP tool schema's "timeout" description) rely on
        // this being generous enough for a human to notice, think, and answer.
        // [decision: H-3]
        XCTAssertEqual(CLIContract.askConfirmDefaultTimeoutSeconds, 60.0)
    }

    // MARK: - AVB-6 registerSession wire round-trip

    func testRegisterSessionRequestEncodesAllFields() throws {
        let req = CLIRequest(
            cmd: .registerSession, sessionId: "existing-id", provider: "codex", label: "task-1",
            workingDirectory: "/repo", requestedCapabilities: ["notify", "say"]
        )
        let data = try req.encode()
        let decoded = try CLIRequest.decode(data)
        XCTAssertEqual(decoded.cmd, .registerSession)
        XCTAssertEqual(decoded.sessionId, "existing-id")
        XCTAssertEqual(decoded.provider, "codex")
        XCTAssertEqual(decoded.label, "task-1")
        XCTAssertEqual(decoded.workingDirectory, "/repo")
        XCTAssertEqual(decoded.requestedCapabilities, ["notify", "say"])
    }

    func testRegisterSessionRequestOmitsOptionalFieldsWhenAbsent() throws {
        let req = CLIRequest(cmd: .registerSession, provider: "codex", label: "task-1")
        let data = try req.encode()
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertNil(json?["sessionId"])
        XCTAssertNil(json?["workingDirectory"])
        XCTAssertNil(json?["requestedCapabilities"])
    }

    func testRegisteredReplyEncodesSessionIdAndCapabilities() throws {
        let reply = CLIReply.registered(sessionId: "new-id", capabilities: ["notify", "status"])
        let data = try reply.encode()
        let decoded = try CLIReply.decode(data)
        XCTAssertTrue(decoded.ok)
        XCTAssertEqual(decoded.sessionId, "new-id")
        XCTAssertEqual(decoded.capabilities, ["notify", "status"])
    }

    // MARK: - AVB-6 sessionNote plumbing

    func testAcceptedCarriesOptionalSessionNote() throws {
        let reply = CLIReply.accepted(sessionNote: "note: sessionId 'x' is not a registered session (call speak_register_session first) — proceeded anyway.")
        let data = try reply.encode()
        let decoded = try CLIReply.decode(data)
        XCTAssertTrue(decoded.ok)
        XCTAssertNotNil(decoded.sessionNote)
    }

    func testAcceptedOmitsSessionNoteWhenAbsent() throws {
        let reply = CLIReply.accepted()
        let data = try reply.encode()
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertNil(json?["sessionNote"])
    }
}

// [deferred — needs human verification] The live CFMessagePort run-loop-pump
// round-trip in `CLIPortServer.handleAskOrConfirm`/`pumpUntilResult` (the actual
// nested-RunLoop pump while an async Task completes) is inherently timing-sensitive
// and requires a live CFMessagePort pair across two processes/threads to exercise
// meaningfully — not unit-tested here. The pieces that ARE unit tested: request/
// reply encode-decode for say/ask/confirm (above), the timeout override plumbing
// (above), the yes/no/cancel extractor (YesNoCancelExtractorTests.swift), and the
// CLIBridgeBackend → CLIReply translation (AgentBridgeServerTests.swift).

// MARK: - Pure idempotency decision function (tested above)
//
// Mirrors the logic in CLIPortServer.handle(data:) so it can be exercised
// without a live port or MainActor. The real server checks `h.icon` on the
// main actor; this pure version takes the icon as a parameter.
//
// Outcomes:
//   .dispatch — the command should be dispatched (beginDictation or endDictation)
//   .noOp     — the desired state is already true; reply accepted() without action
//   .read     — status: always read the live state

private enum IdempotencyOutcome: Equatable {
    case dispatch, noOp, read
}

private func idempotencyDecision(command: CLICommand, icon: MenubarIcon) -> IdempotencyOutcome {
    switch command {
    case .start:
        return icon == .idle ? .dispatch : .noOp

    case .stop:
        return icon == .listening ? .dispatch : .noOp

    case .status:
        return .read

    case .say, .ask, .confirm, .requestInput, .registerSession, .submitCall, .getCall, .askUser, .streamSpeech:
        // H-3/AVB-5/AVB-6/AVB-7: say/ask/confirm/requestInput/registerSession/
        // submitCall/getCall are not gated by this idempotency table — say is
        // always dispatched (no icon precondition); the rest are handled by the
        // dedicated run-loop pump paths in `CLIPortServer.handleAskOrConfirm`/
        // `handleRequestInput`/`handleRegisterSession`/`handleSubmitCall`/
        // `handleGetCall`, not the `.dispatch`/`.noOp`/`.read` decision this pure
        // mirror models.
        return .read
    }
}

// MARK: - StubCLITransport

/// A test stub for `CLITransport` — records calls and returns pre-canned replies.
final class StubCLITransport: CLITransport, @unchecked Sendable {
    private let stubbedReply: CLIReply?
    private let stubbedError: CLITransportError?
    private(set) var lastCommand: CLICommand?

    init(reply: CLIReply) {
        self.stubbedReply = reply
        self.stubbedError = nil
    }

    init(error: CLITransportError) {
        self.stubbedReply = nil
        self.stubbedError = error
    }

    private(set) var lastTimeoutSeconds: TimeInterval?

    func send(_ request: CLIRequest, timeoutSeconds: TimeInterval) throws -> CLIReply {
        lastCommand = request.cmd
        lastTimeoutSeconds = timeoutSeconds
        if let stubbedErr = stubbedError { throw stubbedErr }
        guard let reply = stubbedReply else {
            throw CLITransportError.badReply("StubCLITransport: no reply configured")
        }
        return reply
    }
}
