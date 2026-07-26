// SpeakLLM/ProvenanceReceipt.swift
//
// Provenance metadata attached to every inference response. Emitted as a
// terminal SSE event so the UI can render a "wine label" colophon showing
// which backend answered, how long it took, and token usage.
//
// This makes the routing layer's value visible and builds developer trust:
// every response carries its own diagnostic receipt.

import Foundation

// MARK: - ProvenanceReceipt

/// Metadata about how a specific inference response was produced.
public struct ProvenanceReceipt: Sendable, Equatable {
    /// The backend that actually produced the response (e.g., "apple-intelligence", "ollama/qwen3").
    public let backendID: String

    /// The model originally requested by the client.
    public let requestedModel: String

    /// Wall-clock latency in milliseconds (first request byte → last response byte).
    public let latencyMS: Int

    /// Approximate prompt token count.
    public let promptTokens: Int

    /// Approximate completion token count.
    public let completionTokens: Int

    /// Whether the router fell back to a different backend than requested.
    public let fellBack: Bool

    public init(
        backendID: String,
        requestedModel: String,
        latencyMS: Int,
        promptTokens: Int,
        completionTokens: Int,
        fellBack: Bool
    ) {
        self.backendID = backendID
        self.requestedModel = requestedModel
        self.latencyMS = latencyMS
        self.promptTokens = promptTokens
        self.completionTokens = completionTokens
        self.fellBack = fellBack
    }

    /// Serializes to a JSON dictionary for SSE emission.
    public func toJSON() -> [String: Any] {
        [
            "backend": backendID,
            "requested_model": requestedModel,
            "latency_ms": latencyMS,
            "prompt_tokens": promptTokens,
            "completion_tokens": completionTokens,
            "fell_back": fellBack
        ]
    }

    /// Parses from a JSON dictionary (SSE event payload).
    public static func from(json: [String: Any]) -> ProvenanceReceipt? {
        guard let backend = json["backend"] as? String,
              let requested = json["requested_model"] as? String,
              let latency = json["latency_ms"] as? Int,
              let promptTok = json["prompt_tokens"] as? Int,
              let completionTok = json["completion_tokens"] as? Int else {
            return nil
        }
        let fellBack = json["fell_back"] as? Bool ?? false
        return ProvenanceReceipt(
            backendID: backend,
            requestedModel: requested,
            latencyMS: latency,
            promptTokens: promptTok,
            completionTokens: completionTok,
            fellBack: fellBack
        )
    }

    /// One-line colophon string for display: "ollama/qwen3 · 842ms · 118 tok · direct"
    public var colophon: String {
        let totalTokens = promptTokens + completionTokens
        let mode = fellBack ? "fallback" : "direct"
        return "\(backendID) · \(latencyMS)ms · \(totalTokens) tok · \(mode)"
    }
}
