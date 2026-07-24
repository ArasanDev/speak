// SpeakLLM/InferenceServer/AnthropicMessagesHandler.swift
//
// Handles POST /v1/messages requests in the Anthropic Messages API format.
// Supports both non-streaming (full JSON response) and streaming (SSE event frames).
// Exact JSON shapes match the Anthropic API specification for SDK compatibility.
//
// Streaming uses named SSE events: message_start, content_block_start,
// content_block_delta, content_block_stop, message_delta, message_stop.
//
// No third-party dependencies. Apple frameworks only (AGENTS.md §2.4).

import Foundation
import Network
import os

/// Handles Anthropic Messages API requests (POST /v1/messages).
///
/// Request format:
/// ```json
/// {"model": "speak-default", "max_tokens": 1024, "system": "...", "messages": [...]}
/// ```
///
/// Non-streaming response: message object with content array.
/// Streaming response: SSE with named event frames.
public enum AnthropicMessagesHandler {

    // MARK: - Constants

    /// Logger for request handling.
    private static let logger = Logger(subsystem: "com.speak.app", category: "InferenceServer")

    // MARK: - Request Parsing

    /// Parses the Anthropic messages request body.
    struct MessagesRequest: Sendable {
        let model: String
        let maxTokens: Int
        let system: String?
        let messages: [RouterMessage]
        let stream: Bool
        let temperature: Double?
    }

    /// Parses the request body into a MessagesRequest.
    static func parseRequest(body: Data) -> MessagesRequest? {
        guard let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else {
            return nil
        }

        let model = json["model"] as? String ?? "speak-default"
        let maxTokens = json["max_tokens"] as? Int ?? 1024
        let system = json["system"] as? String
        let stream = json["stream"] as? Bool ?? false
        let temperature = json["temperature"] as? Double

        // Parse messages array.
        guard let messagesArray = json["messages"] as? [[String: Any]] else {
            return nil
        }

        let messages = messagesArray.compactMap { msg -> RouterMessage? in
            guard let role = msg["role"] as? String else { return nil }
            // Anthropic messages can have string content or array content.
            let content: String
            if let strContent = msg["content"] as? String {
                content = strContent
            } else if let arrContent = msg["content"] as? [[String: Any]] {
                // Extract text from content blocks.
                content = arrContent.compactMap { block -> String? in
                    guard block["type"] as? String == "text" else { return nil }
                    return block["text"] as? String
                }.joined(separator: "\n")
            } else {
                return nil
            }
            return RouterMessage(role: role, content: content)
        }

        guard !messages.isEmpty else { return nil }

        return MessagesRequest(
            model: model,
            maxTokens: maxTokens,
            system: system,
            messages: messages,
            stream: stream,
            temperature: temperature
        )
    }

    // MARK: - Request Handling

    /// Handles a messages request and sends the response over the connection.
    static func handle(request: HTTPRequest, connection: NWConnection, router: InferenceRouter) async {
        guard let messagesRequest = parseRequest(body: request.body) else {
            let response = HTTPResponseBuilder.buildErrorResponse(
                status: 400,
                message: "Invalid request body: expected JSON with 'messages' array and 'max_tokens'"
            )
            sendAndClose(response, connection: connection)
            return
        }

        logger.debug("Anthropic messages request: model=\(messagesRequest.model, privacy: .public), stream=\(messagesRequest.stream)")

        // Prepend system message if provided.
        var allMessages = messagesRequest.messages
        if let system = messagesRequest.system, !system.isEmpty {
            allMessages.insert(RouterMessage(role: "system", content: system), at: 0)
        }

        if messagesRequest.stream {
            await handleStreaming(messagesRequest: messagesRequest, allMessages: allMessages,
                                  connection: connection, router: router)
        } else {
            await handleNonStreaming(messagesRequest: messagesRequest, allMessages: allMessages,
                                     connection: connection, router: router)
        }
    }

    // MARK: - Non-Streaming Response

    private static func handleNonStreaming(
        messagesRequest: MessagesRequest,
        allMessages: [RouterMessage],
        connection: NWConnection,
        router: InferenceRouter
    ) async {
        do {
            let result = try await router.complete(
                model: messagesRequest.model,
                messages: allMessages,
                temperature: messagesRequest.temperature,
                maxTokens: messagesRequest.maxTokens
            )

            let responseBody = buildMessageResponse(result: result, model: messagesRequest.model)
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
        messagesRequest: MessagesRequest,
        allMessages: [RouterMessage],
        connection: NWConnection,
        router: InferenceRouter
    ) async {
        let messageId = "msg_speak_\(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(12))"

        do {
            let chunks = try await router.stream(
                model: messagesRequest.model,
                messages: allMessages,
                temperature: messagesRequest.temperature,
                maxTokens: messagesRequest.maxTokens
            )

            // Send SSE headers.
            let headers = HTTPResponseBuilder.buildSSEHeaders()
            await sendData(headers, connection: connection)

            let inputTokens = allMessages.map(\.content).joined().count / 4

            // event: message_start
            let messageStart = buildMessageStartEvent(
                messageId: messageId, model: messagesRequest.model, inputTokens: inputTokens)
            await sendSSEEvent("message_start", messageStart, connection: connection)

            // event: content_block_start
            let blockStart: [String: Any] = [
                "type": "content_block_start",
                "index": 0,
                "content_block": ["type": "text", "text": ""],
            ]
            await sendSSEEvent("content_block_start", blockStart, connection: connection)

            // event: content_block_delta (one per chunk)
            for chunk in chunks {
                let delta: [String: Any] = [
                    "type": "content_block_delta",
                    "index": 0,
                    "delta": ["type": "text_delta", "text": chunk],
                ]
                await sendSSEEvent("content_block_delta", delta, connection: connection)
            }

            // event: content_block_stop
            let blockStop: [String: Any] = [
                "type": "content_block_stop",
                "index": 0,
            ]
            await sendSSEEvent("content_block_stop", blockStop, connection: connection)

            // event: message_delta
            let outputTokens = chunks.joined().count / 4
            let messageDelta: [String: Any] = [
                "type": "message_delta",
                "delta": ["stop_reason": "end_turn", "stop_sequence": NSNull()],
                "usage": ["output_tokens": outputTokens],
            ]
            await sendSSEEvent("message_delta", messageDelta, connection: connection)

            // event: message_stop
            let messageStop: [String: Any] = ["type": "message_stop"]
            await sendSSEEvent("message_stop", messageStop, connection: connection)

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

    /// Builds the non-streaming Anthropic message response object.
    private static func buildMessageResponse(result: InferenceResult, model: String) -> [String: Any] {
        [
            "id": "msg_speak_\(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(12))",
            "type": "message",
            "role": "assistant",
            "model": model,
            "content": [
                ["type": "text", "text": result.text],
            ],
            "stop_reason": "end_turn",
            "stop_sequence": NSNull(),
            "usage": [
                "input_tokens": result.promptTokens,
                "output_tokens": result.completionTokens,
            ],
        ]
    }

    /// Builds the message_start SSE event payload.
    private static func buildMessageStartEvent(
        messageId: String, model: String, inputTokens: Int
    ) -> [String: Any] {
        [
            "type": "message_start",
            "message": [
                "id": messageId,
                "type": "message",
                "role": "assistant",
                "content": [] as [Any],
                "model": model,
                "stop_reason": NSNull(),
                "usage": ["input_tokens": inputTokens, "output_tokens": 0],
            ] as [String: Any],
        ]
    }

    // MARK: - Helpers

    /// Sends a named SSE event with a JSON payload.
    private static func sendSSEEvent(_ event: String, _ payload: [String: Any], connection: NWConnection) async {
        guard let jsonData = try? JSONSerialization.data(withJSONObject: payload),
              let jsonStr = String(data: jsonData, encoding: .utf8) else {
            return
        }
        let eventData = HTTPResponseBuilder.buildSSEEvent(event: event, data: jsonStr)
        await sendData(eventData, connection: connection)
    }

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

    /// Sends data without closing the connection (for streaming).
    private static func sendData(_ data: Data, connection: NWConnection) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            connection.send(content: data, completion: .contentProcessed { _ in
                continuation.resume()
            })
        }
    }
}
