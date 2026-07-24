// SpeakLLM/InferenceServer/OpenAIResponsesHandler.swift
//
// Handles POST /v1/responses requests in the OpenAI Responses API format.
// Non-streaming only for v1. The Responses API is the newest OpenAI protocol
// used by some agent frameworks (e.g., OpenAI Agents SDK).
//
// Request format: {"model": "speak-default", "instructions": "...", "input": "..."}
// Response format: response object with output array containing message items.
//
// No third-party dependencies. Apple frameworks only (AGENTS.md §2.4).

import Foundation
import Network
import os

/// Handles OpenAI Responses API requests (POST /v1/responses).
///
/// The Responses API is a simpler alternative to Chat Completions used by
/// newer OpenAI tooling. It accepts a flat "input" string and optional
/// "instructions" (system prompt equivalent).
public enum OpenAIResponsesHandler {

    // MARK: - Constants

    /// Logger for request handling.
    private static let logger = Logger(subsystem: "com.speak.app", category: "InferenceServer")

    // MARK: - Request Parsing

    /// Parses the Responses API request body.
    struct ResponsesRequest: Sendable {
        let model: String
        let instructions: String?
        let input: String
    }

    /// Parses the request body into a ResponsesRequest.
    /// The "input" field can be a string or an array of message objects.
    static func parseRequest(body: Data) -> ResponsesRequest? {
        guard let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else {
            return nil
        }

        let model = json["model"] as? String ?? "speak-default"
        let instructions = json["instructions"] as? String

        // Input can be a plain string or an array of messages.
        let input: String
        if let strInput = json["input"] as? String {
            input = strInput
        } else if let arrInput = json["input"] as? [[String: Any]] {
            // Extract content from message array format.
            input = arrInput.compactMap { msg -> String? in
                msg["content"] as? String
            }.joined(separator: "\n")
        } else {
            return nil
        }

        guard !input.isEmpty else { return nil }

        return ResponsesRequest(model: model, instructions: instructions, input: input)
    }

    // MARK: - Request Handling

    /// Handles a responses request and sends the response over the connection.
    static func handle(request: HTTPRequest, connection: NWConnection, router: InferenceRouter) async {
        guard let responsesRequest = parseRequest(body: request.body) else {
            let response = HTTPResponseBuilder.buildErrorResponse(
                status: 400,
                message: "Invalid request body: expected JSON with 'input' field"
            )
            sendAndClose(response, connection: connection)
            return
        }

        logger.debug("Responses API request: model=\(responsesRequest.model, privacy: .public)")

        // Build messages for the router.
        var messages: [RouterMessage] = []
        if let instructions = responsesRequest.instructions, !instructions.isEmpty {
            messages.append(RouterMessage(role: "system", content: instructions))
        }
        messages.append(RouterMessage(role: "user", content: responsesRequest.input))

        do {
            let result = try await router.complete(
                model: responsesRequest.model,
                messages: messages,
                temperature: nil,
                maxTokens: nil
            )

            let responseBody = buildResponsesResult(result: result, model: responsesRequest.model)
            guard let jsonData = try? JSONSerialization.data(withJSONObject: responseBody) else {
                let errorResponse = HTTPResponseBuilder.buildErrorResponse(
                    status: 500, message: "Failed to serialize response")
                sendAndClose(errorResponse, connection: connection)
                return
            }

            let response = HTTPResponseBuilder.buildJSONResponse(status: 200, jsonData: jsonData)
            sendAndClose(response, connection: connection)
        } catch let error as InferenceError {
            let status = errorHTTPStatus(for: error)
            let response = HTTPResponseBuilder.buildErrorResponse(
                status: status, message: errorDescription(for: error))
            sendAndClose(response, connection: connection)
        } catch {
            let response = HTTPResponseBuilder.buildErrorResponse(
                status: 500, message: "Internal server error: \(error.localizedDescription)")
            sendAndClose(response, connection: connection)
        }
    }

    // MARK: - Response Builder

    /// Builds the Responses API response object.
    ///
    /// Shape matches spec §2.4:
    /// ```json
    /// {"id": "resp_speak_...", "object": "response", "output": [...], "usage": {...}}
    /// ```
    private static func buildResponsesResult(result: InferenceResult, model: String) -> [String: Any] {
        [
            "id": "resp_speak_\(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(12))",
            "object": "response",
            "created_at": Int(Date().timeIntervalSince1970),
            "model": model,
            "output": [
                [
                    "id": "msg_out_\(UUID().uuidString.prefix(8))",
                    "type": "message",
                    "status": "completed",
                    "role": "assistant",
                    "content": [
                        ["type": "output_text", "text": result.text],
                    ],
                ] as [String: Any],
            ],
            "usage": [
                "input_tokens": result.promptTokens,
                "output_tokens": result.completionTokens,
                "total_tokens": result.promptTokens + result.completionTokens,
            ],
        ]
    }

    // MARK: - Helpers

    /// Maps InferenceError to appropriate HTTP status codes.
    private static func errorHTTPStatus(for error: InferenceError) -> Int {
        switch error {
        case .unknownModel: return 404
        case .backendUnavailable: return 503
        case .backendError: return 502
        case .generationFailed: return 500
        case .proxyFailed: return 502
        }
    }

    /// Returns a human-readable error description.
    private static func errorDescription(for error: InferenceError) -> String {
        switch error {
        case .unknownModel(let model): return "Model '\(model)' not found"
        case .backendUnavailable(let detail): return "Backend unavailable: \(detail)"
        case .backendError(let detail): return "Backend error: \(detail)"
        case .generationFailed(let detail): return "Generation failed: \(detail)"
        case .proxyFailed(let detail): return "Proxy request failed: \(detail)"
        }
    }

    /// Sends data and closes the connection.
    private static func sendAndClose(_ data: Data, connection: NWConnection) {
        connection.send(content: data, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
}
