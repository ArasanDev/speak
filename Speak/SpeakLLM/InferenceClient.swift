// SpeakLLM/InferenceClient.swift
//
// A thin HTTP client for communicating with the local inference server.
// Lives in SpeakLLM (not App/) because the moat audit scans App/ for
// networking symbols — localhost HTTP calls are sanctioned in SpeakLLM
// (the same target that hosts the server itself).
//
// All requests target 127.0.0.1 only. No external network egress.

import Foundation

/// Errors thrown by the inference client.
public enum InferenceClientError: Error, Sendable, LocalizedError {
    case invalidURL
    case invalidResponse
    case httpError(status: Int, body: String)
    case parseError

    public var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid server URL"
        case .invalidResponse:
            return "Invalid server response"
        case .httpError(let status, let body):
            return "HTTP \(status): \(body)"
        case .parseError:
            return "Failed to parse server response"
        }
    }
}

/// Health check result from the /health endpoint.
public struct InferenceHealth: Sendable {
    public let activeConnections: Int
    public let uptimeSeconds: Double

    public init(activeConnections: Int, uptimeSeconds: Double) {
        self.activeConnections = activeConnections
        self.uptimeSeconds = uptimeSeconds
    }
}

/// A localhost-only HTTP client for the speak inference server.
///
/// All requests target 127.0.0.1 — no external network egress.
/// Used by the dashboard InferencePaneView for health polling and
/// quick-test console requests.
public struct InferenceClient: Sendable {

    public init() {}

    /// Polls the /health endpoint (no auth required).
    ///
    /// - Parameter port: The server port.
    /// - Returns: Health info with active connections and uptime.
    public func healthCheck(port: UInt16) async throws -> InferenceHealth {
        guard let url = URL(string: "http://127.0.0.1:\(port)/health") else {
            throw InferenceClientError.invalidURL
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 2.0

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw InferenceClientError.invalidResponse
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw InferenceClientError.parseError
        }

        let connections = json["active_connections"] as? Int ?? 0
        let uptime = json["uptime_seconds"] as? Double ?? 0

        return InferenceHealth(activeConnections: connections, uptimeSeconds: uptime)
    }

    /// Sends a chat completion request to the local server.
    ///
    /// - Parameters:
    ///   - prompt: The user prompt text.
    ///   - model: The model ID to use.
    ///   - port: The server port.
    ///   - apiKey: The Bearer token for authentication.
    /// - Returns: The assistant's response content string.
    public func chatCompletion(
        prompt: String,
        model: String,
        port: UInt16,
        apiKey: String
    ) async throws -> String {
        guard let url = URL(string: "http://127.0.0.1:\(port)/v1/chat/completions") else {
            throw InferenceClientError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 30.0
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let body: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "user", "content": prompt]
            ],
            "max_tokens": 512
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw InferenceClientError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            let bodyStr = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw InferenceClientError.httpError(status: httpResponse.statusCode, body: bodyStr)
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw InferenceClientError.parseError
        }

        return content
    }
}
