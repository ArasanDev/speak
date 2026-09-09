// SpeakCore/Cleanup/TranscriptChunker.swift
//
// Pure, deterministic sentence- and clause-boundary chunking for spoken transcripts.
// Breaks long voice streams of consciousness into natural, bounded units (10–25 words)
// so the small on-device Foundation Model cleans each chunk without over-editing,
// summarizing, or dropping clauses.

import Foundation

public struct TranscriptChunker: Sendable {

    /// Default word count threshold above which chunking is activated.
    /// Dictations shorter than this threshold are processed in a single pass.
    public static let defaultChunkWordThreshold = 25

    /// Splits `text` into natural sentence chunks using Foundation's linguistic boundary engine.
    ///
    /// - Parameters:
    ///   - text: The raw transcript text to segment.
    ///   - wordThreshold: Minimum word count to trigger chunking (default 25).
    /// - Returns: An array of trimmed, non-empty chunk strings.
    public static func chunk(_ text: String, wordThreshold: Int = defaultChunkWordThreshold) -> [String] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        // Fast path: if the text is short, return as a single chunk immediately.
        let words = trimmed.split(whereSeparator: { $0.isWhitespace })
        guard words.count > wordThreshold else {
            return [trimmed]
        }

        var detectedChunks: [String] = []
        let nsString = trimmed as NSString
        let fullRange = NSRange(location: 0, length: nsString.length)

        nsString.enumerateSubstrings(in: fullRange, options: [.bySentences, .localized]) { substring, _, _, _ in
            guard let sentence = substring?.trimmingCharacters(in: .whitespacesAndNewlines), !sentence.isEmpty else {
                return
            }
            detectedChunks.append(sentence)
        }

        // If sentence enumeration didn't split (e.g. no punctuation in raw ASR),
        // fallback to clause connectors or word-budget chunks.
        if detectedChunks.count <= 1 {
            detectedChunks = chunkByClauseOrBudget(words: words, budget: wordThreshold)
        }

        return detectedChunks.isEmpty ? [trimmed] : detectedChunks
    }

    /// Fallback chunker when raw ASR contains zero punctuation.
    /// Splits along conversational connector words ("and", "so", "but", "also", "then")
    /// or word budget boundaries.
    private static func chunkByClauseOrBudget(words: [String.SubSequence], budget: Int) -> [String] {
        var chunks: [String] = []
        var currentChunk: [String] = []
        let clauseConnectors: Set<String> = ["and", "so", "but", "also", "then", "because"]

        for word in words {
            let lower = word.lowercased()
            // If current chunk has grown enough and hits a natural connector, split.
            if currentChunk.count >= budget && clauseConnectors.contains(lower) {
                chunks.append(currentChunk.joined(separator: " "))
                currentChunk = [String(word)]
            } else if currentChunk.count >= (budget * 2) {
                // Hard ceiling to prevent runaway chunk size.
                currentChunk.append(String(word))
                chunks.append(currentChunk.joined(separator: " "))
                currentChunk = []
            } else {
                currentChunk.append(String(word))
            }
        }

        if !currentChunk.isEmpty {
            chunks.append(currentChunk.joined(separator: " "))
        }

        return chunks
    }

    /// Stitches cleaned chunks back into a cohesive, properly spaced transcript.
    ///
    /// - Parameter chunks: Array of cleaned chunk strings.
    /// - Returns: A single combined text string with normalized spacing and punctuation.
    public static func stitch(_ chunks: [String]) -> String {
        guard !chunks.isEmpty else { return "" }
        if chunks.count == 1 { return chunks[0] }

        var result = ""
        for (index, chunk) in chunks.enumerated() {
            let trimmed = chunk.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            if index == 0 {
                result = trimmed
            } else {
                // Ensure single space separation.
                let lastChar = result.last ?? " "
                if lastChar == "\n" {
                    result += trimmed
                } else {
                    result += " " + trimmed
                }
            }
        }
        return result
    }
}
