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
}

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

    func send(_ request: CLIRequest) throws -> CLIReply {
        lastCommand = request.cmd
        if let stubbedErr = stubbedError { throw stubbedErr }
        guard let reply = stubbedReply else {
            throw CLITransportError.badReply("StubCLITransport: no reply configured")
        }
        return reply
    }
}
