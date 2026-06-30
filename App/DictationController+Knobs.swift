// App/DictationController+Knobs.swift
//
// PE-4: re-clean support. Reads the stored raw transcript + current knob overrides
// from the overlay model and re-runs cleanup, pasting the result.
//
// `recleanCurrentTranscript()` is intentionally kept thin: it delegates the actual
// cleanup + paste to `SpeakEngine.recleanAndPaste(...)` which owns the cleaner /
// inserter seam. DictationController just composes the effective profile (base
// destination + per-dictation knob overrides) and hands off.

import Foundation
import SpeakCore

extension DictationController {

    // MARK: - PE-4 re-clean

    /// Re-run AI cleanup on the last raw transcript with the current knob settings and
    /// paste the result. No-op when no raw transcript is stored (before the first
    /// successful dictation, or after a cancel). [decision PE-4]
    func recleanCurrentTranscript() async {
        guard let raw = lastRawTranscript else {
            SpeakLog.engine.info("DictationController: reclean skipped — no raw transcript stored.")
            return
        }
        let model = overlayController.overlayModel
        var effectiveProfile = activeDestination
        if model.perDictationFormat != .asIs { effectiveProfile.format = model.perDictationFormat }
        if model.perDictationTone != .neutral { effectiveProfile.tone = model.perDictationTone }
        if model.perDictationLength != .preserve { effectiveProfile.length = model.perDictationLength }
        do {
            try await engine.recleanAndPaste(raw, profile: effectiveProfile, category: activeCategory)
            SpeakLog.engine.info("DictationController: reclean completed successfully.")
        } catch {
            SpeakLog.engine.error(
                "DictationController: reclean failed — \(error.localizedDescription, privacy: .public)"
            )
        }
    }
}
