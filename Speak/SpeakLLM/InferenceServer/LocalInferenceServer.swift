// SpeakLLM/InferenceServer/LocalInferenceServer.swift
//
// The core HTTP server actor for the speak local AI inference gateway.
// Manages NWListener lifecycle, binds strictly to 127.0.0.1 (loopback only),
// authenticates every request via Bearer token, and dispatches to protocol
// handlers (OpenAI Chat Completions, Anthropic Messages, OpenAI Responses).
//
// Security model:
//   1. NWParameters.acceptLocalOnly = true → kernel rejects non-loopback connections
//   2. Bearer token auth via LocalAPIKeyStore → rejects unauthorized local processes
//   3. No TLS needed (loopback traffic never leaves the machine)
//
// No third-party dependencies. Apple frameworks only (AGENTS.md §2.4).
// No global mutable state — all state owned by this actor (AGENTS.md §2.11).

import Foundation
import Network
import os

/// Errors thrown by the inference server lifecycle.
public enum ServerError: Error, Sendable, Equatable {
    /// The specified port is invalid (0 or already in use).
    case invalidPort(UInt16)
    /// The server failed to start.
    case startFailed(String)
    /// The server is not running.
    case notRunning
}

/// A local HTTP inference server that exposes Apple Intelligence and local LLMs
/// to developer tools via standard OpenAI and Anthropic API protocols.
///
/// Binds strictly to 127.0.0.1 — never exposes on external network interfaces.
/// All requests require a valid Bearer token stored in the macOS Keychain.
///
/// Usage:
/// ```swift
/// let server = LocalInferenceServer()
/// try await server.start(port: 11235)
/// // ... server is now accepting requests ...
/// await server.stop()
/// ```
public actor LocalInferenceServer {

    // MARK: - Constants

    /// Default port for the inference server.
    /// [decision: 11235 — memorable, unlikely to conflict with common dev tools]
    public static let defaultPort: UInt16 = 11235

    /// Maximum receive buffer size per connection read.
    /// [decision: 1MB — sufficient for large prompts; localhost has no bandwidth concern]
    private static let maxReceiveSize = 1_048_576

    /// Logger for server lifecycle and request dispatch.
    private let logger = Logger(subsystem: "com.speak.app", category: "InferenceServer")

    // MARK: - State

    /// The NWListener instance managing TCP connections.
    private var listener: NWListener?

    /// Active connections tracked by unique identifier.
    private var activeConnections: [ObjectIdentifier: NWConnection] = [:]

    /// The API key store for Bearer token authentication.
    private let apiKeyStore = LocalAPIKeyStore()

    /// The inference router for backend dispatch.
    private let router = InferenceRouter()

    /// The model registry for backend discovery.
    private let registry = ModelRegistry()

    /// When the server was started (for uptime reporting).
    private var startTime: Date?

    /// Total requests handled since server start.
    private var totalRequestsHandled: Int = 0

    // MARK: - Public Properties

    /// Whether the server is currently accepting connections.
    public private(set) var isRunning: Bool = false

    /// The port the server is listening on.
    /// [decision: 11235 default — matches defaultPort constant]
    public private(set) var port: UInt16 = 11235

    // MARK: - Init

    public init() {}

    // MARK: - Lifecycle

    /// Starts the inference server on the specified port.
    ///
    /// - Parameter port: TCP port to listen on. Defaults to 11235.
    /// - Throws: `ServerError.invalidPort` if the port cannot be bound,
    ///   `ServerError.startFailed` if the listener fails to initialize.
    public func start(port: UInt16 = LocalInferenceServer.defaultPort) throws {
        guard !isRunning else {
            logger.warning("Server already running on port \(self.port)")
            return
        }

        guard port > 0 else {
            throw ServerError.invalidPort(port)
        }

        guard let nwPort = NWEndpoint.Port(rawValue: port) else {
            throw ServerError.invalidPort(port)
        }

        // Configure TCP parameters with strict loopback binding.
        let parameters = NWParameters.tcp
        parameters.acceptLocalOnly = true

        do {
            let newListener = try NWListener(using: parameters, on: nwPort)
            self.listener = newListener
            self.port = port

            newListener.stateUpdateHandler = { [weak self] state in
                guard let self else { return }
                Task { await self.handleListenerState(state) }
            }

            newListener.newConnectionHandler = { [weak self] connection in
                guard let self else { return }
                Task { await self.handleNewConnection(connection) }
            }

            // Start on a background queue — never blocks the main thread (AGENTS.md §2.12).
            newListener.start(queue: DispatchQueue.global(qos: .userInitiated))

            isRunning = true
            startTime = Date()
            logger.info("Inference server started on 127.0.0.1:\(port)")
        } catch {
            throw ServerError.startFailed(error.localizedDescription)
        }
    }

    /// Stops the server and closes all active connections.
    public func stop() {
        listener?.cancel()
        listener = nil

        for (_, connection) in activeConnections {
            connection.cancel()
        }
        activeConnections.removeAll()

        isRunning = false
        startTime = nil
        logger.info("Inference server stopped")
    }

    /// Returns the current API key (generates one if none exists).
    public func getAPIKey() async -> String {
        await apiKeyStore.currentKey()
    }

    /// Regenerates the API key, invalidating all existing integrations.
    public func regenerateAPIKey() async -> String {
        await apiKeyStore.regenerate()
    }

    // MARK: - Connection Handling

    /// Handles a new incoming TCP connection.
    private func handleNewConnection(_ connection: NWConnection) {
        let connId = ObjectIdentifier(connection)
        activeConnections[connId] = connection

        connection.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .failed, .cancelled:
                Task { await self.removeConnection(connId) }
            default:
                break
            }
        }

        connection.start(queue: DispatchQueue.global(qos: .userInitiated))
        receiveData(connection: connection, connId: connId, buffer: Data())
    }

    /// Removes a connection from the active set.
    private func removeConnection(_ connId: ObjectIdentifier) {
        activeConnections.removeValue(forKey: connId)
    }

    /// Receives data from a connection, accumulating until a full HTTP request is available.
    private func receiveData(connection: NWConnection, connId: ObjectIdentifier, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: Self.maxReceiveSize) {
            [weak self] data, _, isComplete, error in
            guard let self else { return }

            if let error {
                self.logger.debug("Receive error: \(error.localizedDescription, privacy: .public)")
                connection.cancel()
                Task { await self.removeConnection(connId) }
                return
            }

            var accumulated = buffer
            if let data, !data.isEmpty {
                accumulated.append(data)
            }

            // Check if we have a complete HTTP request (headers + body per Content-Length).
            if self.isCompleteRequest(accumulated) {
                Task { await self.processRequest(accumulated, connection: connection, connId: connId) }
            } else if isComplete {
                // Connection closed by peer — process what we have.
                if !accumulated.isEmpty {
                    Task { await self.processRequest(accumulated, connection: connection, connId: connId) }
                } else {
                    connection.cancel()
                    Task { await self.removeConnection(connId) }
                }
            } else {
                // Need more data — continue receiving.
                self.receiveData(connection: connection, connId: connId, buffer: accumulated)
            }
        }
    }

    /// Checks whether the accumulated data contains a complete HTTP request.
    ///
    /// A request is complete when:
    /// 1. The header/body separator (double CRLF) is present, AND
    /// 2. If Content-Length is specified, enough body bytes have arrived.
    private func isCompleteRequest(_ data: Data) -> Bool {
        let separator = Data([0x0D, 0x0A, 0x0D, 0x0A])
        guard let separatorRange = data.range(of: separator) else {
            return false
        }

        // Check Content-Length in headers.
        let headerData = data[data.startIndex..<separatorRange.lowerBound]
        guard let headerStr = String(data: Data(headerData), encoding: .utf8) else {
            return false
        }

        // Look for Content-Length header.
        for line in headerStr.components(separatedBy: "\r\n") {
            let lower = line.lowercased()
            if lower.hasPrefix("content-length:") {
                let valueStr = line.dropFirst("content-length:".count)
                    .trimmingCharacters(in: .whitespaces)
                if let contentLength = Int(valueStr) {
                    let bodyStart = separatorRange.upperBound
                    let bodyReceived = data.distance(from: bodyStart, to: data.endIndex)
                    return bodyReceived >= contentLength
                }
            }
        }

        // No Content-Length — headers complete is sufficient (GET requests).
        return true
    }

    // MARK: - Request Processing

    /// Processes a complete HTTP request: parse, authenticate, dispatch.
    private func processRequest(_ data: Data, connection: NWConnection, connId: ObjectIdentifier) async {
        totalRequestsHandled += 1

        // Parse the HTTP request.
        guard let request = HTTPRequestParser.parse(data: data) else {
            let response = HTTPResponseBuilder.buildErrorResponse(
                status: 400, message: "Malformed HTTP request")
            sendAndClose(response, connection: connection, connId: connId)
            return
        }

        logger.debug("\(request.method, privacy: .public) \(request.path, privacy: .public)")

        // Health endpoint does not require auth (for load balancer probes).
        if request.method == "GET" && request.path == "/health" {
            let activeCount = activeConnections.count
            await ModelsListHandler.handleHealth(
                connection: connection, registry: registry,
                startTime: startTime ?? Date(), activeConnections: activeCount)
            removeConnection(connId)
            return
        }

        // Authenticate via Bearer token.
        let authHeader = request.header("authorization")
        let isValid = await apiKeyStore.validate(authorizationHeader: authHeader)
        guard isValid else {
            let response = HTTPResponseBuilder.buildErrorResponse(
                status: 401, message: "Invalid or missing Authorization header. Expected: Bearer sk-speak-<key>")
            sendAndClose(response, connection: connection, connId: connId)
            return
        }

        // Dispatch by (method, path).
        await dispatch(request: request, connection: connection, connId: connId)
    }

    /// Routes the request to the appropriate handler.
    private func dispatch(request: HTTPRequest, connection: NWConnection, connId: ObjectIdentifier) async {
        switch (request.method, request.path) {
        case ("POST", "/v1/chat/completions"):
            await OpenAIChatCompletionsHandler.handle(
                request: request, connection: connection, router: router)
            removeConnection(connId)

        case ("POST", "/v1/messages"):
            await AnthropicMessagesHandler.handle(
                request: request, connection: connection, router: router)
            removeConnection(connId)

        case ("POST", "/v1/responses"):
            await OpenAIResponsesHandler.handle(
                request: request, connection: connection, router: router)
            removeConnection(connId)

        case ("GET", "/v1/models"):
            await ModelsListHandler.handleModelsList(connection: connection, registry: registry)
            removeConnection(connId)

        default:
            let response = HTTPResponseBuilder.buildErrorResponse(
                status: 404, message: "Endpoint not found: \(request.method) \(request.path)")
            sendAndClose(response, connection: connection, connId: connId)
        }
    }

    // MARK: - Listener State

    /// Handles NWListener state transitions.
    private func handleListenerState(_ state: NWListener.State) {
        switch state {
        case .ready:
            logger.info("NWListener ready on port \(self.port)")
        case .failed(let error):
            logger.error("NWListener failed: \(error.localizedDescription, privacy: .public)")
            stop()
        case .cancelled:
            logger.info("NWListener cancelled")
        default:
            break
        }
    }

    // MARK: - Helpers

    /// Sends response data and closes the connection.
    private func sendAndClose(_ data: Data, connection: NWConnection, connId: ObjectIdentifier) {
        connection.send(content: data, completion: .contentProcessed { [weak self] error in
            if let error {
                self?.logger.debug("Send error: \(error.localizedDescription, privacy: .public)")
            }
            connection.cancel()
            if let self {
                Task { await self.removeConnection(connId) }
            }
        })
    }
}
