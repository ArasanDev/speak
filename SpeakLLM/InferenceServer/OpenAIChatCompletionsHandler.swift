// SpeakLLM/InferenceServer/OpenAIChatCompletionsHandler.swift
//
// Handles POST /v1/chat/completions requests in the OpenAI Chat Completions format.
// Supports both non-streaming (full JSON response) and streaming (SSE chunks).
// Exact JSON shapes match the OpenAI API specification for SDK compatibility.
//
// No third-party dependencies. Apple frameworks only (AGENTS.md §2.4).

import Foundation
import Network
import os

/// Handles OpenAI Chat Completions API requests (POST /v1/chat/completions).
///
/// Request format:
/// ```json
/// {"model": "speak-default", "messages": [...], "stream": false, "temperature": 0.7}
/// ```
///
/// Non-streaming response: chat.completion object.
/// Streaming response: SSE with chat.completion.chunk objects + [DONE].
public enum OpenAIChatCompletionsHandler {

    // MARK: - Constants

    /// Logger for request handling.
    private static let logger = Logger(subsystem: "com.speak.app", category: "InferenceServer")

    // MARK: - Request Parsing

    /// Parses the OpenAI chat completions request body.
    struct ChatRequest: Sendable {
        let model: String
        let messages: [RouterMessage]
        let stream: Bool
        let temperature: Double?
        let maxTokens: Int?
    }

    /// Parses the request body into a ChatRequest.
    /// Returns nil if the body is malformed.
    static func parseRequest(body: Data) -> ChatRequest? {
        guard let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else {
            return nil
        }

        let model = json["model"] as? String ?? "speak-default"
        let stream = json["stream"] as? Bool ?? false
        let temperature = json["temperature"] as? Double
        let maxTokens = json["max_tokens"] as? Int

        // Parse messages array.
        guard let messagesArray = json["messages"] as? [[String: Any]] else {
            return nil
        }

        let messages = messagesArray.compactMap { msg -> RouterMessage? in
            guard let role = msg["role"] as? String,
                  let content = msg["content"] as? String else {
                return nil
            }
            return RouterMessage(role: role, content: content)
        }

        guard !messages.isEmpty else { return nil }

        return ChatRequest(
            model: model,
            messages: messages,
            stream: stream,
            temperature: temperature,
            maxTokens: maxTokens
        )
    }

    // MARK: - Request Handling

    /// Handles a chat completions request and sends the response over the connection.
    ///
    /// - Parameters:
    ///   - request: The parsed HTTP request.
    ///   - connection: The NWConnection to send the response on.
    ///   - router: The inference router for backend dispatch.
    static func handle(request: HTTPRequest, connection: NWConnection, router: InferenceRouter) async {
        guard let chatRequest = parseRequest(body: request.body) else {
            let response = HTTPResponseBuilder.buildErrorResponse(
                status: 400,
                message: "Invalid request body: expected JSON with 'messages' array"
            )
            sendAndClose(response, connection: connection)
            return
        }

        logger.debug("Chat completions request: model=\(chatRequest.model, privacy: .public), stream=\(chatRequest.stream)")

        if chatRequest.stream {
            await handleStreaming(chatRequest: chatRequest, connection: connection, router: router)
        } else {
            await handleNonStreaming(chatRequest: chatRequest, connection: connection, router: router)
        }
    }

    // MARK: - Non-Streaming Response

    private static func handleNonStreaming(
        chatRequest: ChatRequest,
        connection: NWConnection,
        router: InferenceRouter
    ) async {
        do {
            let result = try await router.complete(
                model: chatRequest.model,
                messages: chatRequest.messages,
                temperature: chatRequest.temperature,
                maxTokens: chatRequest.maxTokens
            )

            let responseBody = buildCompletionResponse(result: result, model: chatRequest.model)
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

    // MARK: - Streaming Response

    private static func handleStreaming(
        chatRequest: ChatRequest,
        connection: NWConnection,
        router: InferenceRouter
    ) async {
        let completionId = "chatcmpl-speak-\(UUID().uuidString.prefix(12))"
        let created = Int(Date().timeIntervalSince1970)

        do {
            let chunks = try await router.stream(
                model: chatRequest.model,
                messages: chatRequest.messages,
                temperature: chatRequest.temperature,
                maxTokens: chatRequest.maxTokens
            )

            // Send SSE headers.
            let headers = HTTPResponseBuilder.buildSSEHeaders()
            await sendData(headers, connection: connection)

            // Send initial chunk with role.
            let initialChunk = buildStreamChunk(
                id: completionId, created: created, model: chatRequest.model,
                deltaRole: "assistant", deltaContent: "", finishReason: nil
            )
            if let initialData = try? JSONSerialization.data(withJSONObject: initialChunk),
               let initialStr = String(data: initialData, encoding: .utf8) {
                await sendData(HTTPResponseBuilder.buildSSEChunk(data: initialStr), connection: connection)
            }

            // Send content chunks.
            for (index, chunk) in chunks.enumerated() {
                let isLast = index == chunks.count - 1
                let streamChunk = buildStreamChunk(
                    id: completionId, created: created, model: chatRequest.model,
                    deltaRole: nil, deltaContent: chunk,
                    finishReason: isLast ? "stop" : nil
                )
                if let chunkData = try? JSONSerialization.data(withJSONObject: streamChunk),
                   let chunkStr = String(data: chunkData, encoding: .utf8) {
                    await sendData(HTTPResponseBuilder.buildSSEChunk(data: chunkStr), connection: connection)
                }
            }

            // Send [DONE] terminator.
            await sendData(HTTPResponseBuilder.buildSSEDone(), connection: connection)

            // Close connection after stream completes.
            connection.cancel()
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

    // MARK: - Response Builders

    /// Builds the non-streaming chat.completion response object.
    private static func buildCompletionResponse(result: InferenceResult, model: String) -> [String: Any] {
        [
            "id": "chatcmpl-speak-\(UUID().uuidString.prefix(12))",
            "object": "chat.completion",
            "created": Int(Date().timeIntervalSince1970),
            "model": model,
            "choices": [
                [
                    "index": 0,
                    "message": [
                        "role": "assistant",
                        "content": result.text,
                    ],
                    "finish_reason": "stop",
                ] as [String: Any],
            ],
            "usage": [
                "prompt_tokens": result.promptTokens,
                "completion_tokens": result.completionTokens,
                "total_tokens": result.promptTokens + result.completionTokens,
            ],
        ]
    }

    /// Builds a streaming chat.completion.chunk object.
    private static func buildStreamChunk(
        id: String,
        created: Int,
        model: String,
        deltaRole: String?,
        deltaContent: String?,
        finishReason: String?
    ) -> [String: Any] {
        var delta: [String: Any] = [:]
        if let role = deltaRole {
            delta["role"] = role
        }
        if let content = deltaContent {
            delta["content"] = content
        }

        return [
            "id": id,
            "object": "chat.completion.chunk",
            "created": created,
            "model": model,
            "choices": [
                [
                    "index": 0,
                    "delta": delta,
                    "finish_reason": finishReason as Any,
                ] as [String: Any],
            ],
        ]
    }

    // MARK: - Helpers

    /// Maps InferenceError to appropriate HTTP status codes.
    private static func errorHTTPStatus(for error: InferenceError) -> Int {
        switch error {
        case .unknownModel:
            return 404
        case .backendUnavailable:
            return 503
        case .backendError:
            return 502
        case .generationFailed:
            return 500
        case .proxyFailed:
            return 502
        }
    }

    /// Returns a human-readable error description.
    private static func errorDescription(for error: InferenceError) -> String {
        switch error {
        case .unknownModel(let model):
            return "Model '\(model)' not found"
        case .backendUnavailable(let detail):
            return "Backend unavailable: \(detail)"
        case .backendError(let detail):
            return "Backend error: \(detail)"
        case .generationFailed(let detail):
            return "Generation failed: \(detail)"
        case .proxyFailed(let detail):
            return "Proxy request failed: \(detail)"
        }
    }

    /// Sends data and closes the connection.
    private static func sendAndClose(_ data: Data, connection: NWConnection) {
        connection.send(content: data, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    /// Sends data without closing the connection (for streaming).
    private static func sendData(_ data: Data, connection: NWConnection) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            connection.send(content: data, completion: .contentProcessed { _ in
                continuation.resume()
            })
        }
    }
}
