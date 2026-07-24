// SpeakLLM/InferenceServer/ModelRegistry.swift
//
// Discovers and tracks available inference backends on the local machine.
// Probes Apple FoundationModels availability, Ollama daemon, and MLX server.
// Exposes backend status for the /health and /v1/models endpoints.
//
// No third-party dependencies. Apple frameworks only (AGENTS.md §2.4).

import Foundation
import os

/// Information about a discovered inference backend.
public struct BackendInfo: Sendable, Identifiable {
    /// Unique model identifier used in API requests (e.g., "speak-default", "ollama/llama3.1:8b").
    public let id: String
    /// Human-readable backend name.
    public let name: String
    /// Current availability status.
    public let status: BackendStatus
    /// The localhost endpoint URL (nil for Apple Intelligence which is in-process).
    public let endpoint: String?
    /// Who owns/serves this model.
    public let ownedBy: String

    public init(id: String, name: String, status: BackendStatus, endpoint: String?, ownedBy: String) {
        self.id = id
        self.name = name
        self.status = status
        self.endpoint = endpoint
        self.ownedBy = ownedBy
    }
}

/// Availability status of an inference backend.
public enum BackendStatus: String, Sendable {
    /// Backend is available and ready to serve requests.
    case available
    /// Backend is reachable over the network.
    case reachable
    /// Backend is not running or unreachable.
    case offline
    /// Backend availability is unknown (not yet probed).
    case unknown
}

/// Actor that discovers and tracks available local inference backends.
///
/// Probes are performed on demand (not continuously) to avoid unnecessary
/// network traffic. The registry caches results for a configurable TTL.
public actor ModelRegistry {

    // MARK: - Constants

    /// Ollama default API endpoint for model listing.
    /// [decision: standard Ollama port 11434 per https://github.com/ollama/ollama]
    private static let ollamaModelsURL = "http://127.0.0.1:11434/api/tags"

    /// MLX LM server default endpoint for model listing.
    /// [decision: standard MLX LM server port 8080]
    private static let mlxModelsURL = "http://127.0.0.1:8080/v1/models"

    /// Probe timeout in seconds. Short timeout since these are localhost checks.
    /// [decision: 2s timeout — localhost should respond in <100ms if running]
    private static let probeTimeoutSeconds: TimeInterval = 2.0

    /// Cache TTL for backend probe results in seconds.
    /// [decision: 30s cache avoids hammering localhost services on every request]
    private static let cacheTTLSeconds: TimeInterval = 30.0

    /// Logger for backend discovery operations.
    private let logger = Logger(subsystem: "com.speak.app", category: "InferenceServer")

    // MARK: - State

    /// Cached backend information from the last discovery pass.
    private var cachedBackends: [BackendInfo] = []

    /// Timestamp of the last discovery pass.
    private var lastDiscoveryTime: Date = .distantPast

    // MARK: - Public API

    public init() {}

    /// Returns the list of known backends, refreshing if the cache is stale.
    public var backends: [BackendInfo] {
        get async {
            let now = Date()
            if now.timeIntervalSince(lastDiscoveryTime) > Self.cacheTTLSeconds {
                await discover()
            }
            return cachedBackends
        }
    }

    /// Forces a fresh discovery of all backends.
    public func discover() async {
        var discovered: [BackendInfo] = []

        // Apple FoundationModels — always available on macOS 26 with Apple Intelligence.
        let appleStatus = await probeAppleIntelligence()
        discovered.append(BackendInfo(
            id: "speak-default",
            name: "Apple SystemLanguageModel (AFM 3 Core)",
            status: appleStatus,
            endpoint: nil,
            ownedBy: "speak-local"
        ))
        discovered.append(BackendInfo(
            id: "speak-advanced",
            name: "Apple SystemLanguageModel (Advanced)",
            status: appleStatus,
            endpoint: nil,
            ownedBy: "speak-local"
        ))
        discovered.append(BackendInfo(
            id: "apple-intelligence",
            name: "Apple Intelligence (Direct)",
            status: appleStatus,
            endpoint: nil,
            ownedBy: "apple"
        ))

        // Ollama — probe localhost:11434
        let ollamaModels = await probeOllama()
        for model in ollamaModels {
            discovered.append(BackendInfo(
                id: "ollama/\(model)",
                name: "Ollama: \(model)",
                status: .reachable,
                endpoint: "http://127.0.0.1:11434",
                ownedBy: "ollama"
            ))
        }

        // MLX — probe localhost:8080
        let mlxModels = await probeMLX()
        for model in mlxModels {
            discovered.append(BackendInfo(
                id: "mlx/\(model)",
                name: "MLX: \(model)",
                status: .reachable,
                endpoint: "http://127.0.0.1:8080",
                ownedBy: "mlx"
            ))
        }

        cachedBackends = discovered
        lastDiscoveryTime = Date()
        logger.debug("Model discovery complete: \(discovered.count) backends found")
    }

    /// Returns backend status summary for the /health endpoint.
    public func backendStatusSummary() async -> [String: String] {
        let currentBackends = await backends
        var summary: [String: String] = [:]

        // Apple Intelligence status
        if let apple = currentBackends.first(where: { $0.id == "speak-default" }) {
            summary["apple_intelligence"] = apple.status.rawValue
        } else {
            summary["apple_intelligence"] = "unknown"
        }

        // Ollama status
        if currentBackends.contains(where: { $0.id.hasPrefix("ollama/") }) {
            summary["ollama"] = "reachable"
        } else {
            summary["ollama"] = "offline"
        }

        // MLX status
        if currentBackends.contains(where: { $0.id.hasPrefix("mlx/") }) {
            summary["mlx"] = "reachable"
        } else {
            summary["mlx"] = "offline"
        }

        return summary
    }

    // MARK: - Probes

    /// Checks Apple FoundationModels availability.
    private func probeAppleIntelligence() async -> BackendStatus {
        // On macOS 26 with Apple Silicon, SystemLanguageModel is available
        // when Apple Intelligence is enabled. We check at runtime.
        // The FoundationModels framework is always present on macOS 26.
        // [decision: report available — actual availability is checked per-request
        //  in InferenceRouter via SystemLanguageModel.availability]
        return .available
    }

    /// Probes the Ollama daemon for available models.
    /// Returns an array of model names, or empty if Ollama is not running.
    private func probeOllama() async -> [String] {
        guard let url = URL(string: Self.ollamaModelsURL) else { return [] }

        var request = URLRequest(url: url)
        request.timeoutInterval = Self.probeTimeoutSeconds
        request.httpMethod = "GET"

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                return []
            }
            // Parse Ollama /api/tags response: {"models": [{"name": "llama3.1:8b", ...}]}
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let models = json["models"] as? [[String: Any]] else {
                return []
            }
            return models.compactMap { $0["name"] as? String }
        } catch {
            logger.debug("Ollama probe failed: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    /// Probes the MLX LM server for available models.
    /// Returns an array of model names, or empty if MLX is not running.
    private func probeMLX() async -> [String] {
        guard let url = URL(string: Self.mlxModelsURL) else { return [] }

        var request = URLRequest(url: url)
        request.timeoutInterval = Self.probeTimeoutSeconds
        request.httpMethod = "GET"

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                return []
            }
            // Parse OpenAI-compatible /v1/models response: {"data": [{"id": "..."}]}
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let models = json["data"] as? [[String: Any]] else {
                return []
            }
            return models.compactMap { $0["id"] as? String }
        } catch {
            logger.debug("MLX probe failed: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }
}
