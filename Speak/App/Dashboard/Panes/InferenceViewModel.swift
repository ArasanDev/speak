// App/Dashboard/Panes/InferenceViewModel.swift
//
// The observable view model behind the Inference pane. Extracted verbatim from
// `InferencePaneView.swift` during the pane's visual redesign so that BOTH files
// stay under the 400-line file_length budget — the logic here is unchanged and
// the published surface is identical (other files bind to these names).
//
// Holds the app's SHARED `LocalInferenceServer` (injected — owned by
// DictationController, never constructed here) plus its own `ModelRegistry`
// and `InferenceClient`, and polls status periodically. All server
// interactions are async (actor isolation). No print — os.Logger only.

import Foundation
import os
import SpeakLLM
import SwiftUI

// MARK: - InferenceViewModel

/// Observable view model that owns references to the inference server actors
/// and polls status periodically. `@Observable` (not `ObservableObject`) so
/// views invalidate only on the properties they actually read — a poll tick
/// updating `uptimeSeconds` no longer repaints the quick-test console.
@MainActor
@Observable
final class InferenceViewModel {

    // MARK: - Observed state

    /// Whether the inference server is currently accepting connections.
    var isServerRunning = false

    /// The port the server is listening on.
    var serverPort: UInt16 = LocalInferenceServer.defaultPort

    /// The current API key (fetched from the server's key store).
    var apiKey = ""

    /// Discovered inference backends from the model registry.
    var backends: [BackendInfo] = []

    /// Number of active connections (from /health endpoint).
    var activeConnections = 0

    /// Server uptime in seconds (from /health endpoint).
    var uptimeSeconds: TimeInterval = 0

    /// Whether a start/stop operation is in flight.
    var isTogglingServer = false

    /// Whether a model discovery pass is in flight.
    var isDiscovering = false

    /// Quick test console: the prompt input.
    var testPrompt = ""

    /// Quick test console: the selected model ID.
    var selectedModelID = "speak-default"

    /// Quick test console: the response output.
    var testOutput = ""

    /// Whether a test request is in flight.
    var isTesting = false

    /// Whether the regenerate-key confirmation dialog is showing.
    var showRegenerateConfirmation = false

    /// Whether the "Connect Your Tools" card is expanded.
    var showToolsCard = false

    /// Error message to display (transient).
    var errorMessage: String?

    // MARK: - Dependencies

    /// The app's shared inference server — injected from
    /// `DashboardContext.inferenceServer` (owned by `DictationController`), so
    /// this pane and the Agent Playground drive the SAME listener on port
    /// 11235. Must NOT construct its own. [fix: single-server ownership]
    /// `internal` (not private) so SpeakTests can assert instance identity.
    let server: LocalInferenceServer

    /// The model registry actor for backend discovery.
    private let registry = ModelRegistry()

    /// The localhost HTTP client for health checks and test requests.
    private let client = InferenceClient()

    /// Logger for pane-level operations.
    private let logger = Logger(subsystem: "com.speak.app", category: "InferencePane")

    /// The periodic status poll task.
    private var pollTask: Task<Void, Never>?

    /// Poll interval for server status. [decision: 2.5s — responsive without hammering]
    private static let pollIntervalSeconds: UInt64 = 2_500_000_000

    // MARK: - Init

    /// - Parameter server: the shared `LocalInferenceServer` from the
    ///   `DashboardContext`. Required — no default — so a future consumer can't
    ///   silently reintroduce a second listener on the port.
    init(server: LocalInferenceServer) {
        self.server = server
    }

    // MARK: - Lifecycle

    /// Starts periodic status polling. Call from `.task` or `.onAppear`.
    func startPolling() {
        guard pollTask == nil else { return }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.pollStatus()
                try? await Task.sleep(nanoseconds: Self.pollIntervalSeconds)
            }
        }
    }

    /// Stops periodic status polling. Call from `.onDisappear`.
    func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    // MARK: - Server control

    /// Toggles the server between running and stopped states.
    func toggleServer() {
        isTogglingServer = true
        Task { [weak self] in
            guard let self else { return }
            do {
                if await server.isRunning {
                    await server.stop()
                    logger.info("Inference server stopped via dashboard")
                } else {
                    try await server.start()
                    logger.info("Inference server started via dashboard")
                }
            } catch {
                errorMessage = "Server toggle failed: \(error.localizedDescription)"
                logger.error("Server toggle failed: \(error.localizedDescription, privacy: .public)")
            }
            isTogglingServer = false
            await pollStatus()
        }
    }

    // MARK: - API key

    /// Fetches the current API key from the server.
    func loadAPIKey() {
        Task { [weak self] in
            guard let self else { return }
            apiKey = await server.getAPIKey()
        }
    }

    /// Regenerates the API key after user confirmation.
    func regenerateAPIKey() {
        Task { [weak self] in
            guard let self else { return }
            apiKey = await server.regenerateAPIKey()
            logger.info("API key regenerated via dashboard")
        }
    }

    // MARK: - Model discovery

    /// Forces a fresh discovery of all backends.
    func discoverBackends() {
        isDiscovering = true
        Task { [weak self] in
            guard let self else { return }
            await registry.discover()
            backends = await registry.backends
            isDiscovering = false
            logger.debug("Model discovery complete: \(self.backends.count) backends")
        }
    }

    // MARK: - Quick test

    /// Sends a test chat completion request to the local server.
    func runTest() {
        guard !testPrompt.isEmpty else { return }
        isTesting = true
        testOutput = ""

        Task { [weak self] in
            guard let self else { return }
            do {
                let port = await server.port
                let key = await server.getAPIKey()
                let result = try await client.chatCompletion(
                    prompt: testPrompt,
                    model: selectedModelID,
                    port: port,
                    apiKey: key
                )
                testOutput = result
            } catch {
                testOutput = "Error: \(error.localizedDescription)"
                logger.error("Test request failed: \(error.localizedDescription, privacy: .public)")
            }
            isTesting = false
        }
    }

    // MARK: - Polling

    /// Polls server status and health endpoint.
    private func pollStatus() async {
        let running = await server.isRunning
        let port = await server.port

        isServerRunning = running
        serverPort = port

        guard running else {
            activeConnections = 0
            uptimeSeconds = 0
            return
        }

        // Poll the /health endpoint (no auth required) for connections and uptime.
        do {
            let health = try await client.healthCheck(port: port)
            activeConnections = health.activeConnections
            uptimeSeconds = health.uptimeSeconds
        } catch {
            // Health check failed silently — server may be starting up.
            logger.debug("Health poll failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
