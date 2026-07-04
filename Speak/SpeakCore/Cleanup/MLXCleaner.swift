// SpeakCore/Cleanup/MLXCleaner.swift
//
// v0.1+ stub for an MLX-based on-device LLM cleanup engine.
//
// MLX is Apple's machine-learning framework for Apple Silicon (open source,
// github.com/ml-explore/mlx). An MLX Swift cleanup engine would load a
// quantized model (e.g. Qwen2.5-3B-Instruct-4bit) directly on the Neural
// Engine via MLXLMCommon, no Ollama server required. Apple distributes the
// MLX Swift packages separately — they are not part of the macOS SDK — so
// MLX IS a third-party dependency and is forbidden in v0. [AGENTS.md §2.9]
//
// This stub:
//   - Registers MLX as a known `CleanupEngine` alternative in the UI.
//   - Always returns `isAvailable == false` so the moat and the no-third-
//     party-deps rule are never breached.
//   - Makes the UI picker honest about MLX's roadmap status.
//
// WHEN TO REPLACE THIS STUB:
//   Add `mlx-swift` + `mlx-swift-examples` as SPM dependencies in `project.yml`
//   (v0.1+ only). Implement the real `clean()` using `LLMInference` from
//   `MLXLMCommon`. Wire it in `EngineFactories.swift`.
//   [decision Wave 2.1: MLX ships as opt-in v0.1+ dep, not default]

import Foundation
import os

/// Stub for the MLX on-device LLM cleanup engine (v0.1+ placeholder).
///
/// Always returns `isAvailable == false`. Requires MLX Swift packages (a
/// third-party dep forbidden in v0). [decision Wave 2.1]
public final class MLXCleaner: LLMCleaning, Sendable {

    // MARK: - Configuration

    /// The model tag to load via MLX (e.g. "Qwen2.5-3B-Instruct-4bit").
    public let model: String

    // MARK: - LLMCleaning conformance

    /// Stable identifier written to `TranscriptionResult.engineId`.
    public var id: String { "mlx:\(model)" }

    /// Always `false` in v0 — MLX is a third-party dep, forbidden until v0.1.
    /// `CaptureSession.runCleanup` gracefully falls back to raw transcript.
    public var isAvailable: Bool {
        get async {
            SpeakLog.cleanup.debug(  // [Cleanup-L1] Per-session poll → debug not warning
                "MLXCleaner: v0.1+ stub — isAvailable=false; real impl deferred pending MLX Swift dep approval."
            )
            return false
        }
    }

    /// Unreachable in production (caller checks `isAvailable` first).
    public func clean(_ text: String, mode: CleanupMode) async throws -> String {
        SpeakLog.cleanup.error(
            "MLXCleaner: clean() called on v0.1+ stub — this should not be reached in production."
        )
        throw SpeakError.llmCleanupFailed(
            "MLXCleaner is a v0.1+ stub; real implementation deferred pending MLX Swift dep approval."
        )
    }

    // MARK: - Init

    /// Create a stub `MLXCleaner` for the given model tag.
    public init(model: String) {
        self.model = model
    }
}
