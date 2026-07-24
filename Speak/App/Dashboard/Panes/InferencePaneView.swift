// App/Dashboard/Panes/InferencePaneView.swift
//
// The Inference pane — developer visibility into the local inference server.
// Shows server status, API key management, discovered model backends, a quick
// test console, and copy-paste integration snippets for popular dev tools.
//
// The inference server (SpeakLLM/InferenceServer/) is a loopback-only HTTP
// gateway that exposes Apple Intelligence and local LLMs via standard OpenAI
// and Anthropic API protocols. This pane is its control surface.
//
// All server interactions are async (actor isolation). Copy buttons use
// NSPasteboard write-only (AGENTS.md §2.6). No print — os.Logger only.

import AppKit
import Foundation
import os
import SpeakCore
import SpeakLLM
import SwiftUI

// MARK: - InferenceViewModel

/// Observable view model that owns references to the inference server actors
/// and polls status periodically. All state is published for SwiftUI binding.
@MainActor
final class InferenceViewModel: ObservableObject {

    // MARK: - Published state

    /// Whether the inference server is currently accepting connections.
    @Published var isServerRunning = false

    /// The port the server is listening on.
    @Published var serverPort: UInt16 = LocalInferenceServer.defaultPort

    /// The current API key (fetched from the server's key store).
    @Published var apiKey = ""

    /// Discovered inference backends from the model registry.
    @Published var backends: [BackendInfo] = []

    /// Number of active connections (from /health endpoint).
    @Published var activeConnections = 0

    /// Server uptime in seconds (from /health endpoint).
    @Published var uptimeSeconds: TimeInterval = 0

    /// Whether a start/stop operation is in flight.
    @Published var isTogglingServer = false

    /// Whether a model discovery pass is in flight.
    @Published var isDiscovering = false

    /// Quick test console: the prompt input.
    @Published var testPrompt = ""

    /// Quick test console: the selected model ID.
    @Published var selectedModelID = "speak-default"

    /// Quick test console: the response output.
    @Published var testOutput = ""

    /// Whether a test request is in flight.
    @Published var isTesting = false

    /// Whether the regenerate-key confirmation dialog is showing.
    @Published var showRegenerateConfirmation = false

    /// Whether the "Connect Your Tools" card is expanded.
    @Published var showToolsCard = false

    /// Error message to display (transient).
    @Published var errorMessage: String?

    // MARK: - Private dependencies

    /// The local inference server actor.
    private let server = LocalInferenceServer()

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

// MARK: - InferencePaneView

/// The Inference dashboard pane — developer visibility into the local
/// inference server. Follows the standard pane pattern: takes a
/// `DashboardContext`, renders content in a ScrollView.
struct InferencePaneView: View {
    let context: DashboardContext

    @StateObject private var viewModel = InferenceViewModel()

    init(context: DashboardContext) {
        self.context = context
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PaneHeader(
                title: "Inference",
                subtitle: "Local AI inference server — OpenAI & Anthropic compatible, loopback only."
            )

            ScrollView {
                VStack(alignment: .leading, spacing: SpeakSpacing.lg) {
                    ServerStatusCard(viewModel: viewModel)
                    APIKeyCard(viewModel: viewModel)
                    ModelRegistryGrid(viewModel: viewModel)
                    QuickTestConsole(viewModel: viewModel, context: context)
                    ConnectToolsCard(viewModel: viewModel)
                }
                .padding(SpeakSpacing.lg)
            }
        }
        .task {
            viewModel.loadAPIKey()
            viewModel.discoverBackends()
            viewModel.startPolling()
        }
        .onDisappear {
            viewModel.stopPolling()
        }
    }
}

// MARK: - ServerStatusCard

/// Shows server running/stopped state, base URL, start/stop toggle,
/// active connections, and uptime. Uses `.flowBorder` when running.
private struct ServerStatusCard: View {
    @ObservedObject var viewModel: InferenceViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: SpeakSpacing.md) {
            // Header row: status dot + title + toggle button
            HStack(spacing: SpeakSpacing.sm) {
                Circle()
                    .fill(viewModel.isServerRunning
                        ? Color.speakDelivered
                        : Color(nsColor: .systemRed))
                    .frame(width: 10, height: 10)

                Text("Server Status")
                    .font(.speakMonoBody)

                Spacer(minLength: 0)

                Button(action: { viewModel.toggleServer() }) {
                    HStack(spacing: SpeakSpacing.xs) {
                        Image(systemName: viewModel.isServerRunning ? "stop.fill" : "play.fill")
                            .font(.system(size: 11))
                        Text(viewModel.isServerRunning ? "Stop" : "Start")
                            .font(.speakMonoCaption)
                    }
                    .padding(.horizontal, SpeakSpacing.sm)
                    .padding(.vertical, SpeakSpacing.xs)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(viewModel.isServerRunning
                                ? Color(nsColor: .systemRed).opacity(0.15)
                                : Color.speakDelivered.opacity(0.15))
                    )
                    .foregroundStyle(viewModel.isServerRunning
                        ? Color(nsColor: .systemRed)
                        : Color.speakDelivered)
                }
                .buttonStyle(.plain)
                .disabled(viewModel.isTogglingServer)
            }

            // Base URL row with copy button
            HStack(spacing: SpeakSpacing.sm) {
                Text("Base URL")
                    .font(.speakMonoCaption)
                    .foregroundStyle(.secondary)
                    .frame(width: 80, alignment: .leading)

                Text("http://localhost:\(viewModel.serverPort)")
                    .font(.speakMonoBody)
                    .textSelection(.enabled)

                Spacer(minLength: 0)

                CopyButton(text: "http://localhost:\(viewModel.serverPort)")
            }

            // Metrics row
            HStack(spacing: SpeakSpacing.lg) {
                metricLabel(
                    value: viewModel.isServerRunning ? "\(viewModel.activeConnections)" : "—",
                    label: "Connections"
                )
                metricLabel(
                    value: viewModel.isServerRunning ? formatUptime(viewModel.uptimeSeconds) : "—",
                    label: "Uptime"
                )
                metricLabel(
                    value: viewModel.isServerRunning ? "127.0.0.1" : "—",
                    label: "Bind"
                )
                Spacer(minLength: 0)
            }

            if let error = viewModel.errorMessage {
                Text(error)
                    .font(.speakMonoCaption)
                    .foregroundStyle(Color(nsColor: .systemRed))
            }
        }
        .padding(SpeakSpacing.md)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.speakSurface)
        )
        .flowBorder(
            colors: Color.speakFlowInference,
            isActive: viewModel.isServerRunning
        )
    }

    private func metricLabel(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: SpeakSpacing.xs) {
            Text(value)
                .font(.speakMonoBody)
                .foregroundStyle(Color.speakAccent)
            Text(label)
                .font(.speakMonoCaption)
                .foregroundStyle(.secondary)
        }
    }

    private func formatUptime(_ seconds: TimeInterval) -> String {
        let totalSeconds = Int(seconds)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let secs = totalSeconds % 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else if minutes > 0 {
            return "\(minutes)m \(secs)s"
        }
        return "\(secs)s"
    }
}

// MARK: - APIKeyCard

/// Shows the masked API key with copy and regenerate buttons.
private struct APIKeyCard: View {
    @ObservedObject var viewModel: InferenceViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: SpeakSpacing.md) {
            Text("API Key")
                .font(.speakMonoBody)

            HStack(spacing: SpeakSpacing.sm) {
                Text(maskedKey(viewModel.apiKey))
                    .font(.speakMonoBody)
                    .textSelection(.enabled)

                Spacer(minLength: 0)

                CopyButton(text: viewModel.apiKey)

                Button(action: { viewModel.showRegenerateConfirmation = true }) {
                    HStack(spacing: SpeakSpacing.xs) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 11))
                        Text("Regenerate")
                            .font(.speakMonoCaption)
                    }
                    .padding(.horizontal, SpeakSpacing.sm)
                    .padding(.vertical, SpeakSpacing.xs)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.speakAgentViolet.opacity(0.15))
                    )
                    .foregroundStyle(Color.speakAgentViolet)
                }
                .buttonStyle(.plain)
            }

            Text("Bearer token required for all API requests. Stored in macOS Keychain.")
                .font(.speakMonoCaption)
                .foregroundStyle(.secondary)
        }
        .padding(SpeakSpacing.md)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.speakSurface)
        )
        .confirmationDialog(
            "Regenerate API Key?",
            isPresented: $viewModel.showRegenerateConfirmation,
            titleVisibility: .visible
        ) {
            Button("Regenerate", role: .destructive) {
                viewModel.regenerateAPIKey()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("All existing tool integrations using the old key will receive 401 until reconfigured.")
        }
    }

    /// Masks the API key for display: shows prefix and last 4 chars.
    private func maskedKey(_ key: String) -> String {
        guard key.count > 16 else { return key.isEmpty ? "sk-speak-****" : key }
        let prefix = String(key.prefix(10))
        let suffix = String(key.suffix(4))
        return "\(prefix)****...****\(suffix)"
    }
}

// MARK: - ModelRegistryGrid

/// Shows discovered inference backends with status indicators.
private struct ModelRegistryGrid: View {
    @ObservedObject var viewModel: InferenceViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: SpeakSpacing.md) {
            HStack {
                Text("Model Registry")
                    .font(.speakMonoBody)

                Spacer(minLength: 0)

                Button(action: { viewModel.discoverBackends() }) {
                    HStack(spacing: SpeakSpacing.xs) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 11))
                            .rotationEffect(.degrees(viewModel.isDiscovering ? 360 : 0))
                            .animation(
                                viewModel.isDiscovering
                                    ? .linear(duration: 1.0).repeatForever(autoreverses: false)
                                    : .default,
                                value: viewModel.isDiscovering
                            )
                        Text("Refresh")
                            .font(.speakMonoCaption)
                    }
                    .padding(.horizontal, SpeakSpacing.sm)
                    .padding(.vertical, SpeakSpacing.xs)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.speakSurface)
                    )
                    .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .disabled(viewModel.isDiscovering)
            }

            if viewModel.backends.isEmpty {
                Text("No backends discovered. Click Refresh to scan.")
                    .font(.speakMonoCaption)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, SpeakSpacing.sm)
            } else {
                VStack(alignment: .leading, spacing: SpeakSpacing.xs) {
                    ForEach(viewModel.backends) { backend in
                        BackendRow(backend: backend)
                        if backend.id != viewModel.backends.last?.id {
                            Divider()
                        }
                    }
                }
            }
        }
        .padding(SpeakSpacing.md)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.speakSurface)
        )
    }
}

// MARK: - BackendRow

/// A single backend row: status dot, name, endpoint, ownedBy.
private struct BackendRow: View {
    let backend: BackendInfo

    var body: some View {
        HStack(spacing: SpeakSpacing.sm) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 2) {
                Text(backend.name)
                    .font(.speakMonoCaption)
                    .lineLimit(1)

                HStack(spacing: SpeakSpacing.sm) {
                    Text(backend.id)
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)

                    if let endpoint = backend.endpoint {
                        Text(endpoint)
                            .font(.system(size: 9))
                            .foregroundStyle(.tertiary)
                    }

                    Text(backend.ownedBy)
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, SpeakSpacing.xs)
                        .padding(.vertical, 1)
                        .background(
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.speakAgentViolet.opacity(0.1))
                        )
                }
            }

            Spacer(minLength: 0)

            Text(backend.status.rawValue)
                .font(.system(size: 9))
                .foregroundStyle(statusColor)
        }
        .padding(.vertical, SpeakSpacing.xs)
    }

    private var statusColor: Color {
        switch backend.status {
        case .available:
            return Color.speakDelivered

        case .reachable:
            return Color.speakDelivered

        case .offline:
            return Color(nsColor: .systemRed)

        case .unknown:
            return Color(nsColor: .systemYellow)
        }
    }
}

// MARK: - QuickTestConsole

/// A prompt input + model picker + run button + output display for
/// testing the local inference server directly from the dashboard.
private struct QuickTestConsole: View {
    @ObservedObject var viewModel: InferenceViewModel
    let context: DashboardContext

    var body: some View {
        VStack(alignment: .leading, spacing: SpeakSpacing.md) {
            Text("Quick Test")
                .font(.speakMonoBody)

            // Model picker
            HStack(spacing: SpeakSpacing.sm) {
                Text("Model")
                    .font(.speakMonoCaption)
                    .foregroundStyle(.secondary)

                Picker("Model", selection: $viewModel.selectedModelID) {
                    if viewModel.backends.isEmpty {
                        Text("speak-default").tag("speak-default")
                    } else {
                        ForEach(viewModel.backends) { backend in
                            Text(backend.name).tag(backend.id)
                        }
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: 300)

                Spacer(minLength: 0)
            }

            // Prompt input
            TextField("Enter a test prompt...", text: $viewModel.testPrompt, axis: .vertical)
                .font(.speakMonoBody)
                .textFieldStyle(.roundedBorder)
                .lineLimit(1...4)

            // Action buttons
            HStack(spacing: SpeakSpacing.sm) {
                Button(action: { viewModel.runTest() }) {
                    HStack(spacing: SpeakSpacing.xs) {
                        Image(systemName: "play.fill")
                            .font(.system(size: 11))
                        Text("Run")
                            .font(.speakMonoCaption)
                    }
                    .padding(.horizontal, SpeakSpacing.md)
                    .padding(.vertical, SpeakSpacing.xs)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.speakAgentViolet.opacity(0.2))
                    )
                    .foregroundStyle(Color.speakAgentViolet)
                }
                .buttonStyle(.plain)
                .disabled(viewModel.testPrompt.isEmpty || viewModel.isTesting || !viewModel.isServerRunning)

                // Mic/dictation button — wires to speakEngine if available
                if let engine = context.speakEngine {
                    Button(action: {
                        Task {
                            do {
                                _ = try await engine.beginDictation()
                            } catch {
                                // Dictation start failed — logged by engine.
                            }
                        }
                    }) {
                        HStack(spacing: SpeakSpacing.xs) {
                            Image(systemName: "mic.fill")
                                .font(.system(size: 11))
                            Text("Dictate")
                                .font(.speakMonoCaption)
                        }
                        .padding(.horizontal, SpeakSpacing.md)
                        .padding(.vertical, SpeakSpacing.xs)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color.speakHumanAmber.opacity(0.2))
                        )
                        .foregroundStyle(Color.speakHumanAmber)
                    }
                    .buttonStyle(.plain)
                }

                Spacer(minLength: 0)

                if viewModel.isTesting {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            // Output display
            if !viewModel.testOutput.isEmpty {
                ScrollView {
                    Text(viewModel.testOutput)
                        .font(.speakMonoCaption)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(SpeakSpacing.sm)
                }
                .frame(maxHeight: 200)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.black.opacity(0.05))
                )
            }

            if !viewModel.isServerRunning {
                Text("Start the server to run tests.")
                    .font(.speakMonoCaption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(SpeakSpacing.md)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.speakSurface)
        )
    }
}

// MARK: - ConnectToolsCard

/// Collapsible card showing copy-paste integration snippets for popular
/// developer tools. Each snippet uses the actual port and API key.
private struct ConnectToolsCard: View {
    @ObservedObject var viewModel: InferenceViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: SpeakSpacing.md) {
            // Collapsible header
            Button(action: { viewModel.showToolsCard.toggle() }) {
                HStack(spacing: SpeakSpacing.sm) {
                    Image(systemName: viewModel.showToolsCard ? "chevron.down" : "chevron.right")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Text("Connect Your Tools")
                        .font(.speakMonoBody)
                    Spacer(minLength: 0)
                    Text("Python · cURL · Cursor · Claude Code")
                        .font(.speakMonoCaption)
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)

            if viewModel.showToolsCard {
                let port = viewModel.serverPort
                let key = viewModel.apiKey.isEmpty ? "sk-speak-<your-key>" : viewModel.apiKey
                let baseURL = "http://localhost:\(port)/v1"

                VStack(alignment: .leading, spacing: SpeakSpacing.md) {
                    CodeSnippetBlock(title: "Python (OpenAI SDK)",
                        code: pythonOpenAISnippet(baseURL: baseURL, key: key))
                    CodeSnippetBlock(title: "Python (Anthropic SDK)",
                        code: pythonAnthropicSnippet(baseURL: baseURL, key: key))
                    CodeSnippetBlock(title: "cURL",
                        code: curlSnippet(baseURL: baseURL, key: key))
                    CodeSnippetBlock(title: "Cursor (settings.json)",
                        code: cursorSnippet(baseURL: baseURL, key: key))
                    CodeSnippetBlock(title: "Claude Code (settings.json)",
                        code: claudeCodeSnippet(baseURL: baseURL, key: key))
                    CodeSnippetBlock(title: "Environment Variables (.zshrc)",
                        code: envSnippet(baseURL: baseURL, key: key))
                }
            }
        }
        .padding(SpeakSpacing.md)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.speakSurface)
        )
    }

    // MARK: - Snippet generators

    private func pythonOpenAISnippet(baseURL: String, key: String) -> String {
        """
        from openai import OpenAI
        client = OpenAI(base_url="\(baseURL)", api_key="\(key)")
        response = client.chat.completions.create(
            model="speak-default",
            messages=[{"role": "user", "content": "Hello from speak"}]
        )
        result = response.choices[0].message.content
        """
    }

    private func pythonAnthropicSnippet(baseURL: String, key: String) -> String {
        """
        # pip install anthropic
        from anthropic import Anthropic
        client = Anthropic(base_url="\(baseURL)", api_key="\(key)")
        message = client.messages.create(
            model="speak-default", max_tokens=1024,
            messages=[{"role": "user", "content": "Hello from speak"}]
        )
        result = message.content[0].text
        """
    }

    private func curlSnippet(baseURL: String, key: String) -> String {
        """
        curl \(baseURL)/chat/completions \\
          -H "Content-Type: application/json" \\
          -H "Authorization: Bearer \(key)" \\
          -d '{"model": "speak-default", "messages": [{"role": "user", "content": "Hello"}]}'
        """
    }

    private func cursorSnippet(baseURL: String, key: String) -> String {
        """
        {
          "openai.apiKey": "\(key)",
          "openai.apiBaseUrl": "\(baseURL)",
          "openai.model": "speak-default"
        }
        """
    }

    private func claudeCodeSnippet(baseURL: String, key: String) -> String {
        """
        {
          "apiBaseUrl": "\(baseURL)",
          "apiKey": "\(key)",
          "model": "speak-default"
        }
        """
    }

    private func envSnippet(baseURL: String, key: String) -> String {
        """
        export OPENAI_BASE_URL="\(baseURL)"
        export OPENAI_API_KEY="\(key)"
        export ANTHROPIC_BASE_URL="\(baseURL)"
        export ANTHROPIC_API_KEY="\(key)"
        """
    }
}

// MARK: - CodeSnippetBlock

/// A titled code block with a copy button. Used by ConnectToolsCard.
private struct CodeSnippetBlock: View {
    let title: String
    let code: String

    var body: some View {
        VStack(alignment: .leading, spacing: SpeakSpacing.xs) {
            HStack {
                Text(title)
                    .font(.speakMonoCaption)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                CopyButton(text: code)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                Text(code)
                    .font(.speakMonoCaption)
                    .textSelection(.enabled)
                    .padding(SpeakSpacing.sm)
            }
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.black.opacity(0.05))
            )
        }
    }
}

// MARK: - CopyButton

/// A small copy button that writes to NSPasteboard (write-only, AGENTS.md §2.6).
private struct CopyButton: View {
    let text: String

    @State private var copied = false

    var body: some View {
        Button(action: copyToPasteboard) {
            Image(systemName: copied ? "checkmark" : "doc.on.doc")
                .font(.system(size: 11))
                .foregroundStyle(copied ? Color.speakDelivered : .secondary)
                .frame(width: 24, height: 24)
        }
        .buttonStyle(.plain)
        .help(copied ? "Copied" : "Copy to clipboard")
    }

    private func copyToPasteboard() {
        // Write-only pasteboard access (AGENTS.md §2.6: never read the pasteboard).
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        copied = true
        Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            copied = false
        }
    }
}

// MARK: - Preview

#if DEBUG
#Preview("Inference") {
    InferencePaneView(context: DashboardContext(
        settingsStore: SettingsStore(),
        historyStore: PreviewNullHistoryStore(),
        hotkeyCombo: ["Fn", "Fn"]
    ))
    .frame(width: 900, height: 700)
}
#endif
