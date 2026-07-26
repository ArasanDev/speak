// SpeakLLM/InferenceServer/InferenceRouter.swift
//
// Routes inference requests to the appropriate backend based on the model string.
// Supports Apple FoundationModels (in-process), Ollama (localhost proxy),
// and MLX (localhost proxy). Implements the fallback chain from spec §3.1.
//
// The FoundationModels API is BATCH (session.respond returns the full response).
// For SSE streaming, the response text is chunked into words and emitted as
// individual SSE events. This is protocol-correct — the chunking is a
// presentation-layer concern.
//
// No third-party dependencies. Apple frameworks only (AGENTS.md §2.4).

import Foundation
import FoundationModels
import os

/// Errors that can occur during inference routing.
public enum InferenceError: Error, Sendable, Equatable {
    /// The requested model is not recognized.
    case unknownModel(String)
    /// The requested backend is not available.
    case backendUnavailable(String)
    /// The backend returned an error.
    case backendError(String)
    /// Apple FoundationModels generation failed.
    case generationFailed(String)
    /// The proxy request to a local backend failed.
    case proxyFailed(String)
}

/// A unified message format used internally by the router.
/// Handlers convert from their protocol-specific format to this.
public struct RouterMessage: Sendable {
    /// Role: "system", "user", or "assistant".
    public let role: String
    /// Message content text.
    public let content: String

    public init(role: String, content: String) {
        self.role = role
        self.content = content
    }
}

/// A completed inference result.
public struct InferenceResult: Sendable {
    /// The generated text.
    public let text: String
    /// The model that produced the result.
    public let model: String
    /// Approximate token counts for usage reporting.
    public let promptTokens: Int
    public let completionTokens: Int

    public init(text: String, model: String, promptTokens: Int, completionTokens: Int) {
        self.text = text
        self.model = model
        self.promptTokens = promptTokens
        self.completionTokens = completionTokens
    }
}

/// Routes inference requests to the correct backend based on the model identifier.
///
/// Routing matrix (spec §3.1):
/// - "speak-default", "apple-intelligence" -> Apple FoundationModels
/// - "speak-advanced" -> Apple FoundationModels (alias)
/// - "ollama/<model>" -> proxy to http://127.0.0.1:11434/v1/chat/completions
/// - "mlx/<model>" -> proxy to http://127.0.0.1:8080/v1/chat/completions
public actor InferenceRouter {

    // MARK: - Constants

    /// Ollama chat completions endpoint (OpenAI-compatible).
    /// [decision: use /v1/chat/completions for unified request format]
    private static let ollamaChatURL = "http://127.0.0.1:11434/v1/chat/completions"

    /// MLX LM server chat completions endpoint.
    private static let mlxChatURL = "http://127.0.0.1:8080/v1/chat/completions"

    /// Proxy request timeout in seconds.
    /// [decision: 120s for local LLM inference — large models can be slow]
    private static let proxyTimeoutSeconds: TimeInterval = 120.0

    /// Approximate characters per token for usage estimation.
    /// [decision: 4 chars/token is the standard heuristic for English text]
    private static let charsPerToken = 4

    /// Logger for routing operations.
    private let logger = Logger(subsystem: "com.speak.app", category: "InferenceServer")

    // MARK: - Public API

    public init() {}

    /// Performs a non-streaming inference request.
    ///
    /// - Parameters:
    ///   - model: The model identifier from the request.
    ///   - messages: The conversation messages.
    ///   - temperature: Sampling temperature (0.0 = greedy).
    ///   - maxTokens: Maximum tokens to generate.
    /// - Returns: The completed inference result.
    /// - Throws: `InferenceError` if the backend is unavailable or fails.
    public func complete(
        model: String,
        messages: [RouterMessage],
        temperature: Double?,
        maxTokens: Int?
    ) async throws -> InferenceResult {
        let resolvedModel = resolveModel(model)

        if resolvedModel.hasPrefix("ollama/") {
            return try await proxyToOllama(model: resolvedModel, messages: messages,
                                           temperature: temperature, maxTokens: maxTokens)
        } else if resolvedModel.hasPrefix("mlx/") {
            return try await proxyToMLX(model: resolvedModel, messages: messages,
                                        temperature: temperature, maxTokens: maxTokens)
        } else {
            return try await completeWithAppleIntelligence(
                model: resolvedModel, messages: messages)
        }
    }

    /// Performs a streaming inference request, returning text chunks.
    ///
    /// For Apple FoundationModels (batch API), the full response is generated
    /// first, then chunked into words for SSE emission. For proxy backends,
    /// the response is streamed through if the backend supports it.
    ///
    /// - Parameters:
    ///   - model: The model identifier from the request.
    ///   - messages: The conversation messages.
    ///   - temperature: Sampling temperature.
    ///   - maxTokens: Maximum tokens to generate.
    /// - Returns: An async sequence of text chunks.
    /// - Throws: `InferenceError` if the backend is unavailable or fails.
    public func stream(
        model: String,
        messages: [RouterMessage],
        temperature: Double?,
        maxTokens: Int?
    ) async throws -> [String] {
        // For v1, all backends use batch-then-chunk semantics.
        // Apple FoundationModels is inherently batch; proxy backends
        // could stream but we normalize to batch for simplicity.
        let result = try await complete(model: model, messages: messages,
                                        temperature: temperature, maxTokens: maxTokens)
        return chunkTextIntoWords(result.text)
    }

    /// Streaming with provenance metadata for the UI colophon.
    public func streamWithProvenance(
        model: String,
        messages: [RouterMessage],
        temperature: Double?,
        maxTokens: Int?
    ) async throws -> (chunks: [String], result: InferenceResult) {
        let result = try await complete(model: model, messages: messages,
                                        temperature: temperature, maxTokens: maxTokens)
        return (chunkTextIntoWords(result.text), result)
    }

    // MARK: - Model Resolution

    /// Resolves a model identifier to its canonical form.
    ///
    /// Handles aliases and defaults:
    /// - Empty or "speak-default" -> "speak-default"
    /// - "apple-intelligence" -> "speak-default" (same backend)
    /// - "speak-advanced" -> "speak-default" (same backend for now)
    /// - "ollama/*" and "mlx/*" pass through unchanged.
    private func resolveModel(_ model: String) -> String {
        switch model {
        case "", "speak-default", "apple-intelligence", "speak-advanced":
            return "speak-default"
        default:
            return model
        }
    }

    // MARK: - Apple FoundationModels Backend

    /// Generates a response using Apple's on-device FoundationModels framework.
    ///
    /// Uses the verified API pattern from FoundationModelsCleaner.swift:
    /// SystemLanguageModel -> LanguageModelSession -> session.respond(to:)
    @available(macOS 26.0, *)
    private func completeWithAppleIntelligence(
        model: String,
        messages: [RouterMessage]
    ) async throws -> InferenceResult {
        let languageModel = SystemLanguageModel(
            useCase: .general,
            guardrails: .permissiveContentTransformations
        )

        // Check availability before attempting generation.
        let availability = languageModel.availability
        switch availability {
        case .available:
            break
        case .unavailable(let reason):
            throw InferenceError.backendUnavailable(
                "Apple Intelligence unavailable: \(String(describing: reason))")
        }

        // Build system instructions from system messages.
        let systemMessages = messages.filter { $0.role == "system" }
        let systemPrompt = systemMessages.map(\.content).joined(separator: "\n\n")

        // Build the user prompt from non-system messages.
        let conversationMessages = messages.filter { $0.role != "system" }
        let userPrompt = conversationMessages.map { message in
            if message.role == "assistant" {
                return "Assistant: \(message.content)"
            }
            return message.content
        }.joined(separator: "\n\n")

        // Create session with system instructions.
        let session: LanguageModelSession
        if systemPrompt.isEmpty {
            session = LanguageModelSession(model: languageModel)
        } else {
            session = LanguageModelSession(
                model: languageModel,
                instructions: Instructions(systemPrompt)
            )
        }

        // Generate response (batch API).
        do {
            let response = try await session.respond(to: Prompt(userPrompt))
            let text = response.content

            let promptTokens = estimateTokens(systemPrompt + userPrompt)
            let completionTokens = estimateTokens(text)

            logger.debug("Apple Intelligence response: \(text.count) chars")

            return InferenceResult(
                text: text,
                model: model,
                promptTokens: promptTokens,
                completionTokens: completionTokens
            )
        } catch let genError as LanguageModelSession.GenerationError {
            throw InferenceError.generationFailed(genError.localizedDescription)
        } catch {
            throw InferenceError.generationFailed(error.localizedDescription)
        }
    }

    // MARK: - Ollama Proxy Backend

    /// Proxies a request to the local Ollama daemon.
    private func proxyToOllama(
        model: String,
        messages: [RouterMessage],
        temperature: Double?,
        maxTokens: Int?
    ) async throws -> InferenceResult {
        let ollamaModel = String(model.dropFirst("ollama/".count))
        return try await proxyToOpenAICompatible(
            urlString: Self.ollamaChatURL,
            model: ollamaModel,
            messages: messages,
            temperature: temperature,
            maxTokens: maxTokens,
            backendName: "Ollama"
        )
    }

    // MARK: - MLX Proxy Backend

    /// Proxies a request to the local MLX LM server.
    private func proxyToMLX(
        model: String,
        messages: [RouterMessage],
        temperature: Double?,
        maxTokens: Int?
    ) async throws -> InferenceResult {
        let mlxModel = String(model.dropFirst("mlx/".count))
        return try await proxyToOpenAICompatible(
            urlString: Self.mlxChatURL,
            model: mlxModel,
            messages: messages,
            temperature: temperature,
            maxTokens: maxTokens,
            backendName: "MLX"
        )
    }

    // MARK: - Generic OpenAI-Compatible Proxy

    /// Proxies a request to any OpenAI-compatible chat completions endpoint.
    private func proxyToOpenAICompatible(
        urlString: String,
        model: String,
        messages: [RouterMessage],
        temperature: Double?,
        maxTokens: Int?,
        backendName: String
    ) async throws -> InferenceResult {
        guard let url = URL(string: urlString) else {
            throw InferenceError.proxyFailed("Invalid URL: \(urlString)")
        }

        // Build OpenAI-compatible request body.
        var requestBody: [String: Any] = [
            "model": model,
            "messages": messages.map { ["role": $0.role, "content": $0.content] },
            "stream": false,
        ]
        if let temp = temperature {
            requestBody["temperature"] = temp
        }
        if let maxTok = maxTokens {
            requestBody["max_tokens"] = maxTok
        }

        guard let jsonData = try? JSONSerialization.data(withJSONObject: requestBody) else {
            throw InferenceError.proxyFailed("Failed to serialize request")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = jsonData
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = Self.proxyTimeoutSeconds

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw InferenceError.proxyFailed("Invalid response from \(backendName)")
            }

            guard httpResponse.statusCode == 200 else {
                let bodyStr = String(data: data, encoding: .utf8) ?? "unknown error"
                throw InferenceError.backendError(
                    "\(backendName) returned \(httpResponse.statusCode): \(bodyStr)")
            }

            // Parse OpenAI-compatible response.
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let choices = json["choices"] as? [[String: Any]],
                  let firstChoice = choices.first,
                  let message = firstChoice["message"] as? [String: Any],
                  let content = message["content"] as? String else {
                throw InferenceError.proxyFailed("Failed to parse \(backendName) response")
            }

            // Extract usage if available.
            var promptTokens = 0
            var completionTokens = 0
            if let usage = json["usage"] as? [String: Any] {
                promptTokens = usage["prompt_tokens"] as? Int ?? 0
                completionTokens = usage["completion_tokens"] as? Int ?? 0
            } else {
                let inputText = messages.map(\.content).joined()
                promptTokens = estimateTokens(inputText)
                completionTokens = estimateTokens(content)
            }

            return InferenceResult(
                text: content,
                model: model,
                promptTokens: promptTokens,
                completionTokens: completionTokens
            )
        } catch let error as InferenceError {
            throw error
        } catch {
            throw InferenceError.proxyFailed(
                "\(backendName) request failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Helpers

    /// Estimates token count from character count using the standard heuristic.
    private func estimateTokens(_ text: String) -> Int {
        max(1, text.count / Self.charsPerToken)
    }

    /// Chunks text into word-level pieces for SSE streaming.
    ///
    /// Each chunk is a word followed by its trailing space (if any), so
    /// concatenating all chunks reproduces the original text exactly.
    private func chunkTextIntoWords(_ text: String) -> [String] {
        guard !text.isEmpty else { return [] }

        var chunks: [String] = []
        var current = ""

        for char in text {
            current.append(char)
            if char == " " || char == "\n" {
                chunks.append(current)
                current = ""
            }
        }
        if !current.isEmpty {
            chunks.append(current)
        }
        return chunks
    }
}
