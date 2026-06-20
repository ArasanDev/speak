// App/DictationController.swift
//
// The app's brain. Replaces `MicTestController` (retired at P5/P8 keystone).
//
// Responsibilities:
//   - Constructs the production `SpeakEngine` from real components.
//   - Owns a `HotkeyMonitor` and bridges its events to the engine verbs.
//   - Publishes `icon: MenubarIcon` (drives the menu-bar label).
//   - Publishes `permissionsNeeded: Bool` (drives a hint in the menu).
//
// Honesty boundary: the end-to-end behavior (double-tap Fn, paste at cursor,
// real-time icon) is [deferred — human verification required]. The only
// autonomously-verified piece is the MenubarIcon mapping (unit tests).
//
// Threading:
//   - `DictationController` is `@MainActor`: all `@Published` mutations are
//     on the main thread (required by SwiftUI/Combine).
//   - `SpeakEngine` and `HistoryStore` are actors: all calls to them are `await`.
//   - The hotkey-event Task reads `monitor.events` (an AsyncStream) and awaits
//     engine calls; it captures `[weak self]` to avoid a retain cycle.
//
// History-store degradation:
//   `HistoryStore.makeProductionStore()` throws (SQLite open can fail). On
//   failure we log via `SpeakLog.storage` and continue with a no-op
//   `NullHistoryStore`. The dictation flow (capture → cleanup → paste) is
//   unaffected; history is silently disabled for the session.
//
// Permission-denied degradation:
//   `HotkeyMonitor.start()` throws `.accessibilityDenied` or
//   `.inputMonitoringDenied` when CGEvent.tapCreate returns nil. We catch both,
//   set `permissionsNeeded = true` (drives the menu hint), and log. The app
//   remains open so the user can grant permissions and restart via settings.

import Foundation
import SwiftUI
import AppKit
import SpeakCore

// MARK: - NullHistoryStore

/// A no-op `HistoryStoring` used when the production SQLite store fails to open.
/// Every method succeeds silently — the dictation flow is unaffected.
private final class NullHistoryStore: HistoryStoring, @unchecked Sendable {
    func save(_ entry: HistoryEntry) throws {}
    func recent(limit: Int) throws -> [HistoryEntry] { [] }
    func search(_ substring: String) throws -> [HistoryEntry] { [] }
    func clear() throws {}
    func export() throws -> String { "[]" }
}

// MARK: - DictationController

@MainActor
final class DictationController: ObservableObject {

    // MARK: - Published state

    /// The current menubar icon semantic — drives `MenuBarExtra` systemImage.
    @Published private(set) var icon: MenubarIcon = .idle

    /// `true` when the hotkey monitor failed to start due to missing permissions.
    /// Drives a ⚠️ hint in the menu so the user knows to grant permissions.
    @Published private(set) var permissionsNeeded: Bool = false

    /// The current running partial transcript text (empty when not listening).
    /// Exposed for the overlay view; not directly observed by SwiftUI here —
    /// the overlay panel has its own `OverlayViewModel`.
    @Published private(set) var partialText: String = ""

    /// Hardware-mute state (SPEC §7.4). Mirrors `engine.isMuted` for the menu
    /// checkmark. The authoritative state lives in the engine (the bypass-proof
    /// gate); this published copy is updated whenever the toggle changes.
    @Published private(set) var isMuted: Bool = false

    // MARK: - Private components

    private let engine: SpeakEngine
    private let monitor: HotkeyMonitor
    private var eventTask: Task<Void, Never>?

    /// The history store, shared with the engine. Exposed so the History window
    /// can read/search/clear/export the same persistent store the engine writes to.
    let historyStore: any HistoryStoring

    /// The History window controller. Created lazily on first show request.
    private var historyController: HistoryWindowController?

    // MARK: - Overlay (P4)

    /// View-model shared between this controller and the overlay panel's SwiftUI view.
    /// Created once; updated on the main actor via the partials task.
    private let overlayModel = OverlayViewModel()

    /// The floating overlay panel. Created lazily on first `startMonitoring()` call
    /// (NSPanel init requires a main-thread context — fine since this is @MainActor).
    /// Stored as `NSPanel` to avoid a hard import of `TranscriptOverlayPanel` type
    /// in tests that only depend on `SpeakCore`.
    private var overlayPanel: TranscriptOverlayPanel?

    /// Task that drains the `currentPartials()` stream and updates `overlayModel`.
    private var partialsTask: Task<Void, Never>?

    // MARK: - Settings store

    /// Shared settings store. Exposed so the Settings window can bind to it.
    /// One instance for the app lifetime; the engine reads from it at each
    /// `newSession()` call so toggle changes take effect per-dictation without
    /// an engine restart.
    private(set) var settingsStore: SettingsStore

    // MARK: - Onboarding

    /// The onboarding window controller. Created lazily on first show request.
    /// `nil` after onboarding is complete so it can be released.
    private var onboardingController: OnboardingWindowController?

    /// The live `PermissionManager` (shared with the onboarding flow).
    let permissionManager: PermissionManager

    // MARK: - Init

    init() {
        // --- Settings store (single instance for the app lifetime) ---
        // Created first; passed to the engine below so both the Settings
        // window and the engine share one source of truth.
        let store = SettingsStore()
        self.settingsStore = store

        // --- Permission manager (shared with onboarding) ---
        self.permissionManager = PermissionManager()

        // --- History store (best-effort) ---
        // `makeProductionStore()` throws if SQLite cannot be opened (e.g., disk
        // full, permissions, first-time directory creation fails). On failure,
        // substitute a no-op store so the rest of the pipeline is unaffected.
        let historyStore: any HistoryStoring
        do {
            historyStore = try HistoryStore.makeProductionStore()
        } catch {
            let storageDetail = error.localizedDescription
            SpeakLog.storage.error(
                "DictationController: HistoryStore open failed — without history. \(storageDetail, privacy: .public)"
            )
            historyStore = NullHistoryStore()
        }
        self.historyStore = historyStore

        // --- Engine (production wiring) ---
        // Transcriber and cleaner are chosen via the runtime factories (§10.1/§10a.1).
        // The cleanup toggle (`cleanupEnabled`) is re-read at each `newSession()`
        // call, so changes made via the Settings window apply on the next dictation.
        engine = SpeakEngine(
            transcriber: defaultTranscriber(for: store),
            cleaner: defaultCleaner(for: store),
            inserter: PasteboardWriter(),
            history: historyStore,
            settings: store
        )

        // --- Hotkey monitor ---
        monitor = HotkeyMonitor()
    }

    // MARK: - Public API

    /// Call once from `applicationDidFinishLaunching`. Arms the hotkey tap,
    /// creates the overlay panel, and begins consuming events. Safe to call
    /// exactly once; calling again is a no-op (the prior eventTask is still running).
    func startMonitoring() {
        // Show onboarding when any required permission is missing or the flag is not set.
        // Evaluated before arming the hotkey so the user is prompted immediately.
        showOnboardingIfNeeded()

        // Create the panel once here, on the main actor, so it is ready for the
        // first dictation without any lazy-init race.
        overlayPanel = TranscriptOverlayPanel(overlayModel: overlayModel)
        SpeakLog.hotkey.info("DictationController: startMonitoring() called — arming hotkey tap.")

        do {
            // Read monitor.events AFTER start() — start() allocates a fresh stream;
            // the placeholder from init() is dead.
            try monitor.start()
        } catch SpeakError.accessibilityDenied {
            SpeakLog.permissions.error(
                "DictationController: Accessibility permission denied — hotkey tap not armed."
            )
            permissionsNeeded = true
            // P7 revocation path: re-surface onboarding so the user can re-grant.
            // This handles mid-session revocation: if the user had previously granted
            // accessibility but revoked it between launches, this is the detection point.
            showOnboardingIfNeeded()
            return
        } catch SpeakError.inputMonitoringDenied {
            SpeakLog.permissions.error(
                "DictationController: Input Monitoring permission denied — hotkey tap not armed."
            )
            permissionsNeeded = true
            // P7 revocation path: same as above for Input Monitoring.
            showOnboardingIfNeeded()
            return
        } catch {
            let hotkeyDetail = error.localizedDescription
            SpeakLog.hotkey.error(
                "DictationController: monitor.start() failed unexpectedly — \(hotkeyDetail, privacy: .public)"
            )
            permissionsNeeded = true
            return
        }

        // Capture the event stream reference AFTER a successful start().
        let events = monitor.events

        eventTask = Task { [weak self] in
            for await event in events {
                guard let self else { break }
                await self.handle(event)
            }
            SpeakLog.hotkey.info("DictationController: event stream ended.")
        }
    }

    // MARK: - Onboarding

    /// Shows the onboarding window when the evaluation machine says it is incomplete.
    ///
    /// Called at launch and whenever a session-start failure indicates a permission
    /// was revoked mid-session (P7 done-when #3 — revocation → error path).
    func showOnboardingIfNeeded() {
        let eval = OnboardingStateMachine.evaluate(
            manager: permissionManager,
            hasCompletedOnboarding: settingsStore.hasCompletedOnboarding
        )
        guard !eval.isComplete else { return }
        SpeakLog.permissions.info(
            "DictationController: onboarding required — step=\(String(describing: eval.currentStep), privacy: .public)"
        )
        if onboardingController == nil {
            onboardingController = OnboardingWindowController(
                permissionManager: permissionManager,
                settings: settingsStore
            )
        }
        onboardingController?.show()
    }

    // MARK: - Private event handling

    /// Route a hotkey event to the engine verb and update published state.
    private func handle(_ event: HotkeyEvent) async {
        switch event {
        case .startCapture:
            await beginDictation()
        case .stopCapture:
            await endDictation()
        }
    }

    private func beginDictation() async {
        do {
            try await engine.beginDictation()
            icon = .listening
            SpeakLog.engine.info("DictationController: beginDictation succeeded → .listening")

            // P4: spawn the partials-streaming task and show the overlay.
            startOverlay()
        } catch SpeakError.microphoneMuted {
            // Hardware-mute refusal (SPEC §7.4) is NOT an error — the engine
            // declined to start capture by design. Stay idle; the menu shows the
            // mute state. No overlay, no audio, nothing read.
            icon = .idle
            SpeakLog.engine.info("DictationController: start ignored — microphone muted.")
        } catch {
            icon = .error
            SpeakLog.engine.error(
                "DictationController: beginDictation failed — \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    // MARK: - Hardware mute (SPEC §7.4)

    /// Toggle the hardware-mute state. Routes to the engine (the authoritative,
    /// bypass-proof gate) and mirrors the new value into `isMuted` for the menu.
    func toggleMute() {
        Task { [weak self] in
            guard let self else { return }
            let newValue = await self.engine.toggleMute()
            self.isMuted = newValue
        }
    }

    // MARK: - History window (P9)

    /// Show the History window, creating it lazily. Reads the same `historyStore`
    /// the engine writes to, so every completed dictation appears here.
    func showHistory() {
        if historyController == nil {
            historyController = HistoryWindowController(store: historyStore)
        }
        historyController?.show()
    }

    private func endDictation() async {
        do {
            // Show .processing during STT-finalize + cleanup (the await below),
            // so the menubar reflects every transition (idle→listening→processing
            // →done→idle), per roadmap P8. With Foundation Models unavailable this
            // is brief, but the state is still surfaced rather than skipped.
            icon = .processing
            _ = try await engine.endDictation()

            // P4: hide the overlay immediately when dictation succeeds (text pasted).
            stopOverlay()

            icon = .done
            SpeakLog.engine.info("DictationController: endDictation succeeded → .done")
            // Briefly show .done then return to .idle. Duration = 600 ms, the
            // single documented source for the done-flash: roadmap.md P8 done-when
            // ("Done green flash lasts 600ms then returns to idle"). Visual tuning
            // is P8 polish (deferred to human verification); this keeps the one
            // value consistent rather than inventing a second.
            try? await Task.sleep(nanoseconds: 600_000_000)
            icon = .idle
        } catch {
            // P4: hide the overlay on error too — dictation is over.
            stopOverlay()

            icon = .error
            SpeakLog.engine.error(
                "DictationController: endDictation failed — \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    // MARK: - Overlay lifecycle (P4)

    /// Show the overlay panel and begin streaming partial chunks into it.
    ///
    /// Called immediately after `beginDictation()` succeeds. Cancels any prior
    /// partials task (defensive — there should never be one) before spawning a
    /// new one so a stale stream cannot pollute the new session.
    private func startOverlay() {
        // Reset text and show the panel first so the user gets instant feedback.
        overlayModel.partialText = ""
        overlayPanel?.show()

        // Cancel any residual task from a prior dictation.
        partialsTask?.cancel()
        partialsTask = nil

        partialsTask = Task { [weak self] in
            guard let self else { return }

            // `currentPartials()` awaits the engine actor and returns the stream
            // for the *current* session (nil if the session already finished).
            guard let stream = await self.engine.currentPartials() else {
                SpeakLog.engine.info("DictationController: partials stream unavailable (session may have ended).")
                return
            }

            var accumulator = OverlayTextAccumulator()

            for await chunk in stream {
                // Check for cancellation before each update — the task may be
                // cancelled by stopOverlay() racing with the stream's natural end.
                if Task.isCancelled { break }

                let displayed = accumulator.next(chunk)
                // All @Published mutations must happen on the main actor.
                await MainActor.run {
                    self.overlayModel.partialText = displayed
                    self.partialText = displayed
                }
            }

            SpeakLog.engine.info("DictationController: partials stream finished.")
        }
    }

    /// Hide the overlay and tear down the partials task.
    ///
    /// Called on `.done` and `.error` (both terminate the dictation).
    private func stopOverlay() {
        partialsTask?.cancel()
        partialsTask = nil
        overlayModel.partialText = ""
        partialText = ""
        overlayPanel?.hide()
        SpeakLog.engine.info("DictationController: overlay hidden.")
    }
}
