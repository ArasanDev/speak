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

import AVFoundation
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

    // [lint] `transcriber`/`cleaner`/`snippetStore`/`settings` are internal (not
    // `private`) so the auxiliary-session verbs in `SpeakEngine+Auxiliary.swift`
    // can mint sessions with the same wiring — module-internal only, still not
    // public API.
    let transcriber: any Transcribing
    let cleaner: (any LLMCleaning)?
    private let inserter: (any TextInserting)?
    private let history: any HistoryStoring

    /// Optional snippet store. Read at `newSession()` time (like settings) so a snippet
    /// edit applies to the next dictation without an engine restart. `nil` = no snippets.
    let snippetStore: SnippetStore?

    /// Optional profile store (PE-2). Read at `newSession()` time so a profile edited in
    /// AI Studio applies on the next dictation. `nil` → fall back to the hardcoded
    /// `DefaultProfiles` (the PE-1 behavior), keeping every existing test green.
    private let profileStore: ProfileStore?

    /// The settings store. Read at `newSession()` time so both the cleanup toggle
    /// and the transcription locale take effect on the next dictation without
    /// requiring an engine restart. `@unchecked Sendable` on `SettingsStore` makes
    /// this actor-safe.
    let settings: SettingsStore

    /// [H-1] Optional Voice Actions executor (specs/horizon-voice-os.md, Pillar 1).
    /// `ShortcutsCLIExecutor()` in production (injected by the app shell); `nil` in
    /// tests/CLI. When `nil`, the `.action` route always degrades to dictation (the
    /// coordinator's own contract). All-SpeakCore protocol — keeps the engine
    /// AppKit-free, same as `transcriber`/`cleaner`/`inserter`.
    private let voiceActionsExecutor: (any ActionExecuting)?

    /// [H-1] Optional Voice Actions command service — routes a `.command` utterance
    /// through the on-device selection transform. Wired in production
    /// (`DictationController.init`) with the App-layer `AccessibilitySelection` AX
    /// conformer, the same one the pre-H-1 Command Mode feature already uses. `nil`
    /// only when cleanup is disabled (no cleaner to inject), in which case `.command`
    /// degrades to dictation, same as `voiceActionsExecutor == nil`. The live AX
    /// read/replace I/O remains `[deferred — human verification]`; the DI wiring and
    /// routing logic are unit-tested. Injectable so tests exercise the route directly.
    private let voiceActionsCommandService: CommandModeService?

    /// Optional closure returning whether microphone permission is granted.
    /// Defaults to `AVCaptureDevice.authorizationStatus(for: .audio) == .authorized`,
    /// or `true` in headless unit test environments (`XCTest`).
    /// Internal (not `private`) so `SpeakEngine+Auxiliary.swift` can enforce the
    /// same auth gate — see the [lint] note on `transcriber` above.
    let isMicrophoneAuthorized: @Sendable () -> Bool

    /// [fix: audit — C2 stop-wedge watchdog] Upper bound on how long
    /// `endDictation` / `endAuxiliarySession` wait for `session.stop()` before
    /// force-cancelling the session so the engine slot is released. Derivation:
    /// the worst-case bounded path inside `stop()` is stream-drain watchdog
    /// (5 s) + voice-actions bound (10 s) + cleanup bound T_cleanup (10 s)
    /// ≈ 25 s; 30 s gives headroom without firing on a valid slow run.
    /// Injectable so tests can shrink it. [decision: 30 s]
    private let processingWatchdog: Duration

    // MARK: - Session state (actor-isolated)

    /// The in-flight dictation session. `nil` when idle.
    /// `private(set)` — read by `SpeakEngine+Auxiliary.swift` for the
    /// single-capture exclusion check; written only in this file.
    private(set) var currentSession: CaptureSession?

    /// The in-flight auxiliary (non-dictation) capture session — Command Mode
    /// instruction capture, the Settings "Test My Voice" sandbox. Minted and
    /// started only by `beginAuxiliarySession`, tracked here so `setMuted(true)`
    /// / `cancelDictation()` reach it and `beginDictation` can refuse to start
    /// a second concurrent capture. `nil` when no aux capture is in flight.
    /// [fix: audit — C1 gate bypass]
    /// Internal (module scope) — the aux verbs live in `SpeakEngine+Auxiliary.swift`.
    var auxiliarySession: CaptureSession?

    /// Hardware-mute state (SPEC §7.4 / product.md §8 #4). When `true`,
    /// `beginDictation` refuses to start a session — so no `CaptureSession` and
    /// no audio capture is ever constructed. This is the bypass-proof enforcement
    /// point for the privacy guarantee ("when muted, no audio is read"): the gate
    /// lives in the one place that starts capture, not in the UI layer that could
    /// be circumvented. Actor-isolated so reads/writes are data-race-free.
    /// `private(set)` — read by `SpeakEngine+Auxiliary.swift`; written only in
    /// `setMuted` below.
    private(set) var muted: Bool = false

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
    ///   - processingWatchdog: Bound on `session.stop()` inside `endDictation` /
    ///     `endAuxiliarySession`; on expiry the session is force-cancelled so the
    ///     engine slot is released. Default 30 s [decision: see property doc].
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
                snippetStore: SnippetStore? = nil,
                profileStore: ProfileStore? = nil,
                voiceActionsExecutor: (any ActionExecuting)? = nil,
                voiceActionsCommandService: CommandModeService? = nil,
                isMicrophoneAuthorized: (@Sendable () -> Bool)? = nil,
                processingWatchdog: Duration = .seconds(30)) {
        self.transcriber = transcriber
        self.cleaner = cleaner
        self.inserter = inserter
        self.history = history
        self.settings = settings
        self.snippetStore = snippetStore
        self.profileStore = profileStore
        self.voiceActionsExecutor = voiceActionsExecutor
        self.voiceActionsCommandService = voiceActionsCommandService
        self.isMicrophoneAuthorized = isMicrophoneAuthorized ?? {
            if NSClassFromString("XCTestCase") != nil {
                return true
            }
            return AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        }
        self.processingWatchdog = processingWatchdog
    }

    // MARK: - Session factory

    /// Create and return a new `CaptureSession` wired with the engine's
    /// transcriber, cleaner, and inserter — reading the cleanup toggle, the
    /// transcription locale, streaming mode, and the neat-writing mode (style + level)
    /// from `settings` at call time.
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
    /// **Streaming mode** (`settings.streamingMode`):
    /// [P0.1 / task #29] Keystroke-injection streaming is retired from the delivery
    /// path in v0. The setting is read for P2 but produces no effect; final AI text is
    /// always pasted as the single deliverable. Raw keystroke injection is not used.
    ///
    /// All reads are synchronous: `SettingsStore` is `@unchecked Sendable` and
    /// its properties are computed over `UserDefaults` (documented thread-safe),
    /// so all reads are actor-safe with no `await`.
    ///
    /// The engine retains the session as `currentSession`. Calling this
    /// again before the prior session is terminal replaces the reference
    /// (the prior session should have been stopped or cancelled first).
    ///
    /// `internal` (not public): this is the raw mint — it builds a session but
    /// runs NO capture gates (mute, TCC, single-capture). Public callers must
    /// use `beginDictation` / `beginAuxiliarySession`, which apply the gates
    /// before/around calling this. Tests keep access through `@testable`.
    /// [fix: audit — C1 gate bypass]
    ///
    /// - Parameter frontmostBundleID: the frontmost app's bundle id at dictation
    ///   start (read on the main actor by the app layer and passed in, so the engine
    ///   stays AppKit-free). When it matches a built-in profile's `targetApps`, that
    ///   profile runs; otherwise the global styled() default applies. `nil` (CLI /
    ///   tests) → default.
    @discardableResult
    func newSession(frontmostBundleID: String? = nil) -> CaptureSession {
        // Read both the cleanup toggle and the locale from settings at call time
        // (SettingsStore is @unchecked Sendable — actor read is safe).
        // W4.1: CleanupLevel.none short-circuits cleanup regardless of cleanupEnabled.
        // This means `.none` is semantically "no AI, always" — the user-facing moat
        // feature that shows raw text. Distinct from cleanupEnabled==false (the legacy
        // boolean toggle). When level==.none, we log it clearly so diagnostics distinguish
        // "turned cleanup off" from "model unavailable". [decision W4.1]
        let cleanupLevelIsNone = settings.cleanupLevel == .none
        if cleanupLevelIsNone { SpeakLog.engine.info("SpeakEngine: cleanupLevel=.none — skipping cleanup, raw transcript will be used.") }
        let activeCleaner: (any LLMCleaning)? = (settings.cleanupEnabled && !cleanupLevelIsNone) ? cleaner : nil
        let activeLocale: Locale = settings.language
        // Wave B / Wave 2.2: derive the neat-writing mode from settings at call time
        // (H1 pattern) so any Style-pane or Dictionary-pane change applies on the next
        // dictation with no engine restart. `customVocabulary` is read here alongside
        // style/level — it rides inside the mode enum so the stateless `LLMCleaning`
        // cleaner sees it without needing its own SettingsStore reference. [decision Wave 2.2]
        let activeVocabulary: [String] = settings.effectiveVocabulary
        // Default/global cleanup path — the user's Style + Level + dictionary. Left
        // unchanged so general dictation behaves exactly as the verified v0 base.
        var activeMode: CleanupMode = .styled(settings.cleanupStyle,
                                              settings.cleanupLevel,
                                              customVocabulary: activeVocabulary)

        // PE-0 wiring: if the frontmost app matches a built-in profile's targetApps
        // (Cursor/VSCode/Xcode/Zed → Code, Terminal/iTerm → CLI, Tower/SublimeMerge →
        // Commit), run THAT profile instead of the global styled() default. The default
        // path stays on .styled for now (zero regression: preserves Style/intensity/
        // vocabulary); the full default→Clean migration lands with AI Studio.
        // [decision: app-override increment — conscious scoping, not fragmentation; the
        //  intensity level + custom vocabulary are threaded through to the profile path.]
        // PE-2: resolve against the user's edited profile set when a ProfileStore is
        // injected; otherwise the hardcoded built-ins (PE-1 behavior). This is what makes
        // an AI Studio edit to e.g. the Code profile actually change Xcode/Cursor dictation.
        // The DEFAULT (no-app-match) path still runs `.styled` below — the default→Clean
        // unification is a deliberate later stage, so the verified v0 default is untouched.
        //
        // V01-3 (per-app context, profile-native): `settings.perAppContextEnabled` gates
        // the frontmost-app read itself, not a separate detector — when the user turns it
        // off, `frontmostBundleID` is discarded here so `ProfileResolver.resolve` always
        // falls through to `nil` → the global default, reproducing the no-app-context
        // baseline exactly regardless of which app was frontmost. [decision V01-3]
        let effectiveFrontmostBundleID = settings.perAppContextEnabled ? frontmostBundleID : nil
        let candidateProfiles = profileStore?.profiles ?? DefaultProfiles.all
        let resolvedProfile = ProfileResolver.resolve(
            frontmostBundleID: effectiveFrontmostBundleID,
            profiles: candidateProfiles,
            default: DefaultProfiles.defaultProfile
        )
        let isAppSpecificMatch = resolvedProfile.id != DefaultProfiles.defaultProfile.id
            && resolvedProfile.model != .raw
        // Only switch to the profile path when cleanup will actually run (cleaner non-nil
        // ⇒ cleanupEnabled && level != .none); otherwise the mode is moot (raw passthrough).
        if isAppSpecificMatch, settings.cleanupEnabled, !cleanupLevelIsNone {
            activeMode = .profile(resolvedProfile,
                                  level: settings.cleanupLevel,
                                  customVocabulary: activeVocabulary)
            SpeakLog.engine.info(
                "SpeakEngine: profile '\(resolvedProfile.name, privacy: .public)' active for frontmost app \(effectiveFrontmostBundleID ?? "none", privacy: .public)."
            )
        }
        // Wave B + acoustic corrections: build the expander chain from the current
        // snippets and corrections table at call time, so an edit applies on the
        // next dictation. nil when neither stage has entries → no change.
        let activeExpander: (any SnippetExpanding)? = defaultExpander(for: settings, snippetStore: snippetStore)

        // [P0.1 / task #29] Keystroke-injection raw streaming is retired as a delivery
        // path: raw is NEVER inserted into the document — the final AI text is the single
        // delivery (see CaptureSession+Paste.runPaste). streamingInserter is always nil.
        // [decision P11-c] Settings.streamingMode is retained for P2 revisit; it is not
        // wired to delivery in v0. The setting can be read but produces no effect.
        let activeStreamingInserter: (any StreamingRawTextInserting)? = nil

        // [PE-3.1] Build a voice-command preprocessor when cleanup will actually run.
        // The preprocessor fires in stop(), between snippet expansion and the LLM pass,
        // so the trigger phrase is stripped before the model sees the text. Manual
        // overrides (chip tap / Raw pick) are set before stop() and checked inside
        // CaptureSession — they always win over a spoken trigger.
        let vcpAgentID = DefaultProfiles.agent.id
        let vcpWriteID = DefaultProfiles.write.id
        let vcpNoteID = DefaultProfiles.note.id
        let vcpProfiles = candidateProfiles
        let vcpLevel = settings.cleanupLevel
        let vcpVocab = activeVocabulary

        var activeVoiceCommandPreprocessor: CaptureSession.VoiceCommandPreprocessor?
        if settings.cleanupEnabled && !cleanupLevelIsNone {
            activeVoiceCommandPreprocessor = { rawText in
                guard let cmd = VoiceCommandParser.detect(
                    rawText,
                    agentProfileID: vcpAgentID,
                    writeProfileID: vcpWriteID,
                    noteProfileID: vcpNoteID
                ) else { return nil }

                let modeOverride: CleanupMode?
                if let destID = cmd.destination {
                    if let profile = vcpProfiles.first(where: { $0.id == destID }) {
                        modeOverride = .profile(profile, level: vcpLevel, customVocabulary: vcpVocab)
                    } else {
                        modeOverride = nil
                    }
                } else if let cat = cmd.category {
                    if let agentProfile = vcpProfiles.first(where: { $0.id == vcpAgentID }) {
                        modeOverride = .profile(agentProfile, level: vcpLevel, category: cat, customVocabulary: vcpVocab)
                    } else {
                        modeOverride = nil
                    }
                } else {
                    modeOverride = nil
                }
                return (transcript: cmd.strippedTranscript, modeOverride: modeOverride)
            }
        }

        // [V01-W] Assemble the cleanup warm-up handler ONLY when cleanup will
        // actually run (same gating as the voice-command preprocessor above).

        // [H-1] Assemble the Voice Actions handler (specs/horizon-voice-os.md, Pillar 1)
        // ONLY when the feature is enabled. When disabled, `nil` is passed so
        // CaptureSession.stop() runs the literal pre-H-1 delivery path (byte-identical
        let activeVoiceActionsHandler = makeVoiceActionsHandler()

        let session = CaptureSession(
            transcriber: transcriber,
            cleaner: activeCleaner,
            inserter: inserter,
            streamingInserter: activeStreamingInserter,
            locale: activeLocale,
            cleanupMode: activeMode,
            expander: activeExpander,
            voiceCommandPreprocessor: activeVoiceCommandPreprocessor,
            voiceActionsHandler: activeVoiceActionsHandler,
            warmUpHandler: makeWarmUpHandler(cleaner: activeCleaner),
            agentPrefix: settings.agentPrefixStyle.prefix,
            agentPrefixStyle: settings.agentPrefixStyle,
            agentPrefixIncludeState: settings.agentPrefixIncludeState
        )
        currentSession = session
        return session
    }

    // MARK: - PE-3 live-panel override

    /// Apply a per-dictation profile + category override to the in-flight session,
    /// chosen by the user in the live panel (specs/live-panel-prompt-shaper.md). Rebuilds
    /// the session's cleanup mode as `.profile(profile, level:, category:, vocab:)` from the
    /// user's current cleanup level + vocabulary, then sets it on the session so the cleanup
    /// pass uses it instead of the mode latched at session start.
    ///
    /// No-op when: there is no in-flight session; cleanup will not run (`cleanupEnabled`
    /// false or level `.none` → raw passthrough, so the override is moot); or `profile` is
    /// the `.raw` base-core bypass (an override must never silence a running cleanup).
    ///
    /// MUST be called BEFORE `endDictation()` so the override is in place before the
    /// session's `.processing`/cleanup pass reads it. Race-free: a single ordered actor
    /// write, not a per-tap call. [decision PE-3.]
    ///
    /// - Parameter customInstructions: (P-Code) free-form text from the coding-
    ///   customization panel, appended as the final instruction clause. Empty by
    ///   default — existing callers (knob-only overrides) are unaffected.
    /// - Parameter level: optional per-dictation cleanup-strength override.
    ///   `nil` keeps the saved `settings.cleanupLevel`. `.none` is NOT accepted
    ///   here — callers route that intent through `applyRawOverride` (the
    ///   session was built with no cleaner when the saved level is `.none`, so
    ///   a per-dictation escalation cannot manufacture cleanup mid-session).
    public func applyProfileOverride(
        _ profile: Profile,
        category: AgentCategory,
        customInstructions: String = "",
        level: CleanupLevel? = nil
    ) async {
        guard let session = currentSession else { return }
        guard settings.cleanupEnabled, settings.cleanupLevel != .none else {
            SpeakLog.engine.info("SpeakEngine: live-panel override ignored — cleanup off / level=.none (raw passthrough).")
            return
        }
        guard profile.model != .raw else {
            SpeakLog.engine.info("SpeakEngine: live-panel override ignored — Raw is the AI-off base core, not an override target.")
            return
        }
        let mode = CleanupMode.profile(
            profile,
            level: level ?? settings.cleanupLevel,
            category: category,
            customVocabulary: settings.effectiveVocabulary,
            customInstructions: customInstructions
        )
        await session.setOverrideCleanupMode(mode)
        SpeakLog.engine.info(
            "SpeakEngine: live-panel override — profile '\(profile.name, privacy: .public)' category '\(category.rawValue, privacy: .public)'."
        )
    }

    /// Apply a per-dictation **Raw** override (the user picked Raw in the live panel): skip
    /// cleanup for the in-flight session and paste the raw transcript. No-op when no session.
    /// Like `applyProfileOverride`, called once at stop, before `endDictation()`. [decision PE-3.]
    public func applyRawOverride() async {
        guard let session = currentSession else { return }
        await session.forceRawForThisSession()
        SpeakLog.engine.info("SpeakEngine: live-panel Raw override — this dictation will paste raw.")
    }

    /// Mark the active session as an Agent Bridge response. The transcript is
    /// returned through MCP and must not be pasted into the focused application.
    public func suppressPasteForAgentResponse() async {
        guard let session = currentSession else { return }
        await session.suppressPasteForAgentResponse()
        SpeakLog.agentBridge.info("SpeakEngine: agent response will not paste into the focused app.")
    }

    /// Set or update the agent prefix for the active session.
    public func setAgentPrefix(_ prefix: String) async {
        guard let session = currentSession else { return }
        await session.setAgentPrefix(prefix)
    }

    /// Set or update the agent prefix style and state inclusion for the active session.
    public func setAgentPrefix(style: AgentPrefixStyle, includeState: Bool) async {
        guard let session = currentSession else { return }
        await session.setAgentPrefix(style: style, includeState: includeState)
    }

    // MARK: - Profile preview (PE-2: AI Studio live-test box; reused by #40 eval harness)

    /// The outcome of previewing a profile over a sample — distinguishes "the model is
    /// unavailable" (so the caller never silently shows output == input) from a real
    /// transform, a `.raw` passthrough, or a failure.
    public enum ProfilePreviewResult: Sendable, Equatable {
        /// No cleaner injected, or the engine reports `isAvailable == false` (e.g. Apple
        /// Intelligence is off). The caller should say so, not render the unchanged input.
        case unavailable
        /// The profile is the base-core bypass (`model == .raw`): output equals input by design.
        case raw
        /// The model produced this output.
        case transformed(String)
        /// `clean(_:mode:)` threw. The string is a diagnostic message, not user-facing prose.
        case failed(String)
    }

    /// Run `profile` over `sample` through the real cleaner — the same path live dictation
    /// uses — so AI Studio (and the #40 eval harness) can show what a profile produces.
    /// Pure read of the engine's components; does NOT touch the dictation session state.
    ///
    /// - Note: On a Mac with Apple Intelligence off, `isAvailable` is `false` → `.unavailable`.
    ///   This is why the result is an enum: a preview must never present the raw input as
    ///   though the model transformed it.
    public func preview(profile: Profile, sample: String) async -> ProfilePreviewResult {
        if case .raw = profile.model { return .raw }
        guard let cleaner else { return .unavailable }
        guard await cleaner.isAvailable else { return .unavailable }
        // Use the user's intensity, but never `.none` for a preview (that means "no model
        // call" in live dictation; here the user explicitly asked to see the transform).
        let level: CleanupLevel = settings.cleanupLevel == .none ? .medium : settings.cleanupLevel
        let mode: CleanupMode = .profile(profile, level: level, customVocabulary: settings.effectiveVocabulary)
        do {
            return .transformed(try await cleaner.clean(sample, mode: mode))
        } catch {
            SpeakLog.engine.error("SpeakEngine.preview: clean failed — \(String(describing: error), privacy: .public)")
            return .failed(String(describing: error))
        }
    }

    // MARK: - PE-4: re-clean + paste

    /// Re-run AI cleanup on `rawTranscript` with the given profile + category and paste
    /// the result. Used by `DictationController.recleanCurrentTranscript()`. [decision PE-4]
    ///
    /// Silent no-ops (logged) when: the cleaner is absent or unavailable; cleanup is
    /// disabled or level is `.none`; the profile is the `.raw` base-core bypass.
    /// Throws only from the actual `clean()` or `insert()` calls.
    public func recleanAndPaste(
        _ rawTranscript: String,
        profile: Profile,
        category: AgentCategory,
        customInstructions: String = "",
        level: CleanupLevel? = nil
    ) async throws {
        guard profile.model != .raw else {
            SpeakLog.engine.info("SpeakEngine: reclean skipped — profile is Raw (no model).")
            return
        }
        guard settings.cleanupEnabled, settings.cleanupLevel != .none else {
            SpeakLog.engine.info("SpeakEngine: reclean skipped — cleanup disabled or level=.none.")
            return
        }
        guard let cleaner, await cleaner.isAvailable else {
            SpeakLog.engine.info("SpeakEngine: reclean skipped — cleaner unavailable.")
            return
        }
        guard let inserter else {
            SpeakLog.engine.info("SpeakEngine: reclean skipped — no inserter configured.")
            return
        }
        let mode: CleanupMode = .profile(
            profile,
            level: level ?? settings.cleanupLevel,
            category: category,
            customVocabulary: settings.effectiveVocabulary,
            customInstructions: customInstructions
        )
        let cleaned = try await cleaner.clean(rawTranscript, mode: mode)
        try await inserter.insert(cleaned)
        SpeakLog.engine.info(
            "SpeakEngine: reclean — pasted \(cleaned.count, privacy: .public) chars."
        )
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
    /// - Parameter frontmostBundleID: the frontmost app's bundle id at dictation
    ///   start, forwarded to `newSession()` for profile resolution. Read by the app
    ///   layer (@MainActor) so the engine stays AppKit-free. `nil` (CLI) → default.
    /// - Returns: `true` when this call actually started a new session; `false`
    ///   when the [A3] re-entrancy guard no-op'd because a session was already in
    ///   flight. [decision: AVB-5 follow-up] Making the collision observable (as a
    ///   return value, not a throw, so [Engine-L1]'s deliberate silent-no-op stays
    ///   intact for the hotkey path) closes a check-then-act race: a caller that
    ///   only checked `currentSession == nil` before calling this, then blindly
    ///   assumed `.listening`/ownership after the `await` returned, could believe
    ///   it owns a session that actually belongs to whichever caller won the race
    ///   — and later read the other caller's `lastTranscript`. Callers that need
    ///   ownership guarantees (`DictationController.beginDictation`,
    ///   `cliRequestInput`) must check this return value before touching any
    ///   session-owned state.
    @discardableResult
    public func beginDictation(frontmostBundleID: String? = nil) async throws -> Bool {
        // Hardware-mute gate (SPEC §7.4). Refuse before any session/capture is
        // created so the "no audio is read when muted" guarantee holds at the
        // only place that could start the microphone. Throws a dedicated refusal
        // the app shell treats as "stay idle", not as an error.
        guard !muted else {
            SpeakLog.engine.info("SpeakEngine: beginDictation refused — microphone is muted.")
            throw SpeakError.microphoneMuted
        }
        // If microphone permission has not yet been determined, trigger the system prompt
        // so the user is asked for access rather than failing immediately.
        if AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined {
            _ = await AVCaptureDevice.requestAccess(for: .audio)
        }
        // Mic-permission gate: without this, a denied/revoked TCC grant lets
        // AVAudioEngine.start() succeed while CoreAudio silently feeds zeroed
        // buffers — a session that runs to .done with an empty transcript and
        // no error anywhere. Checked here, the one place that starts capture.
        guard isMicrophoneAuthorized() else {
            SpeakLog.engine.info("SpeakEngine: beginDictation refused — microphone not authorized.")
            throw SpeakError.microphoneDenied
        }
        // [A3] Re-entrancy guard: SpeakEngine is a bare actor (NOT @MainActor).
        // A second beginDictation() call entering during the `await session.start()`
        // suspension below would call newSession(), which overwrites currentSession
        // and orphans the first session's live streamTask indefinitely. Guard at the
        // only place that creates sessions so the first session runs to completion
        // (or cancel) before a second can be started. The caller (DictationController)
        // already serialises through the hotkey debouncer, but the CLI path has no
        // such gate — this is the bypass-proof enforcement point. [decision A3]
        if currentSession != nil {
            guard await releaseCurrentSessionIfTerminal() else {
                SpeakLog.engine.info("SpeakEngine: beginDictation refused — a session is already in flight.")
                // [Engine-L1] Return (not throw) is intentional: DictationController's hotkey
                // debouncer is the primary re-entrancy gate; this is defence-in-depth only.
                // The CLI path does not have a debouncer, but a rapid double-tap there is
                // a user error, not an exceptional condition worth surfacing as an error.
                return false
            }
        }
        // [fix: audit — C1] Single-capture exclusion spans BOTH session kinds:
        // an auxiliary capture (command mode / sandbox) owns the shared
        // transcriber's microphone, so a dictation starting alongside it would
        // run two captures on one device. Refuse (same silent-no-op semantics
        // as the [A3] guard above); a terminal aux session is released.
        if let aux = auxiliarySession {
            guard await aux.isTerminal else {
                SpeakLog.engine.info("SpeakEngine: beginDictation refused — auxiliary capture in flight.")
                return false
            }
            auxiliarySession = nil
        }
        // Apply the persisted mic pin (Settings → Microphone) at session start.
        // `nil` follows the system default; an unplugged preferred device
        // resolves to default inside CoreAudioDeviceMonitor — never an error
        // here. [decision: pinned-device selection]
        setPreferredInputDeviceUID(settings.preferredInputDeviceUID)

        let session = newSession(frontmostBundleID: frontmostBundleID)
        // [fix: audit — mute TOCTOU] The TCC prompt and the terminal-release
        // awaits above can suspend long enough for a mute to land. Re-check at
        // the last moment before opening the mic so the "muted ⇒ no audio is
        // read" guarantee has no check-then-act window.
        guard !muted else {
            SpeakLog.engine.info("SpeakEngine: beginDictation refused — muted during start.")
            if currentSession === session {
                currentSession = nil
            }
            throw SpeakError.microphoneMuted
        }
        SpeakLog.engine.info("SpeakEngine: beginDictation — starting new session.")
        // [Engine-L2] If session.start() throws (e.g., mic permission denied), clear
        // currentSession so the A3 re-entrancy guard doesn't permanently block the
        // next dictation attempt. Identity-guarded: only clear if currentSession is
        // still THIS session — a concurrent cancel/begin interleave must not let a
        // stale catch release a newer session. [fix: audit — session clobber]
        do {
            try await session.start()
        } catch {
            if currentSession === session {
                currentSession = nil
            }
            throw error
        }
        return true
    }

    /// Applies a mic preference to the live capture when the transcriber
    /// exposes one (`AudioCaptureProviding`). Setting mid-session re-resolves
    /// the effective device and rebuilds the tap if it actually differs — see
    /// `AudioCapture.preferredInputDeviceUID`. No-op for fixture/mock
    /// producers that don't own a real `AudioCapture`.
    ///
    /// `nonisolated`: touches only the immutable `transcriber` — the property
    /// setter on `AudioCapture` is itself lock-guarded + stateQueue-dispatched,
    /// so callers (MainActor Settings observers, this actor's beginDictation)
    /// don't need an await for a fire-and-forget apply.
    public nonisolated func setPreferredInputDeviceUID(_ uid: String?) {
        (transcriber as? AudioCaptureProviding)?.audioCapture?.preferredInputDeviceUID = uid
    }

    /// [fix: wedge] Self-healing A3 release: when `currentSession` has reached a
    /// terminal state on its own (e.g. capture teardown threw
    /// `captureInterrupted` into the stream mid-listen → `.error` via
    /// `failStream`, ending the session without an explicit endDictation), the
    /// dead reference must not wedge the re-entrancy guard forever. Clears it
    /// and returns `true` so the new begin can proceed. Returns `false` when a
    /// live session is still in flight (the normal A3 refusal path) and `true`
    /// when no session exists.
    /// Internal (not `private`) — called by `beginAuxiliarySession` in
    /// `SpeakEngine+Auxiliary.swift` for the single-capture exclusion check.
    func releaseCurrentSessionIfTerminal() async -> Bool {
        guard let existing = currentSession else { return true }
        guard await existing.isTerminal else { return false }
        SpeakLog.engine.info(
            "SpeakEngine: releasing terminal session (state settled without stop) before new begin."
        )
        currentSession = nil
        return true
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
        // [fix: audit — C2 stop-wedge watchdog] Every await inside stop() is now
        // bounded, but defense-in-depth says the engine must not trust that
        // forever: arm a watchdog that force-cancels the session (releasing the
        // A3 slot) if stop() is still non-terminal when it fires.
        let watchdog = armStopWatchdog(for: session)
        defer { watchdog.cancel() }
        // [A3 wedge fix] If session.stop() throws (e.g., A1 cancel-during-processing
        // re-check, or a paste failure), `currentSession = nil` below is never reached.
        // Clear currentSession before propagating the error so a subsequent
        // beginDictation() is not wedged by a non-nil stale session. The session is
        // already in a terminal error state at this point — clearing the reference
        // releases it. [decision A3-wedge]
        do {
            let result = try await session.stop()
            // Stop succeeded — fall through to history save below.
            return await finishEndDictation(result: result, session: session)
        } catch {
            // Identity-guarded clear: a concurrent cancelDictation + beginDictation
            // interleave during session.stop()'s awaits may have installed a NEW
            // session — a stale catch must never release it. [fix: audit — clobber]
            if currentSession === session {
                currentSession = nil
            }
            SpeakLog.engine.error(
                "SpeakEngine: endDictation stop/paste failed — currentSession cleared. \(error.localizedDescription, privacy: .public)"
            )
            throw error
        }
    }

    /// Arm the [C2] stop-wedge watchdog: if `session` is still the tracked
    /// session AND still non-terminal when the watchdog fires, force-cancel it
    /// so the pending `stop()` fails at its next `.error` re-check and the
    /// engine slot is released instead of wedging on a hung await.
    /// The returned task must be cancelled (`defer`) when the call completes.
    /// Internal (not `private`) — `endAuxiliarySession` in
    /// `SpeakEngine+Auxiliary.swift` arms the same watchdog.
    func armStopWatchdog(for session: CaptureSession) -> Task<Void, Never> {
        let bound = processingWatchdog
        return Task { [weak self] in
            try? await Task.sleep(for: bound)
            guard !Task.isCancelled, let self else { return }
            await self.forceCancelIfStalled(session)
        }
    }

    /// Watchdog body — identity-guarded (a newer session in the same slot must
    /// survive) and terminal-guarded (a session that already settled must not
    /// be re-cancelled).
    private func forceCancelIfStalled(_ session: CaptureSession) async {
        let tracked = currentSession === session || auxiliarySession === session
        guard tracked else { return }
        guard await !session.isTerminal else { return }
        SpeakLog.engine.error(
            "SpeakEngine: stop watchdog fired — session still non-terminal after \(self.processingWatchdog, privacy: .public); force-cancelling."
        )
        await session.cancel()
    }

    /// Completes the end-dictation flow after a successful `session.stop()`:
    /// saves the history entry (best-effort) and clears `currentSession`.
    /// Extracted so the error path above can clear `currentSession` without
    /// duplicating the history-save logic. `session` is passed so the clears
    /// below can be identity-guarded — only the session that was actually
    /// stopped may release the slot. [fix: audit — session clobber]
    private func finishEndDictation(result: TranscriptionResult, session: CaptureSession) async -> TranscriptionResult {

        // [A2] Empty-transcript guard (engine side): CaptureSession.stop() already
        // skips paste for empty rawText. Skip history save too — a zero-char entry
        // is noise and could mislead WPM/latency stats. Reach .done cleanly.
        guard !result.rawText.isEmpty else {
            if currentSession === session {
                currentSession = nil
            }
            SpeakLog.engine.info("SpeakEngine: empty transcript — skip history save.")
            return result
        }

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
            cleanupSeconds: result.latency?.cleanupSeconds ?? 0,
            // [fix: audit — cleanup honesty] Persist the real cleanup outcome so
            // failed/timed-out passes are never counted as successful cleanup in
            // LatencyStats. Empty string = legacy/unknown (pre-migration rows).
            cleanupStatus: result.cleanupStatus.storageKey
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

        if currentSession === session {
            currentSession = nil
        }
        return result
    }

    /// Hard-cancel the current dictation. Safe to call if no session is in flight.
    /// Also cancels any in-flight auxiliary capture (command mode / sandbox):
    /// mute semantics are "no audio is read", and that covers every capture the
    /// engine owns — not only the dictation slot. [fix: audit — C1]
    public func cancelDictation() async {
        var cancelled = false
        if let session = currentSession {
            SpeakLog.engine.info("SpeakEngine: cancelDictation — cancelling session.")
            await session.cancel()
            // Identity-guarded: only release the session we actually cancelled.
            // A newer session installed during the await must survive. [fix: clobber]
            if currentSession === session {
                currentSession = nil
            }
            cancelled = true
        }
        if let aux = auxiliarySession {
            SpeakLog.engine.info("SpeakEngine: cancelDictation — cancelling auxiliary session.")
            await aux.cancel()
            if auxiliarySession === aux {
                auxiliarySession = nil
            }
            cancelled = true
        }
        if !cancelled {
            SpeakLog.engine.info("SpeakEngine: cancelDictation() — no session in flight, no-op.")
        }
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

    // MARK: - VAD attachment (output-conversation-reconnect)

    /// Attach (or, passing `nil`, detach) a `VoiceActivityDetector` to the
    /// current session's live `AudioCapture` — mirrors `currentLevels()` above.
    /// Returns `false` when no session is active or the transcriber does not
    /// expose an `AudioCapture` (fixture mode); the caller (agent bridge / tests)
    /// uses this to know whether real audio is actually feeding the VAD.
    @discardableResult
    public func attachVoiceActivityDetector(_ vad: VoiceActivityDetector?) async -> Bool {
        guard let session = currentSession else { return false }
        return await session.attachVoiceActivityDetector(vad)
    }
}

// MARK: - V01-W warm-up (extension: keeps the actor body under the type-body lint cap)

private extension SpeakEngine {

    /// [V01-W] Assemble the cleanup warm-up handler ONLY when cleanup will
    /// actually run. `activeCleaner` already encodes the gate (nil when
    /// cleanup is off or level is `.none`), so a nil cleaner → nil handler and
    /// `CaptureSession.start()` spawns no warm-up task — delivery byte-identical
    /// to pre-V01-W. The closure captures the active cleaner; `warmUp()` itself
    /// re-checks `isAvailable` and degrades to a logged no-op when unavailable.
    func makeWarmUpHandler(cleaner: (any LLMCleaning)?) -> CaptureSession.WarmUpHandler? {
        guard let cleaner else { return nil }
        return { await cleaner.warmUp() }
    }

    /// [H-1] Assemble the Voice Actions handler when enabled in settings.
    func makeVoiceActionsHandler() -> CaptureSession.VoiceActionsHandler? {
        guard settings.voiceActionsEnabled else { return nil }
        let prefix = settings.voiceActionsPrefix
        let executor = voiceActionsExecutor
        let router = PrefixActionRouter(prefix: prefix)
        let coordinator = VoiceActionsCoordinator(
            router: router,
            executor: executor,
            commandService: voiceActionsCommandService,
            enabled: true
        )
        let executorState = executor != nil ? "wired" : "none"
        let commandState = voiceActionsCommandService != nil ? "wired" : "none"
        SpeakLog.voiceActions.info(
            "SpeakEngine: Voice Actions enabled — prefix='\(prefix, privacy: .public)', executor=\(executorState, privacy: .public), commandService=\(commandState, privacy: .public)."
        )
        return { rawText in
            guard case .dictation = router.route(rawText, knownActionNames: []) else {
                let knownActionNames = await executor?.listActionNames() ?? []
                return await coordinator.handle(transcript: rawText, knownActionNames: knownActionNames)
            }
            return .dictation(text: rawText)
        }
    }
}
