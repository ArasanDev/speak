// App/DictationController+ErrorHandling.swift
//
// Dictation begin / end with full error routing and permission recovery.
// Both methods are `internal` (not `private`) so sibling extensions
// (+CLI, the main file's `handle()`) can call them across files.

import Foundation
import SpeakCore

extension DictationController {

    // MARK: - Begin / end dictation

    func beginDictation() async {
        do {
            try await engine.beginDictation()
            icon = .listening
            SpeakLog.engine.info("DictationController: beginDictation succeeded → .listening")
            let engineRef = engine
            // W2.1: pass both the partials provider and the levels provider to OverlayController.
            // The cleanup flag drives the "Pasting…" vs "Cleaning up…" copy (W2.2).
            let willCleanup = settingsStore.cleanupEnabled && settingsStore.cleanupLevel != .none
            overlayController.start(
                partialsProvider: { await engineRef.currentPartials() },
                levelsProvider: { await engineRef.currentLevels() },
                isCleaningUp: willCleanup
            )
        } catch SpeakError.microphoneMuted {
            icon = .idle
            SpeakLog.engine.info("DictationController: start ignored — microphone muted.")
        } catch {
            icon = .error
            // W2.2: show an error state in the HUD instead of silently hiding.
            overlayController.showError(error.localizedDescription)
            SpeakLog.engine.error(
                "DictationController: beginDictation failed — \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    func endDictation() async {
        // [validation-fix C1] Reset the double-tap detector — this stop may be
        // out-of-band (Escape, CLI --stop, error) where no hotkey tap reset it.
        // Idempotent after a normal hotkey-driven stop. Runs before any await so
        // it is not skipped if endDictation throws/degrades below.
        monitor.notifySessionEnded()
        do {
            // Phase C: transition overlay to .processing before the cleanup await.
            // This keeps the panel visible showing "Cleaning up…" / "Pasting…" during
            // the LLM pass. The panel is hidden AFTER the done flash, not immediately on stop.
            icon = .processing
            overlayController.transition(to: .processing)
            let result = try await engine.endDictation()
            // Remember the finished text for "Paste Last Transcript" (Wispr's re-paste).
            lastTranscript = result.cleanedText ?? result.rawText
            icon = .done
            // Phase C: show done state briefly before hiding the panel.
            // W2.3: Enforce a minimum processing dwell of 200 ms so "Cleaning up…"
            // / "Pasting…" is always visible before transitioning to .done.
            // Paste has already happened inside endDictation(), so this dwell
            // adds zero text-delivery latency — it only affects the visual transition.
            // [decision W2.3: 200 ms minimum dwell — enough to read "Cleaning up…"
            //  without stalling the workflow; matches Wispr's micro-dwell. benchmark.md §7]
            let processingDwellNanoseconds: UInt64 = 200_000_000  // 200 ms [decision W2.3]
            try? await Task.sleep(nanoseconds: processingDwellNanoseconds)
            overlayController.transition(to: .done)
            SpeakLog.engine.info("DictationController: endDictation succeeded → .done")
            // 600ms done-flash — roadmap.md P8 [decision].
            let doneFlashNanoseconds: UInt64 = 600_000_000  // [decision] roadmap.md P8
            try? await Task.sleep(nanoseconds: doneFlashNanoseconds)
            overlayController.stop()
            icon = .idle
            // P11-c: Signal dashboard to refresh recent dictations after successful completion.
            dictationCompletedSubject.send()
        } catch SpeakError.pasteRequiresAccessibility(let text) {
            // Graceful degradation: text was written to the clipboard (the
            // clipboard-floor step in PasteboardWriter always runs), but
            // synthetic Cmd+V was skipped because AX is not granted.
            // Outcome: NOT a fault — the user can paste manually (Cmd+V).
            // Mirror the `.microphoneMuted` soft-catch pattern: hide overlay,
            // stay idle, surface the permissions hint via `permissionsNeeded`.
            // Also route the text to the Scratchpad so it's never lost and is
            // immediately editable (verified Wispr paste-failure behavior).
            overlayController.stop()
            icon = .idle
            permissionsNeeded = true
            lastTranscript = text
            Scratchpad.append(text)
            SpeakLog.engine.info(
                "DictationController: paste fell back to clipboard + Scratchpad — Accessibility needed"
            )
        } catch SpeakError.pasteIntoSecureField(let text) {
            // Deliberate refusal: the focused element is a secure text field
            // (password input). Pasting dictated speech into a credential field
            // is a privacy/safety footgun; PasteboardWriter refused the paste.
            // The clipboard floor still ran (text is on the clipboard), so text
            // is never lost — we route it to the Scratchpad for easy access.
            // Outcome: NOT a fault, NOT a permissions gap — stay `.idle`, show
            // the HUD error so the user sees the clear message from
            // `SpeakError.pasteIntoSecureField.recoverySuggestion`.
            // [decision: do NOT set `permissionsNeeded` — no permission is missing;
            //  this is a safety refusal, not a degraded permission state.]
            overlayController.stop()
            overlayController.showError(SpeakError.pasteIntoSecureField(text: text).recoverySuggestion)
            icon = .idle
            lastTranscript = text
            Scratchpad.append(text)
            SpeakLog.engine.info(
                "DictationController: paste refused — focused element is a secure field; text saved to Scratchpad"
            )
        } catch {
            // W2.2: show an error state in the HUD with a short reason instead of silently hiding.
            overlayController.showError(error.localizedDescription)
            icon = .error
            SpeakLog.engine.error(
                "DictationController: endDictation failed — \(error.localizedDescription, privacy: .public)"
            )
            // P11-c: Signal dashboard to refresh even on error completion (may have partial history).
            dictationCompletedSubject.send()
        }
    }
}
