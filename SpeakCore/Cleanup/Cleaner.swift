// SpeakCore/Cleanup/Cleaner.swift
//
// The AI neat-writing seam (v0 CORE — not optional). Every cleanup engine
// (Apple Foundation Models in v0, Ollama/MLX later) conforms to `LLMCleaning`.
// Signatures are verbatim from `docs/architecture.md` §6.

import Foundation

public protocol LLMCleaning: Sendable {
    var id: String { get }
    var isAvailable: Bool { get async }
    func clean(_ text: String, mode: CleanupMode) async throws -> String
}

public enum CleanupMode: Sendable {
    case fillersOnly
    case punctuation
    case codeAware
    case toneAdjust
    case translate(Locale)
}
