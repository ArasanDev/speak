// SpeakCore/Diff/TextDiff.swift
//
// Pure word-level diff for the W4.1 transparency moat: "see exactly what the AI changed."
//
// DESIGN:
//   - Dependency-free: no third-party library. This is a first-class product feature,
//     not a utility import. [decision W4.1]
//   - Word-level granularity: finer than line-level (which would show entire sentences
//     as changed), coarser than character-level (which is noisy for transcript diffs).
//     The AI changes words, so word-level is the right unit. [decision W4.1]
//   - Tokenization: split on whitespace. Punctuation attached to a word is part of the
//     same token ("Hello," is one token). This is correct for cleanup diffs where the
//     AI adds a comma or period — the whole token changes, which is what the user sees.
//     [decision W4.1: whitespace-split, not Unicode-word-boundary-split; simpler,
//     sufficient for transcripts, and avoids pulling in ICU or custom tokenizers]
//   - Algorithm: Myers / LCS via dynamic-programming table. O(n*m) time + space on the
//     number of tokens. Transcripts are short (< 500 words); this is fast enough.
//     [decision W4.1: classic DP-LCS, not Myers edit-graph; clearer to audit]
//   - Public: so `CleanupDiffView` (App/) and tests (SpeakTests/) can both import it.
//     `SpeakCore` is the portability seam per architecture §6.
//
// UNIT-TESTABLE: `diff(rawTokens:cleanedTokens:)` is `internal` → `@testable import`
// in tests. `diff(raw:cleaned:)` is the public entry point.
//
// NO PRINT: logging is the caller's responsibility. This module is pure transform.

import Foundation

// MARK: - Public types

/// One segment in a word-level diff. Carries its kind (equal/insert/delete) and the
/// display text for that segment. A sequence of these describes all changes between
/// `rawText` and `cleanedText`. [decision W4.1: value type, Sendable, Hashable for
/// use in SwiftUI ForEach]
public struct DiffSegment: Sendable, Equatable, Hashable, Identifiable {

    public enum Kind: Sendable, Equatable, Hashable {
        /// The word appears in both raw and cleaned (unchanged). Displayed in neutral color.
        case equal
        /// The word was added by the AI (appears in cleaned but not raw). Displayed in green.
        case insert
        /// The word was removed by the AI (appears in raw but not cleaned). Displayed in red strikethrough.
        case delete
    }

    /// The kind of change this segment represents.
    public let kind: Kind
    /// The display text for this segment (one or more words joined by the original spacing).
    public let text: String
    /// Stable identifier for SwiftUI ForEach. Derived from kind + text + position.
    public let id: UUID

    /// Internal init — callers use `TextDiff.diff(raw:cleaned:)`.
    init(kind: Kind, text: String) {
        self.kind = kind
        self.text = text
        self.id = UUID()
    }
}

// MARK: - Public entry point

/// Computes a word-level diff between `raw` and `cleaned` text.
///
/// Returns an ordered array of `DiffSegment` values that describes every
/// equal, inserted, and deleted word. Equal runs are collapsed into a single
/// segment; consecutive inserts and consecutive deletes are each collapsed.
///
/// Edge cases:
///   - Both empty → `[]`
///   - `raw` empty → one `.insert` segment containing all of `cleaned`
///   - `cleaned` empty → one `.delete` segment containing all of `raw`
///   - Identical → one `.equal` segment
///   - No overlap → one `.delete` then one `.insert`
///
/// - Parameters:
///   - raw:     The original (pre-cleanup) text.
///   - cleaned: The AI-cleaned text.
/// - Returns:   An ordered array of `DiffSegment` values.
public func textDiff(raw: String, cleaned: String) -> [DiffSegment] {
    // Tokenize on whitespace (see file-header decision on tokenization).
    let rawTokens = tokenize(raw)
    let cleanedTokens = tokenize(cleaned)
    return diff(rawTokens: rawTokens, cleanedTokens: cleanedTokens)
}

// MARK: - Internal implementation (exposed for unit testing via @testable)

/// Tokenize a string into whitespace-delimited words. Preserves punctuation
/// attached to each word. Empty string → `[]`.
/// `internal` (not `private`) so it is directly testable. [decision W4.1]
func tokenize(_ text: String) -> [String] {
    // `components(separatedBy:)` splits on every whitespace run.
    // `.whitespacesAndNewlines` handles \t, \n, \r\n from the LLM response.
    // Filter out empty strings from leading/trailing whitespace.
    text.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
}

/// Core LCS-based diff. Takes already-tokenized arrays.
/// `internal` for unit testing; public callers use `textDiff(raw:cleaned:)`.
/// [decision W4.1: DP-LCS, not Myers; see file header]
func diff(rawTokens: [String], cleanedTokens: [String]) -> [DiffSegment] {
    let n = rawTokens.count
    let m = cleanedTokens.count

    // Empty-input fast paths.
    if n == 0 && m == 0 { return [] }
    if n == 0 {
        return [DiffSegment(kind: .insert, text: cleanedTokens.joined(separator: " "))]
    }
    if m == 0 {
        return [DiffSegment(kind: .delete, text: rawTokens.joined(separator: " "))]
    }

    // Build the LCS table. `lcs[i][j]` = LCS length of rawTokens[0..<i] and
    // cleanedTokens[0..<j]. We use a (n+1)×(m+1) table initialized to zero.
    // [decision: 2D array for clarity; Swift arrays are value-type but small
    //  enough for transcript lengths (< 500 words → < 250k cells)]
    var lcs = [[Int]](repeating: [Int](repeating: 0, count: m + 1), count: n + 1)
    for i in 1...n {
        for j in 1...m {
            if rawTokens[i - 1] == cleanedTokens[j - 1] {
                lcs[i][j] = lcs[i - 1][j - 1] + 1
            } else {
                lcs[i][j] = max(lcs[i - 1][j], lcs[i][j - 1])
            }
        }
    }

    // Backtrack through the LCS table to build the edit sequence.
    // Each step produces a `.equal`, `.delete`, or `.insert` entry for one token.
    var edits: [(kind: DiffSegment.Kind, word: String)] = []
    var i = n, j = m
    while i > 0 || j > 0 {
        if i > 0 && j > 0 && rawTokens[i - 1] == cleanedTokens[j - 1] {
            edits.append((.equal, rawTokens[i - 1]))
            i -= 1; j -= 1
        } else if j > 0 && (i == 0 || lcs[i][j - 1] >= lcs[i - 1][j]) {
            edits.append((.insert, cleanedTokens[j - 1]))
            j -= 1
        } else {
            edits.append((.delete, rawTokens[i - 1]))
            i -= 1
        }
    }
    // Backtracking produces reverse order; flip to forward.
    edits.reverse()

    // Collapse consecutive same-kind edits into one segment for the view.
    // This converts ["um", "uh"] (two consecutive deletes) into a single
    // DiffSegment(kind: .delete, text: "um uh"). [decision W4.1: collapsed
    // segments make the view simpler — one Text per run, not one per word]
    return collapse(edits)
}

/// Collapse a flat per-word edit list into runs of the same kind.
private func collapse(_ edits: [(kind: DiffSegment.Kind, word: String)]) -> [DiffSegment] {
    guard !edits.isEmpty else { return [] }

    var segments: [DiffSegment] = []
    var currentKind = edits[0].kind
    var currentWords: [String] = [edits[0].word]

    for edit in edits.dropFirst() {
        if edit.kind == currentKind {
            currentWords.append(edit.word)
        } else {
            segments.append(DiffSegment(kind: currentKind, text: currentWords.joined(separator: " ")))
            currentKind = edit.kind
            currentWords = [edit.word]
        }
    }
    segments.append(DiffSegment(kind: currentKind, text: currentWords.joined(separator: " ")))
    return segments
}
