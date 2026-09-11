// SpeakCore/Overlay/OverlayTextFlow.swift
//
// The 3-line FIFO window for the listening overlay.
//
// Speech always appends (newest at the end). When the window fills past
// `maxWindowChars` (~3 lines), the OLDEST text leaves first so the visible
// window keeps the freshest words. Outbound chunks are available to callers
// but the product currently discards them (no second panel).
//
// Feed contract: `ingest` takes a FULL display snapshot of the entire transcript
// so far (matching `OverlayTextAccumulator`), NOT a delta.

import Foundation

/// One chunk of text that has flowed OUT of the 3-line window onto the desktop.
public struct FlowedChunk: Sendable, Equatable, Identifiable {
    public let id: UUID
    /// The text that left the window (the oldest words — FIFO).
    public let text: String

    public init(id: UUID = UUID(), text: String) {
        self.id = id
        self.text = text
    }
}

/// The FIFO-out text flow state machine.
///
/// Mirrors `FilmstripCutter`'s role but for the alternate choreography (used when
/// filmstrip is off): instead of cutting miniaturized blocks, it pushes the oldest
/// text out of a fixed window and reports each outflow as a `FlowedChunk`.
public struct OverlayTextFlow: Sendable, Equatable {
    /// The live text currently in the 3-line window (the capture anchor).
    public private(set) var windowText: String = ""

    /// The chunks that have flowed out, newest last. The desktop stream renders
    /// these (fading upward); they are the "outward text" the user described.
    public private(set) var flowedChunks: [FlowedChunk] = []

    /// Maximum characters the window holds before text flows out.
    /// ~220 chars ≈ 4–5 lines at 9.5pt mono in the center lane of the 520pt panel.
    public var maxWindowChars: Int

    public init(maxWindowChars: Int = 220) {
        self.maxWindowChars = maxWindowChars
    }

    /// The text that has flowed out, joined — the full "outward" transcript so far.
    public var flowedText: String {
        flowedChunks.map(\.text).joined()
    }

    /// Feed the current FULL transcript snapshot. Already-flowed text is treated as
    /// a committed prefix; only the uncaptured suffix is the active window.
    /// Flushes oldest units until the window fits `maxWindowChars` (≈ 3 lines).
    ///
    /// - Returns: the chunk(s) that flowed out this call, or empty if still in budget.
    @discardableResult
    public mutating func ingest(_ snapshot: String) -> [FlowedChunk] {
        let alreadyFlowed = flowedText
        let active: String
        if snapshot.hasPrefix(alreadyFlowed) {
            active = String(snapshot.dropFirst(alreadyFlowed.count))
        } else {
            // Retraction / restart — drop flowed history and treat the whole
            // snapshot as the active window.
            flowedChunks = []
            active = snapshot
        }

        guard active.count > maxWindowChars else {
            windowText = active
            return []
        }

        // Over budget: keep flushing oldest units until the window fits.
        var buffer = active
        var newlyFlowed: [FlowedChunk] = []
        while buffer.count > maxWindowChars {
            let chunk = takeOldestChunk(from: &buffer)
            // Hard-cut safety: if a chunk didn't shrink the buffer, stop.
            if chunk.text.isEmpty { break }
            flowedChunks.append(chunk)
            newlyFlowed.append(chunk)
        }
        windowText = buffer
        return newlyFlowed
    }

    /// Reset the flow for a new dictation.
    public mutating func reset() {
        windowText = ""
        flowedChunks = []
    }

    /// Split the OLDEST sentence-ish unit off the front of `buffer` as a flowed
    /// chunk. Prefers the first sentence boundary, else the first whitespace, else
    /// a hard cut. Whitespace cuts include the space (`upperBound`) so the remainder
    /// never starts with a leading space that would produce an empty next cut.
    private mutating func takeOldestChunk(from buffer: inout String) -> FlowedChunk {
        var cutEnd: String.Index?
        for boundary in [". ", "! ", "? ", "\n"] {
            if let range = buffer.range(of: boundary) {
                cutEnd = range.upperBound
                break
            }
        }
        if cutEnd == nil {
            if let range = buffer.range(of: " ") {
                cutEnd = range.upperBound  // include the space — leave no leading space
            }
        }

        let end = cutEnd ?? buffer.index(buffer.startIndex, offsetBy: min(maxWindowChars, buffer.count))
        // Guard against a no-progress cut (e.g. empty buffer edge).
        let safeEnd = end > buffer.startIndex ? end : buffer.index(after: buffer.startIndex)
        let chunk = String(buffer[..<safeEnd])
        buffer = String(buffer[safeEnd...])
        return FlowedChunk(text: chunk)
    }
}
