// SpeakCore/Engine/SpeakEngine+Auxiliary.swift
//
// Auxiliary (non-dictation) capture sessions — Command Mode instruction
// capture and the Settings "Test My Voice" sandbox. Extracted from
// SpeakEngine.swift to keep that file under SwiftLint's `file_length` cap —
// pure code motion, no behavior change.
//
// Members accessed here are module-internal for exactly this reason (see the
// [lint] note on `transcriber` in SpeakEngine.swift): `muted`,
// `isMicrophoneAuthorized`, `currentSession`, `auxiliarySession`, `settings`,
// `cleaner`, `transcriber`, `snippetStore`, `releaseCurrentSessionIfTerminal()`,
// `armStopWatchdog(for:)`.

import AVFoundation
import os

extension SpeakEngine {

    // MARK: - Auxiliary capture sessions (command mode, voice sandbox)

    /// Mint AND start an auxiliary capture session — a gated capture that is
    /// not a dictation (no paste, no history, no voice actions).
    ///
    /// Enforces the SAME capture gates as `beginDictation` — this is the whole
    /// point of the engine-minted design [fix: audit — C1]:
    ///   - `.microphoneMuted` thrown when muted (checked again immediately
    ///     before `start()` to close the TOCTOU window).
    ///   - `.microphoneDenied` thrown when the TCC mic grant is absent (with
    ///     the same notDetermined → `requestAccess` prompt first).
    ///   - `.unknown` thrown when any capture — dictation OR aux — is already
    ///     in flight (single-capture exclusion on the shared transcriber).
    ///
    /// The session is paste-free by construction (`inserter: nil`) and is
    /// tracked in `auxiliarySession` so `setMuted(true)`/`cancelDictation()`
    /// cancel it and `beginDictation` refuses while it lives.
    ///
    /// - Parameter includeCleanup: `true` (sandbox) wires the settings-gated
    ///   cleaner + `.styled` mode + expander chain; `false` (command mode)
    ///   produces a transcriber-only session that still gets the expander
    ///   (acoustic corrections repair misheard instruction text).
    /// - Returns: the started session. The caller drives `endAuxiliarySession`
    ///   or `cancelAuxiliarySession` — NOT `session.stop()`/`cancel()` — so the
    ///   slot is released under the engine's watchdog.
    public func beginAuxiliarySession(includeCleanup: Bool) async throws -> CaptureSession {
        // Same gates as beginDictation — deliberately mirrored, not shared, so
        // the refusal errors stay identical and the ordering stays readable.
        guard !muted else {
            SpeakLog.engine.info("SpeakEngine: beginAuxiliarySession refused — microphone is muted.")
            throw SpeakError.microphoneMuted
        }
        if AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined {
            _ = await AVCaptureDevice.requestAccess(for: .audio)
        }
        guard isMicrophoneAuthorized() else {
            SpeakLog.engine.info("SpeakEngine: beginAuxiliarySession refused — microphone not authorized.")
            throw SpeakError.microphoneDenied
        }
        // Single-capture exclusion, both directions: refuse while a dictation is
        // live, and refuse a second concurrent aux capture.
        if currentSession != nil {
            guard await releaseCurrentSessionIfTerminal() else {
                SpeakLog.engine.info("SpeakEngine: beginAuxiliarySession refused — dictation in flight.")
                throw SpeakError.unknown("SpeakEngine: auxiliary capture refused — a dictation is in flight.")
            }
        }
        if let existing = auxiliarySession {
            guard await existing.isTerminal else {
                SpeakLog.engine.info("SpeakEngine: beginAuxiliarySession refused — auxiliary capture already in flight.")
                throw SpeakError.unknown("SpeakEngine: auxiliary capture refused — already in flight.")
            }
            auxiliarySession = nil
        }
        setPreferredInputDeviceUID(settings.preferredInputDeviceUID)

        // Same settings-derived wiring as the dictation mint, minus delivery:
        // no inserter (paste-free), no voice actions, no agent prefix.
        let levelIsNone = settings.cleanupLevel == .none
        let activeCleaner: (any LLMCleaning)? = (includeCleanup && settings.cleanupEnabled && !levelIsNone)
            ? cleaner
            : nil
        let session = CaptureSession(
            transcriber: transcriber,
            cleaner: activeCleaner,
            inserter: nil,
            locale: settings.language,
            cleanupMode: .styled(
                settings.cleanupStyle,
                settings.cleanupLevel,
                customVocabulary: settings.effectiveVocabulary
            ),
            expander: defaultExpander(for: settings, snippetStore: snippetStore)
        )
        auxiliarySession = session

        // Second mute check at the last moment before opening the mic — same
        // TOCTOU window as beginDictation (TCC prompt + release awaits above).
        guard !muted else {
            SpeakLog.engine.info("SpeakEngine: beginAuxiliarySession refused — muted during start.")
            if auxiliarySession === session {
                auxiliarySession = nil
            }
            throw SpeakError.microphoneMuted
        }
        do {
            try await session.start()
        } catch {
            if auxiliarySession === session {
                auxiliarySession = nil
            }
            throw error
        }
        SpeakLog.engine.info("SpeakEngine: auxiliary session started (cleanup=\(includeCleanup, privacy: .public)).")
        return session
    }

    /// Stop an auxiliary session under the same [C2] watchdog as
    /// `endDictation`, release the slot, and return the result.
    /// No history save — aux captures are not dictations.
    /// Throws `.unknown` when `session` is not the tracked auxiliary session.
    public func endAuxiliarySession(_ session: CaptureSession) async throws -> TranscriptionResult {
        guard auxiliarySession === session else {
            throw SpeakError.unknown("SpeakEngine.endAuxiliarySession called for an untracked session.")
        }
        let watchdog = armStopWatchdog(for: session)
        defer { watchdog.cancel() }
        do {
            let result = try await session.stop()
            if auxiliarySession === session {
                auxiliarySession = nil
            }
            return result
        } catch {
            if auxiliarySession === session {
                auxiliarySession = nil
            }
            throw error
        }
    }

    /// Cancel an auxiliary session and release the slot. No-op when `session`
    /// is not the tracked auxiliary session.
    public func cancelAuxiliarySession(_ session: CaptureSession) async {
        guard auxiliarySession === session else { return }
        await session.cancel()
        if auxiliarySession === session {
            auxiliarySession = nil
        }
    }

    /// Release the aux slot without touching the session — for callers that
    /// drove `stop()`/`cancel()` themselves. Identity-guarded.
    public func releaseAuxiliarySession(_ session: CaptureSession) {
        if auxiliarySession === session {
            auxiliarySession = nil
        }
    }

    /// The engine transcriber's live mic-level stream (0…1 raw RMS) when it
    /// exposes one — used by the Settings sandbox card's VU meter. Call after
    /// `beginAuxiliarySession` has started capture (the level stream is created
    /// by `AudioCapture.start()` inside `Transcribing.startStream`).
    /// Single-consumer: take it once. [fix: audit — C1] Replaces
    /// `VoiceSandbox.levelStream()`, which read the stream off a SECOND,
    /// ungated transcriber; aux sessions now share the engine's transcriber.
    public func micLevelStream() -> AsyncStream<Double>? {
        (transcriber as? AudioCaptureProviding)?.audioCapture?.startLevelStream()
    }

}
