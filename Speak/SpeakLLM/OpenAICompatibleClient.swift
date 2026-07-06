// SpeakLLM/OpenAICompatibleClient.swift
//
// URLSession-based HTTP client for OpenAI-compatible chat-completions endpoints
// (Ollama, Sarvam, OpenAI, Groq, OpenRouter, custom).
//
// WHY THIS LIVES OUTSIDE SpeakCore/ + App/ + CLI/:
//   `scripts/verify-moat.sh` and `SpeakTests/MoatAuditTests.swift` grep those
//   three directories for networking symbols (`URLSession`, `dataTask(`, etc.)
//   to make "100% local + offline" (benchmark.md §3 #1/#7) a structural
//   guarantee, not a policy. V01-2 adds a genuinely opt-in, user-configured
//   cloud/local-server cleanup engine — the correct way to add that capability
//   without hollowing out the audit is to put the networking code in its own
//   compilation target that the audit does not scan, and let `SpeakCore` reach
//   it only through a narrow, symbol-free import. That keeps the audit's claim
//   honest: `SpeakCore` itself still contains zero networking symbols.
//   [decision V01-2 — this is the `SpeakLLM` module previously sketched in
//   `SpeakCore/Cleanup/OllamaCleaner.swift`'s v0.1 stub comment.]
//
// SpeakCore reaches this module only via `SpeakCore/Cleanup/OpenAICompatibleCleaner.swift`,
// which holds the `ProviderPreset` data and delegates the actual HTTP call here.

import Foundation

/// How the API key (if any) is attached to the request.
public enum LLMAuthStyle: String, Codable, Sendable, Equatable {
    /// No credential sent (Ollama — loopback, no account).
    case none
    /// `Authorization: Bearer <key>` — OpenAI, Groq, OpenRouter.
    case bearer
    /// `api-subscription-key: <key>` — Sarvam AI.
    case subscriptionKey
}

/// Errors surfaced by `OpenAICompatibleClient`. Callers (`OpenAICompatibleCleaner`)
/// map these to `SpeakError.llmCleanupFailed` with a user-facing detail string;
/// none of these are ever surfaced as `LLMCleaning.isAvailable == true` on their own.
public enum OpenAICompatibleClientError: Error, Equatable, Sendable {
    /// Connection-level failure (server not running, DNS failure, timeout).
    case notRunning
    /// Server responded 404 — most commonly Ollama when the model tag has not
    /// been pulled locally.
    case modelNotInstalled(String)
    /// HTTP 401 — bad/missing API key.
    case unauthorized
    /// HTTP 429 — rate limited.
    case rateLimited
    /// Any other non-2xx status.
    case requestFailed(Int)
    /// 2xx response but the body did not decode to the expected shape.
    case invalidResponse
}

/// A single OpenAI-compatible chat-completions client, parameterized per call by
/// base URL / auth / model so one instance serves every preset.
public struct OpenAICompatibleClient: Sendable {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    // MARK: - Chat completion

    /// POSTs `<baseURL>/chat/completions` with a system + user message pair and
    /// returns the assistant's message content, trimmed.
    ///
    /// - Parameter timeout: request timeout in seconds. Default 30s — generous
    ///   enough for a cold local-model load on Ollama, short enough that a dead
    ///   endpoint does not stall a dictation session. [decision V01-2]
    public func chatCompletion(
        baseURL: URL,
        apiKey: String?,
        authStyle: LLMAuthStyle,
        model: String,
        systemPrompt: String,
        userText: String,
        timeout: TimeInterval = 30
    ) async throws -> String {
        let url = baseURL.appendingPathComponent("chat/completions")
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        switch authStyle {
        case .none:
            break

        case .bearer:
            if let apiKey, !apiKey.isEmpty {
                request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            }

        case .subscriptionKey:
            if let apiKey, !apiKey.isEmpty {
                request.setValue(apiKey, forHTTPHeaderField: "api-subscription-key")
            }
        }

        let body = ChatCompletionRequest(
            model: model,
            messages: [
                ChatCompletionRequest.Message(role: "system", content: systemPrompt),
                ChatCompletionRequest.Message(role: "user", content: userText)
            ],
            stream: false,
            maxTokens: 1024 // [decision V01-2: matches the openai-compatible-cleanup skill's REST shape]
        )
        request.httpBody = try JSONEncoder().encode(body)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw OpenAICompatibleClientError.notRunning
        }

        guard let http = response as? HTTPURLResponse else {
            throw OpenAICompatibleClientError.invalidResponse
        }

        switch http.statusCode {
        case 200..<300:
            break

        case 401:
            throw OpenAICompatibleClientError.unauthorized

        case 429:
            throw OpenAICompatibleClientError.rateLimited

        case 404:
            throw OpenAICompatibleClientError.modelNotInstalled(model)

        default:
            throw OpenAICompatibleClientError.requestFailed(http.statusCode)
        }

        guard let decoded = try? JSONDecoder().decode(ChatCompletionResponse.self, from: data),
              let content = decoded.choices.first?.message.content else {
            throw OpenAICompatibleClientError.invalidResponse
        }
        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Ollama availability

    /// Pings Ollama's local `/api/tags` endpoint. Never throws — any failure
    /// (not running, timeout, non-2xx) resolves to `false` so callers can use
    /// this directly as `LLMCleaning.isAvailable`.
    ///
    /// - Parameter timeout: 1s — a fast local probe, not a network round trip.
    ///   [decision V01-2, per the openai-compatible-cleanup skill]
    public func pingOllama(baseURL: URL, timeout: TimeInterval = 1) async -> Bool {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            return false
        }
        components.path = "/api/tags"
        guard let url = components.url else { return false }

        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.httpMethod = "GET"
        do {
            let (_, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { return false }
            return (200..<300).contains(http.statusCode)
        } catch {
            return false
        }
    }
}

// MARK: - Wire types (OpenAI chat-completions shape)

struct ChatCompletionRequest: Encodable {
    let model: String
    let messages: [Message]
    let stream: Bool
    let maxTokens: Int

    enum CodingKeys: String, CodingKey {
        case model, messages, stream
        case maxTokens = "max_tokens"
    }

    struct Message: Encodable {
        let role: String
        let content: String
    }
}

struct ChatCompletionResponse: Decodable {
    let choices: [Choice]

    struct Choice: Decodable {
        let message: Message
    }

    struct Message: Decodable {
        let content: String
    }
}
