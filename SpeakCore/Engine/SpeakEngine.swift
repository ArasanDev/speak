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
//   This implementation diverges in one deliberate way:
//
//   (1) `init` is not `throws` — none of the injected components require throwing
//       initialisation in v0. `throws` in §6 may have anticipated an eager setup
//       call (e.g., DB open); `HistoryStore.init(databaseURL:)` is non-throwing
//       (errors surface on the first `async throws` DB call, per the SQLite actor
//       design in Storage/HistoryStore.swift). Removing `throws` makes call-sites
//       cleaner without losing correctness.
//
//   `SettingsStore` IS now injected (P10 deliverable — see below). The cleanup
//   toggle is read at `newSession()` time so each dictation reflects the current
//   setting without requiring an engine restart.
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

    /// Optional snippet store. Read at `newSession()` time (like settings) so a snippet
    /// edit applies to the next dictation without an engine restart. `nil` = no snippets.
    private let snippetStore: SnippetStore?

    /// The settings store. Read at `newSession()` time so both the cleanup toggle
    /// and the transcription locale take effect on the next dictation without
    /// requiring an engine restart. `@unchecked Sendable` on `SettingsStore` makes
    /// this actor-safe.
    private let settings: SettingsStore

    // MARK: - Session state (actor-isolated)

    /// The in-flight dictation session. `nil` when idle.
    private var currentSession: CaptureSession?

    /// Hardware-mute state (SPEC §7.4 / product.md §8 #4). When `true`,
    /// `beginDictation` refuses to start a session — so no `CaptureSession` and
    /// no audio capture is ever constructed. This is the bypass-proof enforcement
    /// point for the privacy guarantee ("when muted, no audio is read"): the gate
    /// lives in the one place that starts capture, not in the UI layer that could
    /// be circumvented. Actor-isolated so reads/writes are data-race-free.
    private var muted: Bool = false

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
    ///   - settings: The `SettingsStore` whose `cleanupEnabled`, `language`, and
    ///     `cleanupStyle`/`cleanupLevel` are all read at each `newSession()` call.
    ///     The cleanup toggle, transcription locale, and neat-writing mode apply
    ///     per-dictation — no restart required. Inject a test `SettingsStore` in
    ///     tests to control behavior. [decision Wave B: cleanup mode is no longer
    ///     baked at init — it is derived from settings at call time, mirroring the
    ///     H1 locale migration.]
    public init(transcriber: any Transcribing,
                cleaner: (any LLMCleaning)? = nil,
                inserter: (any TextInserting)? = nil,
                history: any HistoryStoring,
                settings: SettingsStore,
                snippetStore: SnippetStore? = nil) {
        self.transcriber = transcriber
        self.cleaner = cleaner
        self.inserter = inserter
        self.history = history
        self.settings = settings
        self.snippetStore = snippetStore
    }

    // MARK: - Session factory

    /// Create and return a new `CaptureSession` wired with the engine's
    /// transcriber, cleaner, and inserter — reading the cleanup toggle, the
    /// transcription locale, and the neat-writing mode (style + level) from
    /// `settings` at call time.
    ///
    /// **Cleanup gating** (`settings.cleanupEnabled`):
    /// - `true` → the injected `cleaner` is passed (cleanup runs).
    /// - `false` → `nil` is passed (raw transcript delivered, no LLM pass).
    ///
    /// **Locale** (`settings.language`):
    /// Read at call time so a language change in Settings takes effect on the
    /// **next** dictation without requiring an engine restart. The default in
    /// `SettingsStore` is `en-US`, preserving the prior behavior. [decision H1]
    ///
    /// Both reads are synchronous: `SettingsStore` is `@unchecked Sendable` and
    /// its properties are computed over `UserDefaults` (documented thread-safe),
    /// so both reads are actor-safe with no `await`.
    ///
    /// The engine retains the session as `currentSession`. Calling this
    /// again before the prior session is terminal replaces the reference
    /// (the prior session should have been stopped or cancelled first).
    @discardableResult
    public func newSession() -> CaptureSession {
        // Read both the cleanup toggle and the locale from settings at call time
        // (SettingsStore is @unchecked Sendable — actor read is safe).
        // W4.1: CleanupLevel.none short-circuits cleanup regardless of cleanupEnabled.
        // This means `.none` is semantically "no AI, always" — the user-facing moat
        // feature that shows raw text. Distinct from cleanupEnabled==false (the legacy
        // boolean toggle). When level==.none, we log it clearly so diagnostics distinguish
        // "turned cleanup off" from "model unavailable". [decision W4.1]
        let cleanupLevelIsNone = settings.cleanupLevel == .none
        if cleanupLevelIsNone {
            SpeakLog.engine.info("SpeakEngine: cleanupLevel=.none — skipping cleanup, raw transcript will be used.")
        }
        let activeCleaner: (any LLMCleaning)? = (settings.cleanupEnabled && !cleanupLevelIsNone) ? cleaner : nil
        let activeLocale: Locale = settings.language
        // Wave B / Wave 2.2: derive the neat-writing mode from settings at call time
        // (H1 pattern) so any Style-pane or Dictionary-pane change applies on the next
        // dictation with no engine restart. `customVocabulary` is read here alongside
        // style/level — it rides inside the mode enum so the stateless `LLMCleaning`
        // cleaner sees it without needing its own SettingsStore reference. [decision Wave 2.2]
        let activeVocabulary: [String] = settings.customVocabulary
        let activeMode: CleanupMode = .styled(settings.cleanupStyle,
                                               settings.cleanupLevel,
                                               customVocabulary: activeVocabulary)
        // Wave B: build a snippet expander from the current snippets at call time, so a
        // snippet edit applies on the next dictation. nil store → nil expander → no change.
        let activeExpander: (any SnippetExpanding)? = snippetStore.map { $0.makeExpander() }

        let session = CaptureSession(
            transcriber: transcriber,
            cleaner: activeCleaner,
            inserter: inserter,
            locale: activeLocale,
            cleanupMode: activeMode,
            expander: activeExpander
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
        // Hardware-mute gate (SPEC §7.4). Refuse before any session/capture is
        // created so the "no audio is read when muted" guarantee holds at the
        // only place that could start the microphone. Throws a dedicated refusal
        // the app shell treats as "stay idle", not as an error.
        guard !muted else {
            SpeakLog.engine.info("SpeakEngine: beginDictation refused — microphone is muted.")
            throw SpeakError.microphoneMuted
        }
        let session = newSession()
        SpeakLog.engine.info("SpeakEngine: beginDictation — starting new session.")
        try await session.start()
    }

    // MARK: - Hardware mute (SPEC §7.4)

    /// Whether capture is currently muted. When `true`, `beginDictation` refuses.
    public var isMuted: Bool {
        muted
    }

    /// Set the mute state explicitly. Muting also **stops any in-flight capture**
    /// (SPEC §7.4 — "a chord toggles capture; when muted, no audio is read"): a
    /// mute that only blocked *starting* a session would still read audio from a
    /// dictation already running. `cancelDictation()` is a safe no-op when idle.
    public func setMuted(_ newValue: Bool) async {
        muted = newValue
        SpeakLog.engine.info("SpeakEngine: mute set to \(newValue, privacy: .public).")
        if newValue {
            await cancelDictation()
        }
    }

    /// Toggle the mute state and return the new value. When the result is muted,
    /// stops any in-flight capture (see `setMuted`).
    @discardableResult
    public func toggleMute() async -> Bool {
        muted.toggle()
        let nowMuted = muted
        SpeakLog.engine.info("SpeakEngine: mute toggled to \(nowMuted, privacy: .public).")
        if nowMuted {
            await cancelDictation()
        }
        return nowMuted
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
        // Latency fields default to 0 when the result has no LatencyRecord (tests /
        // fixture runs without a live inserter). Pre-P13 rows in the DB also default
        // to 0 via the ALTER TABLE migration. [decision P13: 0 ≡ "no measurement"]
        let entry = HistoryEntry(
            rawText: result.rawText,
            cleanedText: result.cleanedText,
            createdAt: result.createdAt,
            engineId: result.engineId,
            duration: result.duration,
            stopToPasteSeconds: result.latency?.stopToPasteSeconds ?? 0,
            cleanupSeconds: result.latency?.cleanupSeconds ?? 0
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

    // MARK: - W2.1: Live level stream for the HUD waveform

    /// Return the live mic RMS level stream for the current session (for the
    /// overlay HUD waveform — W2.1). Returns `nil` when no session is active
    /// or when the transcriber does not expose its AudioCapture (fixture mode).
    ///
    /// The stream finishes when `stop()` is called on the underlying AudioCapture.
    /// Each emitted value is a linear RMS amplitude in [0, 1]; callers should
    /// apply `levelSmoothed(previous:target:)` before driving bar heights.
    public func currentLevels() async -> AsyncStream<Double>? {
        guard let session = currentSession else { return nil }
        return await session.levels()
    }
}
