// SpeakCore/Cleanup/FoundationModelsCleaner.swift
//
// Default implementation of `LLMCleaning` using Apple's on-device Foundation Models
// framework (macOS 26, Apple Silicon + Neural Engine).
//
// Refactored for clean modularity:
//   • Prompt synthesis is delegated to `FoundationModelPromptBuilder`
//   • Lexical acronym normalization is delegated to `DeveloperAcronymNormalizer`
//   • Sentence and clause chunking is delegated to `TranscriptChunker`

import Foundation
import FoundationModels
import os

@available(macOS 26.0, *)
public final class FoundationModelsCleaner: LLMCleaning, Sendable {

    // MARK: - LLMCleaning Conformance

    /// Stable identifier for this engine, written to `TranscriptionResult.engineId`.
    public let id = "foundation-models"

    /// Single shared system model instance with permissive guardrails for dictation cleanup.
    private let model = SystemLanguageModel(
        useCase: .general,
        guardrails: .permissiveContentTransformations
    )

    public let voiceProvenanceHeaderEnabled: Bool

    /// Creates a new `FoundationModelsCleaner`. Lightweight — no model is loaded at init time.
    public init(voiceProvenanceHeaderEnabled: Bool = false) {
        self.voiceProvenanceHeaderEnabled = voiceProvenanceHeaderEnabled
    }

    /// Returns `true` when the on-device Foundation Models engine is ready to accept requests.
    public var isAvailable: Bool {
        get async {
            let availability = model.availability
            switch availability {
            case .available:
                SpeakLog.cleanup.debug("FoundationModelsCleaner: model available")
                return true

            case .unavailable(let reason):
                let reasonDescription = String(describing: reason)
                SpeakLog.cleanup.warning(
                    "FoundationModelsCleaner: model unavailable — reason: \(reasonDescription, privacy: .public)"
                )
                return false
            }
        }
    }

    // MARK: - Cleaning Execution

    /// Cleans the raw transcript using the on-device Foundation Models engine.
    ///
    /// If the input is a long multi-sentence ramble, it is processed via chunked
    /// transformation to eliminate latency and prevent over-editing.
    public func clean(_ text: String, mode: CleanupMode) async throws -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        let chunks = TranscriptChunker.chunk(trimmed)
        SpeakLog.cleanup.debug(
            "FoundationModelsCleaner: cleaning \(trimmed.count, privacy: .public) chars across \(chunks.count, privacy: .public) chunk(s)"
        )

        var cleanedChunks: [String] = []
        for chunk in chunks {
            let cleanedChunk = try await cleanSingleChunk(chunk, mode: mode)
            cleanedChunks.append(cleanedChunk)
        }

        var result = TranscriptChunker.stitch(cleanedChunks)
        result = DeveloperAcronymNormalizer.normalize(result)

        if voiceProvenanceHeaderEnabled {
            let header = "[Audio Transcript • Speak Engine]\n> Note: Dictated via live voice ramble.\n\n"
            result = header + result
        }

        SpeakLog.cleanup.debug("FoundationModelsCleaner: cleaned result length \(result.count, privacy: .public) chars")
        return result
    }

    /// Cleans an individual, bounded chunk of text using a fresh LanguageModelSession.
    private func cleanSingleChunk(_ text: String, mode: CleanupMode) async throws -> String {
        // Pass 1: Deterministic Lexical Pre-Cleaning (0ms Swift regex pass)
        // Collapses repeated stutters ("I will I will" -> "I will") and prunes throat-clearing
        // preambles so the 3B model attention window is primed with clean text.
        let preCleaned = DeveloperAcronymNormalizer.normalize(text)

        let systemInstructions = FoundationModelPromptBuilder.instructions(for: mode)
        let session = LanguageModelSession(
            model: model,
            instructions: Instructions(systemInstructions)
        )

        let promptText = FoundationModelPromptBuilder.userPrompt(preCleaned)
        do {
            let options = GenerationOptions(sampling: .greedy)
            let response = try await session.respond(to: Prompt(promptText), options: options)
            let cleaned = FoundationModelPromptBuilder.extractTargetTranscript(from: response.content, fallback: preCleaned)
            return cleaned
        } catch let genError as LanguageModelSession.GenerationError {
            let detail = genError.localizedDescription
            SpeakLog.cleanup.error("FoundationModelsCleaner: GenerationError — \(detail, privacy: .public)")
            throw SpeakError.llmCleanupFailed(detail)
        } catch {
            let detail = error.localizedDescription
            SpeakLog.cleanup.error("FoundationModelsCleaner: unexpected error — \(detail, privacy: .public)")
            throw SpeakError.llmCleanupFailed(detail)
        }
    }

    // MARK: - Warm-up (V01-W warm cleanup model)

    private static let warmUpPromptText = "Ready."

    /// Best-effort engine warm-up: prewarms assets so the first real dictation does not hit cold-start latency.
    public func warmUp() async {
        guard await isAvailable else {
            SpeakLog.cleanup.debug("FoundationModelsCleaner: warm-up skipped — model unavailable.")
            return
        }

        let session = LanguageModelSession(
            model: model,
            instructions: Instructions(FoundationModelPromptBuilder.instructions(for: .punctuation))
        )
        session.prewarm()
        guard !Task.isCancelled else { return }
        do {
            let options = GenerationOptions(sampling: .greedy)
            _ = try await session.respond(to: Prompt(Self.warmUpPromptText), options: options)
            SpeakLog.cleanup.debug("FoundationModelsCleaner: warm-up complete.")
        } catch {
            SpeakLog.cleanup.debug(
                "FoundationModelsCleaner: warm-up respond failed (logged no-op) — \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    // MARK: - Backward Compatibility Forwarders

    public static var developerAcronymRules: [(spoken: String, written: String)] {
        DeveloperAcronymNormalizer.rules
    }

    public static func fixDeveloperAcronyms(_ text: String) -> String {
        DeveloperAcronymNormalizer.normalize(text)
    }

    public static func instructions(for mode: CleanupMode) -> String {
        FoundationModelPromptBuilder.instructions(for: mode)
    }

    public static func modeInstructions(for mode: CleanupMode) -> String {
        FoundationModelPromptBuilder.modeInstructions(for: mode)
    }

    public static func commandInstructions(instruction: String) -> String {
        FoundationModelPromptBuilder.commandInstructions(instruction: instruction)
    }

    public static func styledInstructions(style: CleanupStyle, level: CleanupLevel,
                                          customVocabulary: [String] = []) -> String {
        FoundationModelPromptBuilder.styledInstructions(style: style, level: level, customVocabulary: customVocabulary)
    }

    public static func wrapTranscript(_ text: String) -> String {
        FoundationModelPromptBuilder.wrapTranscript(text)
    }

    public static func userTurnTask() -> String {
        FoundationModelPromptBuilder.userTurnTask()
    }

    public static func userPrompt(_ text: String) -> String {
        FoundationModelPromptBuilder.userPrompt(text)
    }

    public static func unescapeTranscript(_ text: String) -> String {
        FoundationModelPromptBuilder.unescapeTranscript(text)
    }

    public static func extractTargetTranscript(from text: String) -> String {
        FoundationModelPromptBuilder.extractTargetTranscript(from: text)
    }
}
