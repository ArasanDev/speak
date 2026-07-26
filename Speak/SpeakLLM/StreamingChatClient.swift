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

        let rawTokenStream = AsyncThrowingStream<String, Error> { continuation in
            let task = Task {
                do {
                    guard let url = URL(string: "http://127.0.0.1:\(port)/v1/chat/completions") else {
                        continuation.finish(throwing: InferenceClientError.invalidURL)
                        provenanceStream.continuation.finish()
                        return
                    }

                    var request = URLRequest(url: url)
                    request.httpMethod = "POST"
                    request.timeoutInterval = 120.0
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

                    var body: [String: Any] = [
                        "model": model,
                        "messages": messages.map { ["role": $0.role, "content": $0.content] },
                        "stream": true
                    ]
                    if let temperature {
                        body["temperature"] = temperature
                    }
                    if let maxTokens {
                        body["max_tokens"] = maxTokens
                    }
                    request.httpBody = try JSONSerialization.data(withJSONObject: body)

                    let (bytes, response) = try await URLSession.shared.bytes(for: request)

                    guard let httpResponse = response as? HTTPURLResponse else {
                        continuation.finish(throwing: InferenceClientError.invalidResponse)
                        provenanceStream.continuation.finish()
                        return
                    }

                    guard httpResponse.statusCode == 200 else {
                        var errorBody = ""
                        for try await line in bytes.lines {
                            errorBody += line
                        }
                        continuation.finish(
                            throwing: InferenceClientError.httpError(
                                status: httpResponse.statusCode,
                                body: errorBody
                            )
                        )
                        provenanceStream.continuation.finish()
                        return
                    }

                    var currentEventType: String?

                    for try await line in bytes.lines {
                        if Task.isCancelled {
                            continuation.finish()
                            provenanceStream.continuation.finish()
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
                            provenanceStream.continuation.finish()
                            return
                        }

                        if currentEventType == "provenance" {
                            currentEventType = nil
                            if let data = payload.data(using: .utf8),
                               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                               let receipt = ProvenanceReceipt.from(json: json) {
                                provenanceStream.continuation.yield(receipt)
                            }
                            continue
                        }

                        currentEventType = nil

                        guard let data = payload.data(using: .utf8),
                              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                              let choices = json["choices"] as? [[String: Any]],
                              let firstChoice = choices.first,
                              let delta = firstChoice["delta"] as? [String: Any],
                              let content = delta["content"] as? String,
                              !content.isEmpty else {
                            continue
                        }

                        continuation.yield(content)
                    }

                    continuation.finish()
                    provenanceStream.continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                    provenanceStream.continuation.finish()
                }
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }

        let tokenStream: AsyncThrowingStream<String, Error>
        if paced {
            let cadence = StreamingCadenceEngine()
            tokenStream = AsyncThrowingStream { continuation in
                let task = Task {
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
        } else {
            tokenStream = rawTokenStream
        }

        return StreamingChatResult(
            tokens: tokenStream,
            provenance: provenanceStream.stream
        )
    }
}
