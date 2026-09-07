// SpeakCore/AgentBridge/CLIBridgeBackend.swift
//
// Production `BridgeBackend`. Tools reuse the existing CFMessagePort CLI IPC
// (CLIContract / CFMessagePortTransport). `say`/`status`/`register` are short
// accept-acks (`sendTimeoutSeconds`). `ask`/`confirm`/`request_input` submit a
// durable pending call (short send), then this client polls `getCall` until
// terminal or human timeout + slack. [decision: H-3, AVB-7-ask-confirm-pump-fix]

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
            // Contract-version guard: an app build from before/after this one
            // must surface as a loud error, not a plausible-looking normal
            // status reply. [decision: output-conversation-reconnect §4]
            guard reply.contractVersion == CLIContract.bridgeContractVersion else {
                let mismatch = BridgeUnavailable.contractVersionMismatch(
                    runningVersion: reply.contractVersion,
                    expectedVersion: CLIContract.bridgeContractVersion
                )
                return BridgeOutcome(BridgeStatusReport(
                    appRunning: true, engineState: reply.state?.rawValue, hotkeyBinding: reply.binding,
                    detail: mismatch.reason, contractMismatch: true
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

    /// Submit+poll decoupling ([decision: AVB-7-ask-confirm-pump-fix]): the app
    /// replies immediately with a pending `AgentCall`; this client polls `getCall`
    /// until terminal or deadline.
    ///
    /// Adapter durable rows are always submitted with `sessionId: nil` (see
    /// `CLIPortServer.handleAskOrConfirm` / `handleRequestInput`). Poll with `nil`
    /// so store isolation matches. The request's `sessionId` still rides the wire
    /// for the advisory `sessionNote` only.
    private func pollUntilTerminal(callId: UUID, deadline: Date) async -> AgentCall? {
        while true {
            switch await getCall(callId: callId, sessionId: nil) {
            case .success(let outcome):
                if let call = outcome.value, call.state.isTerminal {
                    return call
                }
            case .failure:
                return nil
            }
            if Date() >= deadline { return nil }
            try? await Task.sleep(nanoseconds: CLIContract.terminalPollIntervalNanoseconds)
        }
    }

    public func ask(
        question: String, timeoutSeconds: Double?, sessionId: String?
    ) async -> Result<BridgeOutcome<String>, BridgeUnavailable> {
        let effectiveTimeout = timeoutSeconds ?? CLIContract.askConfirmDefaultTimeoutSeconds
        let request = CLIRequest(cmd: .ask, question: question, timeout: effectiveTimeout, sessionId: sessionId)
        do {
            let reply = try transport.send(request, timeoutSeconds: CLIContract.sendTimeoutSeconds)
            guard reply.ok else {
                return .failure(.timedOut("speak_ask"))
            }
            guard let pending = reply.agentCall else {
                return .failure(.transportError("speak_ask", "reply missing 'agentCall' field"))
            }
            let deadline = Date().addingTimeInterval(
                effectiveTimeout + CLIContract.terminalPollSlackSeconds
            )
            guard let call = await pollUntilTerminal(callId: pending.id, deadline: deadline) else {
                return .failure(.timedOut("speak_ask"))
            }
            guard case .answered(let text, _) = call.response else {
                return .failure(.timedOut("speak_ask"))
            }
            return .success(BridgeOutcome(text ?? "", sessionNote: reply.sessionNote))
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
            let reply = try transport.send(request, timeoutSeconds: CLIContract.sendTimeoutSeconds)
            guard reply.ok else {
                return .failure(.timedOut("speak_confirm"))
            }
            guard let pending = reply.agentCall else {
                return .failure(.transportError("speak_confirm", "reply missing 'agentCall' field"))
            }
            let deadline = Date().addingTimeInterval(
                effectiveTimeout + CLIContract.terminalPollSlackSeconds
            )
            guard let call = await pollUntilTerminal(callId: pending.id, deadline: deadline) else {
                return .failure(.timedOut("speak_confirm"))
            }
            // Production durable resolve stores RequestInputExtractor output:
            // approval "no" → `.declined`, not `.answered(..., "no")`.
            switch call.response {
            case .answered(let text, let choice):
                if choice == "approved" {
                    return .success(BridgeOutcome(true, sessionNote: reply.sessionNote))
                }
                switch YesNoCancelExtractor.extract(text ?? "") {
                case .yes:
                    return .success(BridgeOutcome(true, sessionNote: reply.sessionNote))
                case .no:
                    return .success(BridgeOutcome(false, sessionNote: reply.sessionNote))
                case .cancel, .unclear:
                    return .failure(.unclearAnswer("speak_confirm"))
                }
            case .declined:
                return .success(BridgeOutcome(false, sessionNote: reply.sessionNote))
            case .cancelled:
                return .failure(.unclearAnswer("speak_confirm"))
            case .timedOut, .busy, .none:
                return .failure(.timedOut("speak_confirm"))
            }
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
            let reply = try transport.send(request, timeoutSeconds: CLIContract.sendTimeoutSeconds)
            guard reply.ok else {
                return .failure(.transportError("speak_request_input", reply.error ?? "unknown error"))
            }
            guard let pending = reply.agentCall else {
                return .failure(.transportError("speak_request_input", "reply missing 'agentCall' field"))
            }
            let deadline = Date().addingTimeInterval(
                effectiveTimeout + CLIContract.terminalPollSlackSeconds
            )
            guard let finalCall = await pollUntilTerminal(
                callId: pending.id, deadline: deadline
            ) else {
                return .success(BridgeOutcome(.timedOut, sessionNote: reply.sessionNote))
            }
            let outcome = finalCall.response ?? .timedOut
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

    // MARK: - AVB-7 durable calls

    public func submitCall(
        _ args: SubmitCallArguments
    ) async -> Result<BridgeOutcome<AgentCallSubmitOutcome>, BridgeUnavailable> {
        let request = CLIRequest(
            cmd: .submitCall,
            requestId: args.requestId,
            idempotencyKey: args.idempotencyKey,
            prompt: args.prompt,
            mode: args.mode,
            choices: args.choices,
            consequence: args.consequence,
            spokenSummary: args.spokenSummary,
            sessionId: args.sessionId,
            urgency: args.urgency,
            expiresInSeconds: args.expiresInSeconds
        )
        do {
            let reply = try transport.send(
                request, timeoutSeconds: CLIContract.getCallSendTimeoutSeconds
            )
            guard reply.ok else {
                return .failure(BridgeUnavailable(reply.error ?? "speak_submit_call reported an error"))
            }
            guard let call = reply.agentCall else {
                return .failure(.transportError("speak_submit_call", "reply missing 'agentCall' field"))
            }
            let outcome = AgentCallSubmitOutcome(call: call, duplicate: reply.duplicateSubmission ?? false)
            return .success(BridgeOutcome(outcome, sessionNote: reply.sessionNote))
        } catch CLITransportError.portNotFound {
            return .failure(.appNotRunning)
        } catch {
            return .failure(.transportError("speak_submit_call", String(describing: error)))
        }
    }

    public func getCall(callId: UUID, sessionId: String?) async -> Result<BridgeOutcome<AgentCall?>, BridgeUnavailable> {
        let request = CLIRequest(cmd: .getCall, sessionId: sessionId, callId: callId.uuidString)
        do {
            let reply = try transport.send(
                request, timeoutSeconds: CLIContract.getCallSendTimeoutSeconds
            )
            guard reply.ok else {
                return .failure(BridgeUnavailable(reply.error ?? "speak_get_call reported an error"))
            }
            return .success(BridgeOutcome(reply.agentCall, sessionNote: reply.sessionNote))
        } catch CLITransportError.portNotFound {
            return .failure(.appNotRunning)
        } catch {
            return .failure(.transportError("speak_get_call", String(describing: error)))
        }
    }
}
