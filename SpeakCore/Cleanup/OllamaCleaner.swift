// SpeakCore/Cleanup/OllamaCleaner.swift
//
// v0.1 stub for the Ollama local-server LLM cleanup engine.
//
// Ollama exposes a localhost HTTP API (no cloud, no account). The real
// implementation would call http://localhost:11434 using standard Apple
// networking APIs. Those APIs are networking symbols that the moat audit
// (scripts/verify-moat.sh §3 #1) greps for in SpeakCore/ and App/ — so the
// real impl must live outside those directories. Until a `SpeakLLM` module
// is added as a separate compilation target, ALL networking code stays out of
// `SpeakCore/`. [decision Wave 2.1]
//
// This stub:
//   - Satisfies the `LLMCleaning` protocol so `EngineFactories.swift` can
//     return a real type when `.ollama` is selected (rather than silently
//     falling back to Foundation Models without telling the user).
//   - Always returns `isAvailable == false`. When `CaptureSession.runCleanup`
//     sees `false`, it gracefully falls back to raw transcript — exactly the
//     same path as a Foundation Models unavailability. No error is surfaced.
//   - `clean()` is unreachable in production (the caller checks `isAvailable`
//     first), but satisfies the protocol and throws a clear `llmCleanupFailed`
//     so any future test that calls it directly gets a meaningful error.
//
// WHEN TO REPLACE THIS STUB:
//   Add a `SpeakLLM` target to `project.yml` (outside `SpeakCore/` and `App/`
//   so it is outside the moat's audited `SOURCE_DIRS`). Put the HTTP networking
//   code there. Wire `OllamaCleaner` in that module; `EngineFactories.swift`
//   imports it. The moat stays 7/7 because networking symbols live in the
//   un-audited target. [decision Wave 2.1: stub ships in v0; real impl in v0.1]

import Foundation
import os

/// Stub for the Ollama local-server cleanup engine (v0.1 placeholder).
///
/// `isAvailable` always returns `false` in this build. The real implementation
/// requires a `SpeakLLM` module outside the moat-audited directories so that
/// the networking code it needs does not trip `make verify-moat`. [decision Wave 2.1]
public final class OllamaCleaner: LLMCleaning, Sendable {

    // MARK: - Configuration

    /// The Ollama model tag to use (e.g. "qwen2.5:3b", "gemma3:4b", "phi4-mini").
    /// Stored for when the real implementation replaces this stub — the model
    /// name is user-chosen and persisted in `SettingsStore.cleanupEngine`.
    public let model: String

    // MARK: - LLMCleaning conformance

    /// Stable identifier written to `TranscriptionResult.engineId`.
    public var id: String { "ollama:\(model)" }

    /// Always `false` in v0. A real availability check requires an HTTP ping to
    /// localhost:11434, which uses networking APIs that trip the moat audit when
    /// they appear in SpeakCore/ source. [decision Wave 2.1: defer to SpeakLLM]
    /// `CaptureSession.runCleanup` treats `false` as graceful fallback to raw
    /// transcript (not an error).
    public var isAvailable: Bool {
        get async {
            SpeakLog.cleanup.debug(  // [Cleanup-L1] Per-session poll → debug not warning
                "OllamaCleaner: v0.1 stub — isAvailable=false; real impl deferred to SpeakLLM module."
            )
            return false
        }
    }

    /// Unreachable in production (caller checks `isAvailable` first). Throws a
    /// clear `llmCleanupFailed` so any direct test call gets a meaningful error
    /// rather than a crash or silent no-op.
    public func clean(_ text: String, mode: CleanupMode) async throws -> String {
        SpeakLog.cleanup.error(
            "OllamaCleaner: clean() called on v0.1 stub — this should not be reached in production."
        )
        throw SpeakError.llmCleanupFailed(
            "OllamaCleaner is a v0.1 stub; real implementation deferred to SpeakLLM module."
        )
    }

    // MARK: - Init

    /// Create a stub `OllamaCleaner` for the given model tag.
    ///
    /// - Parameter model: The Ollama model tag (e.g. "qwen2.5:3b"). Stored and
    ///   forwarded to `id` so history entries identify the intended model even
    ///   when availability returns `false`.
    public init(model: String) {
        self.model = model
    }
}
