// SpeakLLM/StreamingChatClient.swift
//
// SSE streaming client for the local inference server's chat completions
// endpoint. Lives in SpeakLLM (not App/) because the moat audit scans App/
// for networking symbols — localhost HTTP calls are sanctioned in SpeakLLM.
//
// Connects to http://127.0.0.1:<port>/v1/chat/completions with stream=true,
// parses Server-Sent Events (data: <json>\n\n frames), and yields word-level
// text chunks via AsyncThrowingStream. All requests target 127.0.0.1 only.
//
// Also parses the terminal `event: provenance` SSE frame emitted by the
// server, surfacing a ProvenanceReceipt alongside the token stream.

import Foundation

// MARK: - ChatWireMessage

/// Wire-format message for the OpenAI-compatible chat API.
public struct ChatWireMessage: Sendable, Equatable {
    public let role: String
    public let content: String

    public init(role: String, content: String) {
        self.role = role
        self.content = content
    }
}

// MARK: - StreamingChatResult

/// The result of initiating a streaming chat request.
/// Contains both the token stream and a provenance receipt stream.
public struct StreamingChatResult: Sendable {
    /// Word-level text chunks, paced by the cadence engine if enabled.
    public let tokens: AsyncThrowingStream<String, Error>
    /// Yields exactly one ProvenanceReceipt when the stream completes, then finishes.
    public let provenance: AsyncStream<ProvenanceReceipt>
}

// MARK: - StreamingChatClient

/// A localhost-only SSE streaming client for the speak inference server.
///
/// Streams chat completion responses token-by-token (word-level chunks from
/// the server's InferenceRouter). Uses URLSession's async bytes API to
/// consume the text/event-stream response incrementally.
public struct StreamingChatClient: Sendable {

    /// Bundles the request-shaping arguments for `streamChat` so the private
    /// helpers below don't trip SwiftLint's `function_parameter_count`.
    private struct ChatRequestParameters {
        let messages: [ChatWireMessage]
        let model: String
        let port: UInt16
        let apiKey: String
        let temperature: Double?
        let maxTokens: Int?
    }

    public init() {}

    /// Streams a chat completion with provenance metadata.
    ///
    /// - Parameters:
    ///   - messages: The conversation history (system + user + assistant turns).
    ///   - model: The model identifier (e.g., "speak-default", "ollama/qwen3").
    ///   - port: The server port (default 11235).
    ///   - apiKey: Bearer token for authentication.
    ///   - temperature: Optional sampling temperature.
    ///   - maxTokens: Optional max generation tokens.
    ///   - paced: Whether to apply cadence pacing (default true).
    /// - Returns: A StreamingChatResult with token stream and provenance.
    public func streamChat(
        messages: [ChatWireMessage],
        model: String,
        port: UInt16,
        apiKey: String,
        temperature: Double? = nil,
        maxTokens: Int? = nil,
        paced: Bool = true
    ) -> StreamingChatResult {
        let provenanceStream = AsyncStream<ProvenanceReceipt>.makeStream()
        let parameters = ChatRequestParameters(
            messages: messages,
            model: model,
            port: port,
            apiKey: apiKey,
            temperature: temperature,
            maxTokens: maxTokens
        )

        let rawTokenStream = AsyncThrowingStream<String, Error> { continuation in
            let task = Task {
                await runSSERequest(
                    parameters: parameters,
                    continuation: continuation,
                    provenanceContinuation: provenanceStream.continuation
                )
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }

        let tokenStream = paced
            ? pacedTokenStream(from: rawTokenStream)
            : rawTokenStream

        return StreamingChatResult(
            tokens: tokenStream,
            provenance: provenanceStream.stream
        )
    }

    // MARK: - Request orchestration

    /// Builds and performs the SSE request, dispatching to error-body reading
    /// or SSE line consumption, and finishing both streams in every exit path.
    private func runSSERequest(
        parameters: ChatRequestParameters,
        continuation: AsyncThrowingStream<String, Error>.Continuation,
        provenanceContinuation: AsyncStream<ProvenanceReceipt>.Continuation
    ) async {
        do {
            guard let url = URL(string: "http://127.0.0.1:\(parameters.port)/v1/chat/completions") else {
                continuation.finish(throwing: InferenceClientError.invalidURL)
                provenanceContinuation.finish()
                return
            }

            let request = try makeRequest(url: url, parameters: parameters)
            let (bytes, response) = try await URLSession.shared.bytes(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                continuation.finish(throwing: InferenceClientError.invalidResponse)
                provenanceContinuation.finish()
                return
            }

            guard httpResponse.statusCode == 200 else {
                let errorBody = try await readErrorBody(from: bytes)
                continuation.finish(
                    throwing: InferenceClientError.httpError(
                        status: httpResponse.statusCode,
                        body: errorBody
                    )
                )
                provenanceContinuation.finish()
                return
            }

            await consumeSSELines(bytes: bytes, continuation: continuation, provenanceContinuation: provenanceContinuation)
        } catch {
            continuation.finish(throwing: error)
            provenanceContinuation.finish()
        }
    }

    /// Builds the URLRequest (headers, JSON body) for the chat completions call.
    private func makeRequest(url: URL, parameters: ChatRequestParameters) throws -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 120.0
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(parameters.apiKey)", forHTTPHeaderField: "Authorization")

        var body: [String: Any] = [
            "model": parameters.model,
            "messages": parameters.messages.map { ["role": $0.role, "content": $0.content] },
            "stream": true
        ]
        if let temperature = parameters.temperature {
            body["temperature"] = temperature
        }
        if let maxTokens = parameters.maxTokens {
            body["max_tokens"] = maxTokens
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    /// Drains a non-200 response body into a single string for error reporting.
    private func readErrorBody(from bytes: URLSession.AsyncBytes) async throws -> String {
        var errorBody = ""
        for try await line in bytes.lines {
            errorBody += line
        }
        return errorBody
    }

    /// The SSE line loop: cancellation, `event:`/`data:` framing, `[DONE]` handling.
    private func consumeSSELines(
        bytes: URLSession.AsyncBytes,
        continuation: AsyncThrowingStream<String, Error>.Continuation,
        provenanceContinuation: AsyncStream<ProvenanceReceipt>.Continuation
    ) async {
        do {
            var currentEventType: String?

            for try await line in bytes.lines {
                if Task.isCancelled {
                    continuation.finish()
                    provenanceContinuation.finish()
                    return
                }

                if line.hasPrefix("event: ") {
                    currentEventType = String(line.dropFirst(7))
                    continue
                }

                guard line.hasPrefix("data: ") else { continue }

                let payload = String(line.dropFirst(6))

                if payload == "[DONE]" {
                    continuation.finish()
                    provenanceContinuation.finish()
                    return
                }

                if currentEventType == "provenance" {
                    currentEventType = nil
                    handleProvenancePayload(payload, provenanceContinuation: provenanceContinuation)
                    continue
                }

                currentEventType = nil

                if let content = extractDeltaContent(fromPayload: payload) {
                    continuation.yield(content)
                }
            }

            continuation.finish()
            provenanceContinuation.finish()
        } catch {
            continuation.finish(throwing: error)
            provenanceContinuation.finish()
        }
    }

    /// Parses a `event: provenance` SSE frame's payload and yields the receipt.
    private func handleProvenancePayload(
        _ payload: String,
        provenanceContinuation: AsyncStream<ProvenanceReceipt>.Continuation
    ) {
        guard let data = payload.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let receipt = ProvenanceReceipt.from(json: json) else {
            return
        }
        provenanceContinuation.yield(receipt)
    }

    /// Parses a token delta payload, returning the content string if present.
    private func extractDeltaContent(fromPayload payload: String) -> String? {
        guard let data = payload.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let delta = firstChoice["delta"] as? [String: Any],
              let content = delta["content"] as? String,
              !content.isEmpty else {
            return nil
        }
        return content
    }

    /// Wraps the raw token stream with StreamingCadenceEngine pacing.
    private func pacedTokenStream(from rawTokenStream: AsyncThrowingStream<String, Error>) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                let cadence = StreamingCadenceEngine()
                let pacedStream = await cadence.pace(rawTokenStream)
                do {
                    for try await chunk in pacedStream {
                        if Task.isCancelled {
                            continuation.finish()
                            return
                        }
                        continuation.yield(chunk)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
