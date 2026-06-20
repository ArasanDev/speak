// SpeakCore/Engine/SpeakEngine.swift
//
// Top-level facade for the dictation pipeline (architecture.md §6).
// Assembles the injected components — transcriber, optional cleaner, optional
// inserter, and history store — and provides the three verbs the app shell
// needs: `beginDictation`, `endDictation`, `cancelDictation`.
//
// DESIGN DEVIATION FROM §6 (surfaced, not papered over):
//   §6 shows:
//     public init(transcriber:cleaner:history:settings: SettingsStore) throws
//   This implementation diverges in two deliberate ways:
//
//   (1) `SettingsStore` is not injected — it is a P10 deliverable (not yet built).
//       Pending P10, cleanup on/off is encoded structurally: `cleaner == nil` ↔
//       cleanup off (the existing CaptureSession contract), matching the intent of
//       the `guard settings.cleanupEnabled else { return nil }` factory documented
//       in §10a.1. A typed SettingsStore replaces this at P10.
//
//   (2) `init` is not `throws` — none of the injected components require throwing
//       initialisation in v0. `throws` in §6 may have anticipated an eager setup
//       call (e.g., DB open); `HistoryStore.init(databaseURL:)` is non-throwing
//       (errors surface on the first `async throws` DB call, per the SQLite actor
//       design in Storage/HistoryStore.swift). Removing `throws` makes call-sites
//       cleaner without losing correctness.
//
// CONCURRENCY MODEL (§8 actor vs §6 class contradiction — surfaced):
//   §6 shows `public final class SpeakEngine: @unchecked Sendable`.
//   §8 says "`SpeakEngine` and `CaptureSession` are `actor`s."
//   This implements `actor` to match §8 intent: `currentSession` is mutable state
//   written in `beginDictation` and read in `endDictation`/`cancelDictation`. The
//   actor gives data-race safety for free, with no manual locking. Using
//   `@unchecked Sendable final class` would require an explicit NSLock around
//   `currentSession`, weakening the safety argument. The actor model is the
//   correct call — the §6/§8 discrepancy is flagged for the orchestrator's review.
//
// HISTORY SAVE (best-effort contract):
//   `endDictation` persists via `do/catch`: a save failure is logged via
//   `SpeakLog.engine` and swallowed. The dictation result (and the paste) already
//   succeeded — a failed SQLite write must never surface to the caller as an error.
//   Raw `try?` would discard the error silently; `do/catch` lets us log it.
//
// SIGNATURES match the roadmap P3.5 / P9 / P10 contracts. The app shell
// (P11+) calls `beginDictation` on hotkey-start and `endDictation` on
// hotkey-stop; `cancelDictation` is called on hotkey-cancel / quit.

import Foundation
import os

/// The top-level dictation facade. One `SpeakEngine` lives for the app lifetime;
/// each dictation gets a fresh `CaptureSession` via `beginDictation`.
///
/// **Architecture §6 / §8 note:** implemented as an `actor` (§8 is explicit:
/// "`SpeakEngine` and `CaptureSession` are actors"); §6 shows a `@unchecked
/// Sendable final class` — the discrepancy is flagged for the orchestrator.
public actor SpeakEngine {

    // MARK: - Configuration (immutable post-init)

    private let transcriber: any Transcribing
    private let cleaner: (any LLMCleaning)?
    private let inserter: (any TextInserting)?
    private let history: any HistoryStoring
    private let locale: Locale
    private let cleanupMode: CleanupMode

    // MARK: - Session state (actor-isolated)

    /// The in-flight dictation session. `nil` when idle.
    private var currentSession: CaptureSession?

    // MARK: - Init

    /// Create a `SpeakEngine` wired with the given components.
    ///
    /// - Parameters:
    ///   - transcriber: The STT engine. `AppleSpeechTranscriber()` is the v0 default.
    ///   - cleaner: `nil` (default) disables AI cleanup — the session delivers raw
    ///     transcript. Non-nil enables the cleanup pass (`FoundationModelsCleaner()`
    ///     is the v0 default). If the cleaner's `isAvailable` returns `false` at
    ///     runtime, the session falls back to raw text and still reaches `.done`
    ///     (never `.error`). **P10 deviation:** in §6, the `SettingsStore` param
    ///     encodes cleanup on/off; here `cleaner == nil` encodes it structurally.
    ///     `SettingsStore` injection arrives at P10.
    ///   - inserter: `nil` (default) leaves paste as the caller's responsibility
    ///     (test/CLI mode). `PasteboardWriter()` is injected by the app shell for
    ///     live paste (write-never-read, hard constraint §2).
    ///   - history: Persistence store for completed dictations. Injected so tests
    ///     can substitute an in-memory or temp-file store.
    ///   - locale: Transcription locale. Defaults to `en-US`.
    ///   - cleanupMode: The LLM cleanup mode passed to the cleaner. Defaults to
    ///     `.punctuation` (the most common use-case).
    public init(transcriber: any Transcribing,
                cleaner: (any LLMCleaning)? = nil,
                inserter: (any TextInserting)? = nil,
                history: any HistoryStoring,
                locale: Locale = Locale(identifier: "en-US"),
                cleanupMode: CleanupMode = .punctuation) {
        self.transcriber = transcriber
        self.cleaner = cleaner
        self.inserter = inserter
        self.history = history
        self.locale = locale
        self.cleanupMode = cleanupMode
    }

    // MARK: - Session factory

    /// Create and return a new `CaptureSession` wired with the engine's
    /// transcriber, cleaner, inserter, locale, and cleanupMode.
    ///
    /// The engine retains the session as `currentSession`. Calling this
    /// again before the prior session is terminal replaces the reference
    /// (the prior session should have been stopped or cancelled first).
    @discardableResult
    public func newSession() -> CaptureSession {
        let session = CaptureSession(
            transcriber: transcriber,
            cleaner: cleaner,
            inserter: inserter,
            locale: locale,
            cleanupMode: cleanupMode
        )
        currentSession = session
        return session
    }

    // MARK: - Dictation verbs (the three the app shell drives)

    /// Begin a dictation. Creates a fresh session, starts it, and tracks it
    /// as the current session.
    ///
    /// Throws `SpeakError` if the new session cannot start (e.g., permission
    /// denied, STT unavailable).
    ///
    /// **Note:** `async throws` is required because `CaptureSession.start()` is
    /// `async throws` (it initiates the STT stream). §6's non-async `throws`
    /// signature is a primary-source contradiction — surfaced, not papered over.
    public func beginDictation() async throws {
        let session = newSession()
        SpeakLog.engine.info("SpeakEngine: beginDictation — starting new session.")
        try await session.start()
    }

    /// End the current dictation.
    ///
    /// Drives the session through `processing` to `done`:
    /// 1. `session.stop()` — finalizes the STT stream, runs cleanup (if enabled),
    ///    and triggers paste (if an `inserter` was injected). Returns the
    ///    `TranscriptionResult`. The paste delivery is the session's responsibility;
    ///    if paste throws, the session errors and that error propagates here.
    /// 2. History save (best-effort) — builds a `HistoryEntry` from the result and
    ///    calls `history.save(_:)`. **A save failure is logged and swallowed**:
    ///    the dictation already succeeded (text was pasted); a SQLite write failure
    ///    must never be surfaced to the caller as a dictation error.
    ///
    /// Returns the `TranscriptionResult` regardless of history-save outcome.
    /// Throws `SpeakError` if no session is in flight, or if the session's stop
    /// or paste step fails.
    public func endDictation() async throws -> TranscriptionResult {
        guard let session = currentSession else {
            throw SpeakError.unknown("SpeakEngine.endDictation() called with no active session.")
        }
        SpeakLog.engine.info("SpeakEngine: endDictation — stopping session.")
        let result = try await session.stop()

        // History save — best-effort. Never propagate a save failure.
        let entry = HistoryEntry(
            rawText: result.rawText,
            cleanedText: result.cleanedText,
            createdAt: result.createdAt,
            engineId: result.engineId
        )
        do {
            try await history.save(entry)
            SpeakLog.engine.info("SpeakEngine: history entry saved (\(entry.id, privacy: .public)).")
        } catch {
            // Log and swallow — the dictation succeeded; a persistence failure is
            // non-fatal. The caller receives the result regardless.
            SpeakLog.engine.error(
                "SpeakEngine: history save failed (swallowed) — \(error.localizedDescription, privacy: .public)"
            )
        }

        currentSession = nil
        return result
    }

    /// Hard-cancel the current dictation. Safe to call if no session is in flight.
    public func cancelDictation() async {
        guard let session = currentSession else {
            SpeakLog.engine.info("SpeakEngine: cancelDictation() — no session in flight, no-op.")
            return
        }
        SpeakLog.engine.info("SpeakEngine: cancelDictation — cancelling session.")
        await session.cancel()
        currentSession = nil
    }

    // MARK: - State observation

    /// Current state of the in-flight session, or `.idle` when no session exists.
    public var currentState: CaptureSession.State {
        get async {
            guard let session = currentSession else { return .idle }
            return await session.currentState
        }
    }

    /// Return a partials stream for the current session (for the overlay / menubar
    /// icon in P4/P8). Returns `nil` when no session is active.
    ///
    /// The stream finishes when the session terminates. The caller owns the
    /// `AsyncStream` returned; calling this again replaces the prior consumer
    /// (single-consumer contract — see `CaptureSession.partials()`).
    public func currentPartials() async -> AsyncStream<TranscriptChunk>? {
        guard let session = currentSession else { return nil }
        return await session.partials()
    }
}
