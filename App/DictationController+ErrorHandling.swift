// App/DictationController+ErrorHandling.swift
//
// Dictation begin / end with full error routing and permission recovery.
// Both methods are `internal` (not `private`) so sibling extensions
// (+CLI, the main file's `handle()`) can call them across files.

import AppKit
import Foundation
import SpeakCore

extension DictationController {

    // MARK: - Begin / end dictation

    func beginDictation() async {
        do {
            // [PE-0 wiring] Capture the frontmost app on the main actor and pass its
            // bundle id down, so the engine can resolve an app-specific profile (e.g.
            // Cursor → Code) without importing AppKit. Frontmost = the target app
            // because the overlay is a non-activating panel.
            let frontmostApp    = NSWorkspace.shared.frontmostApplication
            let frontmostBundleID = frontmostApp?.bundleIdentifier
            // P2.2: capture PID now (before the await) so we hold one consistent
            // frontmost-app snapshot for the caret overlay placement.
            let frontmostPID    = frontmostApp?.processIdentifier ?? 0
            // [PE-3] Seed the live-panel shaping state from the same resolution the engine
            // uses, so the panel highlights the destination that will actually run and a
            // chip tap can override it for this dictation only.
            resolveActiveDestination(frontmostBundleID: frontmostBundleID)
            try await engine.beginDictation(frontmostBundleID: frontmostBundleID)
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
            // P2.2: show the caret overlay near the text insertion point.
            // Gracefully no-ops when CaretLocator returns nil (browser, Electron, etc.).
            caretOverlay.show(partialText: "", frontmostPID: frontmostPID)
            // [PE-3] Configure the live-panel destination strip: the three AI destinations,
            // highlighting the resolved one. Shown only when cleanup will run (a chip does
            // nothing when AI is off / level=.none). Tapping reshapes THIS dictation only.
            overlayController.configureDestinationStrip(
                choices: willCleanup ? OverlayDestinationChoice.allCases : [],
                active: OverlayDestinationChoice(profileID: activeDestination.id),
                activeCategory: activeCategory,
                onSelect: { [weak self] choice in self?.selectDestinationChoice(choice) },
                onSelectCategory: { [weak self] category in self?.selectCategoryChoice(category) }
            )
            // [PE-4] Wire cancel + knob callbacks. A knob change flags the session as
            // overridden so the stop-time profile apply runs with the knob values applied.
            overlayController.configureKnobs(
                onKnobChanged: { [weak self] in self?.didOverrideThisSession = true },
                onCancel: { [weak self] in self?.cancelDictation() },
                onReclean: { [weak self] in self?.recleanCurrentTranscript() }
            )
        } catch SpeakError.microphoneMuted {
            monitor.notifySessionEnded()
            icon = .idle
            SpeakLog.engine.info("DictationController: start ignored — microphone muted.")
        } catch {
            monitor.notifySessionEnded()
            // W2.2: show an error state in the HUD instead of silently hiding.
            overlayController.showError(error.localizedDescription)
            icon = .error
            SpeakLog.engine.error(
                "DictationController: beginDictation failed — \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    func endDictation() async {
        // [task #30] Re-entrancy guard: endDictation can arrive twice (Escape routes here
        // AND a hotkey single-press), or after the session already ended. Only a live
        // .listening session should be stopped; a 2nd call finds no session and would
        // surface a spurious error HUD. Ignore unless we are actually listening.
        guard icon == .listening else {
            SpeakLog.engine.info("DictationController: endDictation ignored — not listening (icon=\(String(describing: self.icon), privacy: .public)).")
            return
        }
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
            // [P2.3] Show the raw partial in the caret panel during the cleanup window
            // (typically 0.3–1.5 s). The user sees their captured speech immediately
            // even before the AI finishes. lastRawTranscript holds the last non-empty
            // partial from the onPartialTextUpdated drain; falls back to "" on empty
            // sessions (no-op empty overlay is fine — panel stays visible with "…").
            caretOverlay.showProcessing(rawText: lastRawTranscript ?? "")
            // [PE-3 / PE-4] Apply the live-panel override exactly once, here, BEFORE
            // endDictation() triggers the cleanup pass. Reads the per-dictation knob
            // values from the overlay model to build the effective profile. [decision PE-4]
            let kf = overlayController.overlayModel.perDictationFormat
            let kt = overlayController.overlayModel.perDictationTone
            let kl = overlayController.overlayModel.perDictationLength
            let hasKnobOverride = kf != .asIs || kt != .neutral || kl != .preserve
            if didOverrideThisSession || hasKnobOverride {
                if overrodeToRaw {
                    await engine.applyRawOverride()
                } else {
                    // Build an effective profile: start from the active destination, then
                    // apply any non-Auto knob values on top without touching saved defaults.
                    var effectiveProfile = activeDestination
                    if kf != .asIs { effectiveProfile.format = kf }
                    if kt != .neutral { effectiveProfile.tone = kt }
                    if kl != .preserve { effectiveProfile.length = kl }
                    await engine.applyProfileOverride(effectiveProfile, category: activeCategory)
                }
            }
            let result = try await engine.endDictation()
            // Remember the finished text for "Paste Last Transcript" (Wispr's re-paste).
            lastTranscript = result.cleanedText ?? result.rawText
            // [PE-4] Store the raw transcript so the user can re-run cleanup with new knobs.
            lastRawTranscript = result.rawText
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
            caretOverlay.hide()
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
            caretOverlay.hide()
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
            caretOverlay.hide()
            overlayController.showError(SpeakError.pasteIntoSecureField(text: text).recoverySuggestion)
            icon = .idle
            lastTranscript = text
            Scratchpad.append(text)
            SpeakLog.engine.info(
                "DictationController: paste refused — focused element is a secure field; text saved to Scratchpad"
            )
        } catch {
            // W2.2: show an error state in the HUD with a short reason instead of silently hiding.
            caretOverlay.hide()
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
