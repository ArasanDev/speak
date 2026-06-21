// SpeakCore/Paste/StreamingTextInserting.swift
//
// The streaming-paste-seam abstraction (acceleration-plan.md H5).
// A forward-looking companion to `TextInserting` (TextInserting.swift)
// that enables word-by-word delivery as tokens arrive from the cleanup
// layer, rather than waiting for the full cleaned string.
//
// Status: PROTOCOL ONLY — no conformer exists yet.
// The concrete implementation (`PasteboardWriter` or a new sibling) and
// the `CaptureSession` wiring are deferred to the H5-impl task. This
// file is additive: nothing in the existing paste seam changes behaviour.
//
// Design rationale (acceleration-plan.md §H5):
//   `TextInserting.insert(_:)` receives the complete text after cleanup.
//   Streaming cleanup (Foundation Models token-by-token output) produces
//   partial strings at a sub-sentence cadence. `StreamingTextInserting`
//   exposes two hooks — `insertChunk` for each token and `finalize` at
//   the end — so a conformer can stream text into the frontmost app
//   incrementally without coupling the engine to a specific delivery
//   strategy (replace-in-place, append, etc.).
//
// Thread safety: `Sendable` for the same reason as `TextInserting` —
// session actors store and call the inserter across suspension points.
//
// Hard rule: conformers WRITE to the pasteboard and simulate Cmd+V.
// They NEVER read the pasteboard (AGENTS.md §2.6, architecture §13).

import Foundation

/// A streaming counterpart to `TextInserting` for word-by-word paste delivery.
///
/// Whereas `TextInserting.insert(_:)` receives the complete final text in one
/// call, `StreamingTextInserting` splits delivery into two phases:
///
/// 1. **Chunk phase** — `insertChunk(_:)` is called once per token (or word
///    group) as the cleanup layer produces output. The conformer decides how to
///    accumulate and deliver each chunk (e.g., replace-in-place, append).
/// 2. **Finalize phase** — `finalize()` is called once after all chunks have
///    been delivered. The conformer flushes any remaining buffer, cleans up
///    transient state, and leaves the target app in its final state.
///
/// Callers must call `finalize()` exactly once, after the last `insertChunk(_:)`
/// call, even if no chunks were delivered (empty transcript). A conformer may
/// throw from either method; callers should handle errors the same way they
/// handle `TextInserting` errors (surface as `SpeakError.pasteboardBusy` or a
/// new streaming-specific case — decided at implementation time).
///
/// Thread safety: `Sendable` so session actors can store and call the inserter
/// across `await` suspension points without isolation warnings.
///
/// - Note: This protocol is the **forward seam** for streaming paste
///   (acceleration-plan.md H5). No conformer or `CaptureSession` wiring exists
///   yet; those land in the H5-impl task. The protocol is declared now so
///   downstream compile-only references can be added without touching the
///   existing `TextInserting` seam.
public protocol StreamingTextInserting: Sendable {

    /// Deliver one chunk of text to the target application.
    ///
    /// Called once per token (or word group) as the cleanup layer produces
    /// streaming output. Multiple calls accumulate into the final inserted text.
    ///
    /// - Parameter text: A partial string — typically a word or short phrase.
    ///   May be empty (conformers should no-op silently on empty input).
    /// - Throws: Any error that prevents delivery of this chunk. The caller
    ///   should abort streaming and not call `finalize()` if this throws.
    func insertChunk(_ text: String) async throws

    /// Signal end-of-stream and flush any remaining state.
    ///
    /// Called exactly once, after all `insertChunk(_:)` calls are complete.
    /// Must be called even when no chunks were delivered (empty transcript) so
    /// the conformer can release transient resources.
    ///
    /// - Throws: Any error that prevents the final flush or cleanup.
    func finalize() async throws
}
