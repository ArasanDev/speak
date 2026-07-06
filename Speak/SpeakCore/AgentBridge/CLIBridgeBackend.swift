// SpeakCore/AgentBridge/CLIBridgeBackend.swift
//
// Production `BridgeBackend`. `status()` reuses the existing CFMessagePort
// CLI IPC (CLIContract.swift / CFMessagePortTransport) that the `speak` CLI
// tool already uses for `--status` — no new transport is introduced for this
// slice. `say`/`ask`/`confirm` have no live seam to call yet (see
// BridgeBackend.swift) and always report `.failure`.

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
        .failure(.noSynthesizer("speak_say"))
    }

    public func ask(question: String, timeoutSeconds: Double?) async -> Result<String, BridgeUnavailable> {
        .failure(.needsTransport("speak_ask"))
    }

    public func confirm(question: String) async -> Result<Bool, BridgeUnavailable> {
        .failure(.needsTransport("speak_confirm"))
    }
}
