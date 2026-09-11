// App/DictationController+Session.swift
//
// [lint] Moved out of the main class body into an extension to keep
// `DictationController`'s type body under SwiftLint's `type_body_length` cap —
// pure code motion, no behavior change (matching this file's existing
// precedent: `applyAppearance`/`rebindExtraBindings`/`registerCLIPortAndSweepAgentCalls`
// in `DictationController+Session.swift`'s sibling extensions).
//
// Owns: cancel/re-paste/mute session actions, and the private task-consumption
// loops that bridge `HotkeyMonitor`'s async streams (arm-state, command chord,
// hotkey events) onto the main actor. `armStateTask`, `commandChordTask`,
// `eventTask`, and `commandModeController` are declared in the main class body
// without `private` (module-internal) specifically so this same-module
// extension file can reach them — Swift's `private` is file-scoped.

import Foundation
import SpeakCore

extension DictationController {

    // MARK: - Session actions

    /// Cancel the current dictation without pasting. Previously called by the Escape
    /// key handler (W2.2), which was changed to invoke `endDictation()` (stop+paste)
    /// instead. `cancelDictation()` is now only called internally (e.g. mute toggle)
    /// and remains available for future use. Safe to call when idle — the engine
    /// no-ops in that case.
    ///
    /// Hides the overlay immediately (no done-flash on cancel) and resets to idle.
    func cancelDictation() {
        Task { [weak self] in
            guard let self else { return }
            await self.engine.cancelDictation()
            self.overlayController.cancelImmediate()
            self.caretOverlay.hide()
            self.icon = .idle
            self.monitor.notifySessionEnded()  // [validation-fix C1] keep detector in sync
            SpeakLog.engine.info("DictationController: dictation cancelled by user (Escape).")
        }
    }

    /// Re-paste the most recent finished transcript at the current cursor
    /// ("Paste Last Transcript" / Ctrl+Cmd+V). No-op until the first dictation completes.
    /// On AX-denied, the text is still placed on the clipboard (PasteboardWriter's
    /// clipboard floor) and the permissions hint is surfaced.
    func pasteLastTranscript() {
        let text = lastTranscript
        guard !text.isEmpty else { return }
        Task { [weak self] in
            guard let self else { return }
            do {
                try await self.pasteboardWriter.insert(text)
                SpeakLog.engine.info("DictationController: re-pasted last transcript.")
            } catch {
                self.permissionsNeeded = true
                SpeakLog.engine.info(
                    "DictationController: re-paste left text on clipboard — Accessibility needed."
                )
            }
        }
    }

    // MARK: - Hardware mute (SPEC §7.4)

    func toggleMute() {
        Task { [weak self] in
            guard let self else { return }
            let nowMuted = await self.engine.toggleMute()
            self.isMuted = nowMuted
            if nowMuted {
                self.monitor.notifySessionEnded()
                self.overlayController.stop()
                self.caretOverlay.hide()
                self.icon = .idle
            }
        }
    }

    // MARK: - Private task management

    /// Start consuming `monitor.armStateChanges` to update `permissionsNeeded`.
    /// On arm: clear the hint and ensure the event-consume task is running.
    func startArmStateTask() {
        armStateTask?.cancel()
        armStateTask = Task { [weak self] in
            guard let self else { return }
            for await armed in self.monitor.armStateChanges {
                let isArmed = armed
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    if isArmed {
                        self.permissionsNeeded = false
                        SpeakLog.hotkey.info("DictationController: tap armed — permissionsNeeded cleared.")
                    } else {
                        // [validation-fix C7] A disarm fires on EVERY teardown — including
                        // a normal re-arm cycle (rate-limit trip, wake re-arm) while AX is
                        // still granted. Only raise the permissions hint when AX is actually
                        // missing, so the menu doesn't flicker "permissions needed" spuriously.
                        let axGranted = self.permissionManager.status(.accessibility) == .granted
                        if !axGranted {
                            self.permissionsNeeded = true
                            SpeakLog.hotkey.warning("DictationController: tap disarmed + AX missing — permissionsNeeded set.")
                        } else {
                            SpeakLog.hotkey.info("DictationController: tap disarmed during re-arm (AX still granted) — no hint.")
                        }

                        // [validation-fix C2] If the tap died mid-session, the engine is
                        // stuck `.recording` (HUD frozen, mic hot) with no way to self-heal.
                        // Cancel the session so it doesn't hang. Covers BOTH hold and
                        // double-tap (both surface as `icon == .listening`). We cancel
                        // (discard) rather than paste: a tap death is not a user stop
                        // intent, and "never paste against intent / be very safe" takes
                        // precedence over salvaging the partial transcript.
                        if self.icon == .listening {
                            SpeakLog.hotkey.warning("DictationController: tap died mid-session — cancelling to avoid stuck recording.")
                            self.cancelDictation()
                        }
                    }
                }
            }
        }
    }

    /// Consume `monitor.commandChordEvents` and drive Command Mode. Begin starts the
    /// instruction capture; end runs the transform. Hops to the main actor (the
    /// controller is `@MainActor`).
    func startCommandChordTask() {
        commandChordTask?.cancel()
        let chordEvents = monitor.commandChordEvents
        commandChordTask = Task { [weak self] in
            for await event in chordEvents {
                await MainActor.run { [weak self] in
                    guard let self, let controller = self.commandModeController else { return }
                    switch event {
                    case .begin: controller.begin()
                    case .end:   controller.end()
                    }
                }
            }
        }
    }

    /// Start the event-consume task. Because `monitor.events` is a stable
    /// AsyncStream that lives for the monitor's lifetime, this task can be
    /// started once at `startMonitoring()` and will receive events across all
    /// arm cycles without restart.
    func startEventTask() {
        guard eventTask == nil else { return }
        let events = monitor.events
        eventTask = Task { [weak self] in
            for await event in events {
                guard let self else { break }
                await self.handle(event)
            }
            SpeakLog.hotkey.info("DictationController: event stream ended.")
        }
    }

    // MARK: - Private event handling

    func handle(_ event: HotkeyEvent) async {
        switch event {
        case .startCapture:
            await beginDictation()

        case .stopCapture:
            await endDictation()
        }
    }
}
