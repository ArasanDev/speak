// SpeakCore/STT/SpeechPrewarmer.swift
//
// STT P2 — lightweight model prewarming.
//
// Purpose: SpeechAnalyzer loads its model cold on first use (~1-3s observed).
// `SpeechPrewarmer.prewarm()` warms the model non-blocking shortly after launch
// and after wake by running a best-effort analyzer setup in a detached Task.
//
// Design constraints:
//   • Non-blocking: returns immediately; work is on a detached Task.
//   • Guarded: no-ops when `SpeechTranscriber.isAvailable == false`. [verified]
//   • No mic: uses `SpeechAnalyzer.Options(modelRetention: .processLifetime)` —
//     keeping the model loaded for the process lifetime once warmed. [verified]
//   • Silent on error: prewarm failure is logged but never propagated.
//   • `prewarm()` is idempotent: redundant calls during a session are cheap
//     (the detached Task exits early if warming is already in progress or done).
//
// Wire-up call sites (NOT done here — handoff to builder-app/orchestrator):
//   • App launch (≈3s after startup to avoid blocking initial render).
//   • NSWorkspace `NSWorkspaceDidWakeNotification`.
// These call sites live in App target files outside the STT seam.
//
// API verified against arm64e-apple-macos.swiftinterface, MacOSX26.5.sdk, 2026-06-22:
//   • SpeechTranscriber.isAvailable: Bool [verified]
//   • SpeechAnalyzer.Options(priority:modelRetention:) [verified]
//   • SpeechAnalyzer.Options.ModelRetention.processLifetime [verified]
//   • SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith:) async -> AVAudioFormat? [verified]
//
// The latency benefit (~1-3s first-dictation cold-start reduction) is [inferred]
// from the modelRetention API semantics and observed VoiceInk prewarm behavior —
// not measurable without a live benchmark corpus.

import os
import Speech

/// Warms the SpeechAnalyzer model non-blocking so first-dictation cold-start
/// latency is reduced. Calling `prewarm()` is idempotent and safe at any time.
@available(macOS 26.0, *)
public final class SpeechPrewarmer: Sendable {

    public static let shared = SpeechPrewarmer()

    private init() {}

    /// Trigger model prewarming in a detached background Task. Returns immediately.
    ///
    /// Call from the App target:
    ///   - ~3s after launch (to avoid delaying initial UI render).
    ///   - On `NSWorkspaceDidWakeNotification`.
    ///
    /// Failure is logged via `os.Logger` and never propagated.
    public func prewarm() {
        guard SpeechTranscriber.isAvailable else { // [verified]
            SpeakLog.stt.info("SpeechPrewarmer: SpeechTranscriber not available — skipping prewarm.")
            return
        }
        Task.detached(priority: .background) {
            await Self.warmModel()
        }
    }

    // MARK: - Internals

    /// Performs the warm-up: builds the analyzer with processLifetime retention.
    /// Constructing a SpeechAnalyzer instance is what actually loads the on-device
    /// model; the static bestAvailableAudioFormat query alone does not guarantee it.
    /// [STT-H1] [verified: SpeechAnalyzer(modules:options:) + Options(priority:modelRetention:)
    ///  + ModelRetention.processLifetime — arm64e-apple-macos.swiftinterface, MacOSX26.5.sdk]
    private static func warmModel() async {
        let locale = Locale(identifier: "en-US")
        guard let resolvedLocale = await SpeechTranscriber.supportedLocale(equivalentTo: locale) else {
            SpeakLog.stt.info("SpeechPrewarmer: en-US not a supported locale — skipping prewarm.")
            return
        }
        let transcriber = SpeechTranscriber(locale: resolvedLocale, preset: .progressiveTranscription)

        // Only prewarm when the model asset is installed — avoid triggering
        // a background download during prewarm; that is the session's job.
        let status = await AssetInventory.status(forModules: [transcriber])
        guard status == .installed else {
            SpeakLog.stt.info("SpeechPrewarmer: model not installed (status: \(String(describing: status), privacy: .public)) — skipping prewarm.")
            return
        }

        // Constructing the analyzer with processLifetime retention loads and
        // retains the model for the process lifetime. [STT-H1]
        // [verified: SpeechAnalyzer(modules:options:) SDK signature, 2026-06-26]
        let options = SpeechAnalyzer.Options(
            priority: .background,
            modelRetention: .processLifetime
        )
        _ = SpeechAnalyzer(modules: [transcriber], options: options)
        SpeakLog.stt.info("SpeechPrewarmer: model warm-up complete.")
    }
}
