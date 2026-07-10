// SpeakCore/AgentBridge/CLIBridgeBackend.swift
//
// Production `BridgeBackend`. All four tools reuse the existing CFMessagePort CLI
// IPC (CLIContract.swift / CFMessagePortTransport) that the `speak` CLI tool already
// uses for `--start`/`--stop`/`--status` — no new transport is introduced. `say` is
// an accept-ack (default 3 s timeout); `ask`/`confirm` use the longer
// `CLIContract.askConfirmDefaultTimeoutSeconds`-scaled timeout via
// `CLITransport.send(_:timeoutSeconds:)`. [decision: H-3]

import Foundation

public final class CLIBridgeBackend: BridgeBackend, @unchecked Sendable {
    private let transport: any CLITransport

    /// - Parameter transport: injectable for tests (see `StubCLITransport` in
    ///   CLIContractTests.swift). Defaults to the production CFMessagePort
    ///   client used by the `speak` CLI tool.
    public init(transport: any CLITransport = CFMessagePortTransport()) {
        self.transport = transport
    }

    public func status(sessionId: String?) async -> BridgeOutcome<BridgeStatusReport> {
        do {
            let reply = try transport.send(CLIRequest(cmd: .status, sessionId: sessionId))
            guard reply.ok else {
                return BridgeOutcome(BridgeStatusReport(
                    appRunning: true, engineState: nil, hotkeyBinding: nil,
                    detail: reply.error ?? "speak reported an error"
                ), sessionNote: reply.sessionNote)
            }
            return BridgeOutcome(BridgeStatusReport(
                appRunning: true,
                engineState: reply.state?.rawValue,
                hotkeyBinding: reply.binding,
                detail: nil
            ), sessionNote: reply.sessionNote)
        } catch CLITransportError.portNotFound {
            return BridgeOutcome(BridgeStatusReport(
                appRunning: false, engineState: nil, hotkeyBinding: nil,
                detail: BridgeUnavailable.appNotRunning.reason
            ))
        } catch {
            // Any other transport failure (timeout, malformed reply) is
            // still "can't confirm the app is usable" from the agent's point
            // of view — report not-running with the diagnostic in `detail`
            // rather than surfacing a Swift error type across the MCP seam.
            return BridgeOutcome(BridgeStatusReport(
                appRunning: false, engineState: nil, hotkeyBinding: nil,
                detail: "speak_status transport error: \(error)"
            ))
        }
    }

    public func say(
        text: String, interrupt: Bool, sessionId: String?
    ) async -> Result<BridgeOutcome<Void>, BridgeUnavailable> {
        let request = CLIRequest(cmd: .say, text: text, interrupt: interrupt, sessionId: sessionId)
        do {
            let reply = try transport.send(request, timeoutSeconds: CLIContract.sendTimeoutSeconds)
            guard reply.ok else {
                return .failure(BridgeUnavailable(reply.error ?? "speak_say reported an error"))
            }
            return .success(BridgeOutcome((), sessionNote: reply.sessionNote))
        } catch CLITransportError.portNotFound {
            return .failure(.appNotRunning)
        } catch {
            return .failure(.transportError("speak_say", String(describing: error)))
        }
    }

    public func ask(
        question: String, timeoutSeconds: Double?, sessionId: String?
    ) async -> Result<BridgeOutcome<String>, BridgeUnavailable> {
        let effectiveTimeout = timeoutSeconds ?? CLIContract.askConfirmDefaultTimeoutSeconds
        let request = CLIRequest(cmd: .ask, question: question, timeout: effectiveTimeout, sessionId: sessionId)
        do {
            // A small buffer beyond the round-trip's own timeout so the app-side
            // reply (which itself waits up to `effectiveTimeout`) has time to arrive
            // before the transport gives up on the wire call. [decision: H-3]
            let reply = try transport.send(request, timeoutSeconds: effectiveTimeout + 5)
            guard reply.ok else {
                return .failure(.timedOut("speak_ask"))
            }
            guard let answer = reply.answer else {
                return .failure(.transportError("speak_ask", "reply missing 'answer' field"))
            }
            return .success(BridgeOutcome(answer, sessionNote: reply.sessionNote))
        } catch CLITransportError.portNotFound {
            return .failure(.appNotRunning)
        } catch CLITransportError.timeout {
            return .failure(.timedOut("speak_ask"))
        } catch {
            return .failure(.transportError("speak_ask", String(describing: error)))
        }
    }

    public func confirm(question: String, sessionId: String?) async -> Result<BridgeOutcome<Bool>, BridgeUnavailable> {
        let effectiveTimeout = CLIContract.askConfirmDefaultTimeoutSeconds
        let request = CLIRequest(cmd: .confirm, question: question, timeout: effectiveTimeout, sessionId: sessionId)
        do {
            let reply = try transport.send(request, timeoutSeconds: effectiveTimeout + 5)
            guard reply.ok else {
                return .failure(.timedOut("speak_confirm"))
            }
            guard let confirmedValue = reply.confirmed else {
                // ok == true but confirmed == nil: the spoken answer was unclear/cancel.
                return .failure(.unclearAnswer("speak_confirm"))
            }
            return .success(BridgeOutcome(confirmedValue, sessionNote: reply.sessionNote))
        } catch CLITransportError.portNotFound {
            return .failure(.appNotRunning)
        } catch CLITransportError.timeout {
            return .failure(.timedOut("speak_confirm"))
        } catch {
            return .failure(.transportError("speak_confirm", String(describing: error)))
        }
    }

    // MARK: - AVB-5 requestInput

    public func requestInput(
        _ call: RequestInputCall
    ) async -> Result<BridgeOutcome<HumanResponseOutcome>, BridgeUnavailable> {
        let effectiveTimeout = call.timeoutSeconds ?? CLIContract.askConfirmDefaultTimeoutSeconds
        let request = CLIRequest(
            cmd: .requestInput,
            timeout: effectiveTimeout,
            requestId: call.requestId,
            idempotencyKey: call.idempotencyKey,
            prompt: call.prompt,
            mode: call.mode,
            choices: call.choices,
            consequence: call.consequence,
            spokenSummary: call.spokenSummary,
            sessionId: call.sessionId
        )
        do {
            // Same buffer rationale as `ask`/`confirm` above: the app-side reply
            // itself waits up to `effectiveTimeout`. [decision: AVB-5]
            let reply = try transport.send(request, timeoutSeconds: effectiveTimeout + 5)
            guard reply.ok else {
                return .failure(.transportError("speak_request_input", reply.error ?? "unknown error"))
            }
            guard let outcome = reply.decodedHumanResponseOutcome() else {
                return .failure(.transportError("speak_request_input", "reply missing/invalid 'outcome' field"))
            }
            return .success(BridgeOutcome(outcome, sessionNote: reply.sessionNote))
        } catch CLITransportError.portNotFound {
            return .failure(.appNotRunning)
        } catch CLITransportError.timeout {
            return .failure(.timedOut("speak_request_input"))
        } catch {
            return .failure(.transportError("speak_request_input", String(describing: error)))
        }
    }

    // MARK: - AVB-6 registerSession

    public func registerSession(
        sessionId: String?,
        provider: String,
        label: String,
        workingDirectory: String?,
        requestedCapabilities: [String]
    ) async -> Result<(sessionId: String, capabilities: [String]), BridgeUnavailable> {
        let request = CLIRequest(
            cmd: .registerSession,
            sessionId: sessionId,
            provider: provider,
            label: label,
            workingDirectory: workingDirectory,
            requestedCapabilities: requestedCapabilities
        )
        do {
            let reply = try transport.send(request, timeoutSeconds: CLIContract.sendTimeoutSeconds)
            guard reply.ok else {
                return .failure(BridgeUnavailable(reply.error ?? "speak_register_session reported an error"))
            }
            guard let registeredId = reply.sessionId else {
                return .failure(.transportError("speak_register_session", "reply missing 'sessionId' field"))
            }
            return .success((sessionId: registeredId, capabilities: reply.capabilities ?? []))
        } catch CLITransportError.portNotFound {
            return .failure(.appNotRunning)
        } catch {
            return .failure(.transportError("speak_register_session", String(describing: error)))
        }
    }
}
