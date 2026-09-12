// SpeakCore/Cleanup/StreamingChunkCoordinator.swift
//
// Progressive chunk-by-chunk cleanup coordinator.
// Transforms speech incrementally as chunks finalize during recording, eliminating
// bulk post-speech latency (from 5–8s down to <200ms) and preventing the 3B model
// from over-editing long run-on dictations.

import Foundation
import os

public actor StreamingChunkCoordinator {

    public struct ChunkResult: Sendable {
        public let raw: String
        public let cleaned: String
        public let isFinal: Bool
    }

    private let cleaner: any LLMCleaning
    private let mode: CleanupMode
    private var chunkTasks: [Task<String, Never>] = []
    private var rawChunks: [String] = []
    private var chunkErrors: [String] = []
    private var lastTask: Task<String, Never>?

    /// TTL-cached `isAvailable` result — for HTTP-backed cleaners (Ollama)
    /// the check is a live network ping; running it per chunk serialized an
    /// HTTP round-trip into every task-chain link. A stale `true` is safe
    /// (`clean` throws → raw fallback); a stale `false` self-heals at the TTL.
    /// [fix: audit — per-chunk isAvailable ping]
    private var availabilityCache: (value: Bool, checkedAt: ContinuousClock.Instant)?
    private static let availabilityTTL: Duration = .seconds(10)

    public init(cleaner: any LLMCleaning, mode: CleanupMode) {
        self.cleaner = cleaner
        self.mode = mode
    }

    /// The number of chunks currently ingested or processed.
    public var chunkCount: Int {
        chunkTasks.count
    }

    public var hasFailed: Bool {
        !chunkErrors.isEmpty
    }

    func recordError(_ description: String) {
        chunkErrors.append(description)
    }

    /// Ingests a finalized raw text chunk during active speech and fires an asynchronous cleanup task.
    /// Serializes tasks using a task chain to prevent concurrent contention on the Neural Engine.
    ///
    /// - Parameter chunkText: The stabilized text emitted by the speech recognizer.
    public func ingestChunk(_ chunkText: String) {
        let trimmed = chunkText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        rawChunks.append(trimmed)
        let cleanerRef = self.cleaner
        let modeRef = self.mode
        let priorTask = self.lastTask

        // Chain the task onto the prior task to ensure strict single-lane execution
        // while still processing continuously in the background during active speech.
        let task = Task<String, Never> { [weak self] in
            _ = await priorTask?.value
            guard let self, await self.cleanerAvailable() else {
                return trimmed
            }
            do {
                let cleaned = try await cleanerRef.clean(trimmed, mode: modeRef)
                let extracted = FoundationModelPromptBuilder.extractTargetTranscript(from: cleaned, fallback: trimmed)
                return extracted.trimmingCharacters(in: .whitespacesAndNewlines)
            } catch {
                await self.recordError(error.localizedDescription)
                SpeakLog.cleanup.warning(
                    "StreamingChunkCoordinator: chunk clean failed, falling back to raw — \(error.localizedDescription, privacy: .public)"
                )
                return trimmed
            }
        }
        self.lastTask = task
        chunkTasks.append(task)
    }

    /// `cleaner.isAvailable` with a short TTL — see `availabilityCache`.
    /// `internal` for `@testable` verification of the cache behavior.
    func cleanerAvailable() async -> Bool {
        if let cache = availabilityCache,
           cache.checkedAt.duration(to: .now) < Self.availabilityTTL {
            return cache.value
        }
        let value = await cleaner.isAvailable
        availabilityCache = (value, .now)
        return value
    }

    /// Determines whether the current cleanup mode benefits from the full-chunk macro-consolidation pass.
    private var isMacroConsolidationEligible: Bool {
        switch mode {
        case .styled(let style, _, _):
            return style == .code || style == .professional || style == .default

        case .profile:
            return true

        case .toneAdjust, .codeAware:
            return true

        case .fillersOnly, .punctuation, .translate, .command:
            return false
        }
    }

    /// Awaits all in-flight chunk cleanup tasks and stitches the result.
    /// When multiple chunks or extended thoughts exist, performs a deterministic
    /// full-chunk macro-reprocessing pass to collapse train-of-thought resets into
    /// a crisp final instruction.
    ///
    /// - Parameter trailingRawText: Any final volatile or remaining text not captured in earlier chunks.
    /// - Returns: The stitched, normalized, and macro-consolidated full transcript.
    public func finalizeAndStitch(trailingRawText: String? = nil) async throws -> String {
        for task in chunkTasks {
            _ = await task.value
        }
        if let firstError = chunkErrors.first {
            throw SpeakError.llmCleanupFailed("Chunk cleanup failed: \(firstError)")
        }

        var cleanedChunks: [String] = []

        for task in chunkTasks {
            let cleaned = await task.value
            if !cleaned.isEmpty {
                cleanedChunks.append(cleaned)
            }
        }

        // If there is trailing raw text (e.g. from the final volatile window), clean it now.
        if let trailing = trailingRawText?.trimmingCharacters(in: .whitespacesAndNewlines), !trailing.isEmpty {
            let cleanedTrailing = try await cleaner.clean(trailing, mode: mode)
            let extracted = FoundationModelPromptBuilder.extractTargetTranscript(from: cleanedTrailing)
            cleanedChunks.append(extracted.isEmpty ? trailing : extracted)
        }

        let stitched = TranscriptChunker.stitch(cleanedChunks)
        let normalizedDraft = DeveloperAcronymNormalizer.normalize(stitched)

        // Tier 3: Deterministic Full-Chunk Macro-Consolidation Pass.
        // Runs only when multiple chunks exist — the pass's job is collapsing
        // train-of-thought resets *across* stitch boundaries. A single chunk
        // already went through `clean` as one unit; re-cleaning it was a
        // second full model pass on the release path — pure latency for a
        // dictation that was already cleaned in full during speech.
        // [decision: felt-latency — the visible "Processing" wait is this pass]
        let wordCount = normalizedDraft.split(whereSeparator: { $0.isWhitespace }).count
        guard isMacroConsolidationEligible, chunkTasks.count > 1 else {
            return normalizedDraft
        }

        SpeakLog.cleanup.info(
            "StreamingChunkCoordinator: running full-chunk macro consolidation on \(wordCount, privacy: .public) words across \(self.chunkTasks.count, privacy: .public) chunks."
        )

        do {
            let consolidated = try await cleaner.clean(normalizedDraft, mode: mode)
            let extracted = FoundationModelPromptBuilder.extractTargetTranscript(from: consolidated)
            if !extracted.isEmpty {
                return DeveloperAcronymNormalizer.normalize(extracted)
            }
        } catch {
            SpeakLog.cleanup.warning(
                "StreamingChunkCoordinator: macro consolidation failed, falling back to stitched draft — \(error.localizedDescription, privacy: .public)"
            )
        }

        return normalizedDraft
    }

    /// Resets all accumulated chunk state (e.g. on session cancel).
    public func reset() {
        lastTask?.cancel()
        lastTask = nil
        for task in chunkTasks {
            task.cancel()
        }
        chunkTasks.removeAll()
        chunkErrors.removeAll()
        rawChunks.removeAll()
    }
}
