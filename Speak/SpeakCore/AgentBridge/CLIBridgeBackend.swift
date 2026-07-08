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

    public func status() async -> BridgeStatusReport {
        do {
            let reply = try transport.send(CLIRequest(cmd: .status))
            guard reply.ok else {
                return BridgeStatusReport(
                    appRunning: true, engineState: nil, hotkeyBinding: nil,
                    detail: reply.error ?? "speak reported an error"
                )
            }
            return BridgeStatusReport(
                appRunning: true,
                engineState: reply.state?.rawValue,
                hotkeyBinding: reply.binding,
                detail: nil
            )
        } catch CLITransportError.portNotFound {
            return BridgeStatusReport(
                appRunning: false, engineState: nil, hotkeyBinding: nil,
                detail: BridgeUnavailable.appNotRunning.reason
            )
        } catch {
            // Any other transport failure (timeout, malformed reply) is
            // still "can't confirm the app is usable" from the agent's point
            // of view — report not-running with the diagnostic in `detail`
            // rather than surfacing a Swift error type across the MCP seam.
            return BridgeStatusReport(
                appRunning: false, engineState: nil, hotkeyBinding: nil,
                detail: "speak_status transport error: \(error)"
            )
        }
    }

    public func say(text: String, interrupt: Bool) async -> Result<Void, BridgeUnavailable> {
        let request = CLIRequest(cmd: .say, text: text, interrupt: interrupt)
        do {
            let reply = try transport.send(request, timeoutSeconds: CLIContract.sendTimeoutSeconds)
            guard reply.ok else {
                return .failure(BridgeUnavailable(reply.error ?? "speak_say reported an error"))
            }
            return .success(())
        } catch CLITransportError.portNotFound {
            return .failure(.appNotRunning)
        } catch {
            return .failure(.transportError("speak_say", String(describing: error)))
        }
    }

    public func ask(question: String, timeoutSeconds: Double?) async -> Result<String, BridgeUnavailable> {
        let effectiveTimeout = timeoutSeconds ?? CLIContract.askConfirmDefaultTimeoutSeconds
        let request = CLIRequest(cmd: .ask, question: question, timeout: effectiveTimeout)
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
            return .success(answer)
        } catch CLITransportError.portNotFound {
            return .failure(.appNotRunning)
        } catch CLITransportError.timeout {
            return .failure(.timedOut("speak_ask"))
        } catch {
            return .failure(.transportError("speak_ask", String(describing: error)))
        }
    }

    public func confirm(question: String) async -> Result<Bool, BridgeUnavailable> {
        let effectiveTimeout = CLIContract.askConfirmDefaultTimeoutSeconds
        let request = CLIRequest(cmd: .confirm, question: question, timeout: effectiveTimeout)
        do {
            let reply = try transport.send(request, timeoutSeconds: effectiveTimeout + 5)
            guard reply.ok else {
                return .failure(.timedOut("speak_confirm"))
            }
            guard let confirmedValue = reply.confirmed else {
                // ok == true but confirmed == nil: the spoken answer was unclear/cancel.
                return .failure(.unclearAnswer("speak_confirm"))
            }
            return .success(confirmedValue)
        } catch CLITransportError.portNotFound {
            return .failure(.appNotRunning)
        } catch CLITransportError.timeout {
            return .failure(.timedOut("speak_confirm"))
        } catch {
            return .failure(.transportError("speak_confirm", String(describing: error)))
        }
    }
}
