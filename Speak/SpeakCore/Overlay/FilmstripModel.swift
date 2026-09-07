// SpeakCore/Overlay/FilmstripModel.swift
//
// Felt-speed (input-felt-speed.md §3.3) — the horizontal filmstrip transcript.
//
// The overlay HUD is a FIXED, never-growing panel (520×88 — it must not expand
// vertically; scrolling is forbidden). When the streaming transcript would exceed
// the visible area, the overflow is captured as a miniaturized block that slides
// LEFT (abandoned horizontally, block by block), while the active area keeps
// streaming fresh words at full size.
//
// This file is the PURE, TESTABLE model for that choreography. No SwiftUI, no
// AppKit — the view layer consumes it.
//
// The rules (from the product direction, locked 2026-08-03):
//   • The panel NEVER grows vertically and never scrolls vertically.
//   • When the active text reaches the block threshold, it is cut into a block:
//     the block holds the text, is marked `isMiniaturized` (rendered ~2–3× smaller),
//     and slides left.
//   • The active area resets to the remainder (or empty) and keeps streaming.
//   • Blocks can be sent to the cleanup engine for live per-block AI polish.

import Foundation

/// One completed horizontal filmstrip block — text captured out of the active
/// streaming area, miniaturized, and abandoned left.
public struct FilmstripBlock: Sendable, Equatable, Identifiable {
    public let id: UUID
    /// The raw text captured in this block.
    public var rawText: String
    /// The live-polished result, once the per-block AI cleanup returns.
    /// `nil` until the block is being polished / has no result.
    public var cleanedText: String?
    /// `true` once the per-block AI polish has completed (or deterministically
    /// produced no result, e.g. cleanup off). Drives the "Polishing…" → polished
    /// affordance on the block.
    public var isPolished: Bool
    /// `true` while this block is being actively polished by the cleanup engine.
    public var isPolishing: Bool

    public init(
        id: UUID = UUID(),
        rawText: String,
        cleanedText: String? = nil,
        isPolished: Bool = false,
        isPolishing: Bool = false
    ) {
        self.id = id
        self.rawText = rawText
        self.cleanedText = cleanedText
        self.isPolished = isPolished
        self.isPolishing = isPolishing
    }

    /// The text this block should DISPLAY: the polished result when available,
    /// otherwise the raw text.
    public var displayText: String { cleanedText ?? rawText }
}

/// Decides WHEN to cut the active streaming text into a horizontal block.
///
/// The cut is a pure function of the streaming text + a maximum character budget.
/// The budget models the visible 3-line area of the fixed panel: text beyond the
/// budget overflows, so it becomes a block. [decision: character-budget over
/// line-count because the streaming text arrives word-by-word and the panel is
/// fixed-width — a char budget is deterministic and testable without layout.]
public struct FilmstripCutter: Sendable, Equatable {
    /// The maximum number of characters that fit in the active streaming area.
    /// [decision: ~120 chars ≈ 3 lines at the HUD's monospaced 11pt in the CENTER
    /// lane of the 520pt panel (after the left waveform + right chrome). Traced to
    /// the panel's fixed size; revisit with live dogfood. Locked 2026-08-04: the
    /// active area is the CENTER anchor, so the budget tracks the center lane, not
    /// the full 520pt panel width.]
    public var maxActiveChars: Int

    public init(maxActiveChars: Int = 120) {
        self.maxActiveChars = maxActiveChars
    }

    /// Returns the prefix that becomes a block, or `nil` if the active text still
    /// fits (no cut yet).
    ///
    /// The block is the longest sentence-ish prefix within the budget: we cut at
    /// the last sentence boundary (". ", "! ", "? ") at or before `maxActiveChars`,
    /// falling back to the last whitespace, falling back to a hard character cut.
    /// This keeps blocks sentence-aligned where possible — cleaner than mid-word.
    public func blockCut(for text: String) -> String? {
        guard text.count > maxActiveChars else { return nil }

        let hardLimit = text.index(text.startIndex, offsetBy: maxActiveChars)
        let prefix = text[..<hardLimit]

        // Prefer the last sentence boundary within the prefix.
        for boundary in [". ", "! ", "? ", "\n"] {
            if let range = prefix.range(of: boundary, options: .backwards) {
                let end = range.upperBound
                return String(text[..<end])
            }
        }
        // Fall back to the last whitespace.
        if let range = prefix.range(of: " ", options: .backwards) {
            return String(text[..<range.lowerBound])
        }
        // Hard character cut.
        return String(prefix)
    }
}
