// SpeakLLM/InferenceServer/ModelsListHandler.swift
//
// Handles GET /v1/models (OpenAI model list) and GET /health (server status).
// Returns standard OpenAI model objects for IDE auto-discovery compatibility.
//
// No third-party dependencies. Apple frameworks only (AGENTS.md §2.4).

import Foundation
import Network
import os

/// Handles the models list and health check endpoints.
///
/// GET /v1/models — Returns an OpenAI-compatible model list for tool auto-discovery.
/// GET /health — Returns server status, uptime, connection count, and backend health.
public enum ModelsListHandler {

    // MARK: - Constants

    /// Logger for request handling.
    private static let logger = Logger(subsystem: "com.speak.app", category: "InferenceServer")

    /// Server version string reported in health checks.
    /// [decision: semver matches the product version in project.yml]
    private static let serverVersion = "speak-inference/0.1.0"

    // MARK: - Models List (GET /v1/models)

    /// Handles GET /v1/models — returns the OpenAI model list.
    ///
    /// - Parameters:
    ///   - connection: The NWConnection to send the response on.
    ///   - registry: The model registry for backend discovery.
    static func handleModelsList(connection: NWConnection, registry: ModelRegistry) async {
        let backends = await registry.backends
        let created = Int(Date().timeIntervalSince1970)

        let models: [[String: Any]] = backends.map { backend in
            [
                "id": backend.id,
                "object": "model",
                "created": created,
                "owned_by": backend.ownedBy,
                "permission": [] as [Any],
                "root": backend.id,
                "parent": NSNull(),
            ]
        }

        let responseBody: [String: Any] = [
            "object": "list",
            "data": models,
        ]

        guard let jsonData = try? JSONSerialization.data(withJSONObject: responseBody) else {
            let errorResponse = HTTPResponseBuilder.buildErrorResponse(
                status: 500, message: "Failed to serialize model list")
            sendAndClose(errorResponse, connection: connection)
            return
        }

        let response = HTTPResponseBuilder.buildJSONResponse(status: 200, jsonData: jsonData)
        sendAndClose(response, connection: connection)
    }

    // MARK: - Health Check (GET /health)

    /// Handles GET /health — returns server status JSON.
    ///
    /// - Parameters:
    ///   - connection: The NWConnection to send the response on.
    ///   - registry: The model registry for backend status.
    ///   - startTime: When the server was started (for uptime calculation).
    ///   - activeConnections: Current number of active connections.
    static func handleHealth(
        connection: NWConnection,
        registry: ModelRegistry,
        startTime: Date,
        activeConnections: Int
    ) async {
        let uptimeSeconds = Int(Date().timeIntervalSince(startTime))
        let backendStatus = await registry.backendStatusSummary()

        let responseBody: [String: Any] = [
            "status": "ok",
            "server": serverVersion,
            "uptime_seconds": uptimeSeconds,
            "active_connections": activeConnections,
            "backends": backendStatus,
        ]

        guard let jsonData = try? JSONSerialization.data(withJSONObject: responseBody) else {
            let errorResponse = HTTPResponseBuilder.buildErrorResponse(
                status: 500, message: "Failed to serialize health status")
            sendAndClose(errorResponse, connection: connection)
            return
        }

        let response = HTTPResponseBuilder.buildJSONResponse(status: 200, jsonData: jsonData)
        sendAndClose(response, connection: connection)
    }

    // MARK: - Helpers

    /// Sends data and closes the connection.
    private static func sendAndClose(_ data: Data, connection: NWConnection) {
        connection.send(content: data, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
}
