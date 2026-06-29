// App/DictationController.swift
//
// The app's brain. Replaces `MicTestController` (retired at P5/P8 keystone).
//
// Responsibilities:
//   - Constructs the production `SpeakEngine` from real components.
//   - Owns a `HotkeyMonitor` and bridges its events to the engine verbs.
//   - Publishes `icon: MenubarIcon` (drives the menu-bar label).
//   - Publishes `permissionsNeeded: Bool` (drives a hint in the menu).
//   - Delegates overlay lifecycle to `OverlayController`.
//   - Delegates window presentation to `WindowPresenter`.
//
// Honesty boundary: the end-to-end behavior (double-tap Fn, paste at cursor,
// real-time icon) is [deferred — human verification required]. The only
// autonomously-verified piece is the MenubarIcon mapping (unit tests).
//
// Threading:
//   - `DictationController` is `@MainActor`: all observable property mutations are
//     on the main thread (required by SwiftUI and the Observation framework).
//   - `SpeakEngine` and `HistoryStore` are actors: all calls to them are `await`.
//   - The hotkey-event Task reads `monitor.events` (an AsyncStream) and awaits
//     engine calls; it captures `[weak self]` to avoid a retain cycle.
//   - The arm-state Task reads `monitor.armStateChanges` and updates
//     `permissionsNeeded` on the main actor when the tap arms/disarms.
//
// Re-arm wiring (Phase A):
//   `HotkeyMonitor` manages its own re-arm watchdog internally. `DictationController`
//   calls `monitor.start()` once from `startMonitoring()`. If AX is not yet granted
//   at that point, the monitor's 100ms watchdog will arm the tap as soon as AX is
//   granted — no relaunch required.
//
//   When the tap arms, `monitor.armStateChanges` yields `true`, which this
//   controller receives on a background Task and routes to the @MainActor to clear
//   `permissionsNeeded` and spawn the event-consume Task if it hasn't been yet.
//
// History-store degradation:
//   `HistoryStore.makeProductionStore()` throws (SQLite open can fail). On
//   failure we log via `SpeakLog.storage` and continue with a no-op
//   `NullHistoryStore`. The dictation flow (capture → cleanup → paste) is
//   unaffected; history is silently disabled for the session.
//
// Permission-denied degradation:
//   `HotkeyMonitor.start()` is non-throwing (Phase A). The monitor handles its
//   own retry. `permissionsNeeded` is set when AX is missing; cleared when the
//   arm-state stream yields `true`.

import AppKit
import Combine
import Foundation
import Observation
import SpeakCore
import SwiftUI

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

@Observable
@MainActor
final class DictationController: CLICommandHandler {

    // MARK: - Observable state

    /// The current menubar icon semantic — drives `MenuBarExtra` systemImage.
    var icon: MenubarIcon = .idle {
        didSet {
            if icon == .listening, oldValue != .listening {
                _hotkeySubject.send()
            }
        }
    }

    /// `true` when the hotkey monitor has not yet armed (AX not granted).
    /// Drives a ⚠️ hint in the menu so the user knows to grant permissions.
    var permissionsNeeded: Bool = false

    /// The current running partial transcript text (empty when not listening).
    /// Mirrors `overlayController.partialText` for callers that observe this controller.
    private(set) var partialText: String = ""

    /// Hardware-mute state (SPEC §7.4). Mirrors `engine.isMuted` for the menu
    /// checkmark. The authoritative state lives in the engine.
    private(set) var isMuted: Bool = false

    // MARK: - Private components

    let engine: SpeakEngine
    let monitor: HotkeyMonitor
    private var eventTask: Task<Void, Never>?
    private var armStateTask: Task<Void, Never>?

    let historyStore: any HistoryStoring

    /// The snippets store — owned here, shared with the engine (expansion at dictation
    /// start) and the dashboard's Snippets pane.
    let snippetStore = SnippetStore()

    /// The paste writer — held so the engine and the "Paste Last Transcript" action
    /// share one instance (re-paste writes the clipboard + simulates Cmd+V).
    private let pasteboardWriter = PasteboardWriter()

    /// The most recent finished transcript (cleaned if available, else raw). Drives the
    /// "Paste Last Transcript" menu item (Wispr's Ctrl+Cmd+V re-paste); empty until the
    /// first dictation completes. Observed reactively so the menu enables/disables.
    var lastTranscript: String = ""

    // MARK: - Collaborators (H3)

    /// Owns the overlay lifecycle (model + panel + partials drain).
    let overlayController = OverlayController()

    /// Owns History, Onboarding, and Dashboard window presentation.
    /// Nil until first access — constructed lazily via `ensureWindowPresenter()` so
    /// that `showDashboard()` / `showHistory()` / `showOnboardingIfNeeded()` work
    /// whether or not `startMonitoring()` has been called (e.g. the DEBUG path or
    /// a very-early menu open before monitoring arms).
    /// [decision: lazy guard, not init-time construction — keeps showDashboard / showHistory /
    ///  showOnboardingIfNeeded safe whether or not startMonitoring() has run.]
    private var windowPresenter: WindowPresenter?

    /// Drives Command Mode (Wave D) from the Fn+Ctrl chord. Constructed in
    /// `startMonitoring()`; consumes `monitor.commandChordEvents`.
    private var commandModeController: CommandModeController?
    private var commandChordTask: Task<Void, Never>?

    /// Fires on the main thread each time `icon` transitions idle → listening.
    /// Used by `ensureWindowPresenter()` to supply `hotkeyFiredPublisher` to the
    /// onboarding flow without requiring a Combine `@Published` projected value.
    private let _hotkeySubject = PassthroughSubject<Void, Never>()

    /// Fires on the main thread after a dictation completes successfully (done or error state).
    /// Used by the dashboard Home pane to refresh recent dictations list after a new entry
    /// is saved to history. [decision P11-c: fires after completion, allowing the history
    /// save to be processed before the refresh query runs]
    /// Accessible to extensions (DictationController+ErrorHandling) for firing the signal.
    let dictationCompletedSubject = PassthroughSubject<Void, Never>()

    // MARK: - CLI IPC server (W2.3)

    /// Owns the named CFMessagePort server for the `speak` CLI tool.
    /// Registered in `startMonitoring()` — not before, so the test host path
    /// (XCTestConfigurationFilePath early-return) never opens the port.
    /// [decision: W2.3 — server lifetime = app lifetime]
    private let cliPortServer = CLIPortServer()

    // MARK: - Settings store

    private(set) var settingsStore: SettingsStore

    /// The current active hotkey binding. Observed reactively so the Shortcuts settings tab
    /// refreshes its "Current Hotkey" label without a relaunch.
    /// Updated atomically by `rebindHotkey(_:)` alongside `monitor.updateBinding`.
    /// [decision: W1.1 — observable so SwiftUI can react to recorder saves]
    private(set) var activeBinding: HotkeyBinding = .defaultBinding

    /// The human-readable label for the current hotkey binding, e.g. "⌘ Right Command ×2".
    /// Forwarded from the live `HotkeyMonitor.binding.displayString` so the Settings
    /// Shortcuts tab can show a read-only summary without accessing the private monitor.
    /// [decision: W3.1 — Settings shows binding read-only; recorder added in W1.1]
    var currentHotkeyDisplayString: String { monitor.binding.displayString }

    /// Apply a new hotkey binding from the recorder sheet (W1.1).
    ///
    /// This is the single point of truth for a rebind:
    ///   1. `monitor.updateBinding` — swaps the live tap binding AND persists via
    ///      `UserDefaultsBindingStore.save` [verified: HotkeyMonitor.updateBinding, 2026-06-22].
    ///   2. Updates `settingsStore.triggerMode` so the next-launch reconcile in
    ///      `DictationController.init` converges on the saved trigger.
    ///      The `withObservationTracking` loop fires after this write; the dedupe
    ///      guard skips it because `lastAppliedTrigger` was already updated above.
    ///   3. Publishes `activeBinding` so the Settings UI refreshes without relaunch.
    ///
    /// Must be called on the main actor (this class is `@MainActor`).
    func rebindHotkey(_ newBinding: HotkeyBinding) {
        monitor.updateBinding(newBinding)
        lastAppliedTrigger = newBinding.trigger  // [validation-fix NEW-7] keep dedupe baseline in sync
        settingsStore.triggerMode = newBinding.trigger
        activeBinding = newBinding
        SpeakLog.hotkey.info(
            "DictationController: hotkey rebound — keyCode=\(newBinding.keyCode, privacy: .public) trigger=\(newBinding.trigger.rawValue, privacy: .public)"
        )
    }

    // MARK: - Trigger-mode wiring (Phase B)

    /// Task that re-arms observation tracking each time `settingsStore.triggerMode`
    /// changes, applying the new trigger to the live monitor without relaunch.
    ///
    /// Uses `withObservationTracking` (from `@Observable`) instead of a Combine
    /// subscription — fires only on `triggerMode` mutations (not on every settings
    /// write), so the dedupe guard is a last-defence against same-value writes.
    private var triggerModeObserverTask: Task<Void, Never>?

    /// The last trigger applied to the live monitor. [validation-fix NEW-7]
    /// Guards against same-value `withMutation` fires that would produce spurious
    /// `updateBinding` + UserDefaults writes.
    private var lastAppliedTrigger: HotkeyBinding.Trigger = .doubleTap

    // MARK: - Onboarding

    let permissionManager: PermissionManager

    // MARK: - Init

    init() {
        let store = SettingsStore()
        self.settingsStore = store
        self.permissionManager = PermissionManager()

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

        engine = SpeakEngine(
            transcriber: defaultTranscriber(for: store),
            cleaner: defaultCleaner(for: store),
            inserter: pasteboardWriter,
            history: historyStore,
            settings: store,
            snippetStore: snippetStore
        )

        monitor = HotkeyMonitor()

        // Phase B: apply the persisted trigger mode to the monitor on launch.
        // `monitor = HotkeyMonitor()` loads the persisted `HotkeyBinding` via
        // `UserDefaultsBindingStore`, but `SettingsStore.triggerMode` is the
        // user-facing authoritative value — reconcile them now.
        let initialTrigger = store.triggerMode
        let updatedBinding = monitor.binding.with(trigger: initialTrigger)
        monitor.updateBinding(updatedBinding)
        // Seed `activeBinding` from the reconciled initial binding so the Settings UI
        // shows the correct key on first open. [decision: set after reconcile, W1.1]
        activeBinding = updatedBinding
        lastAppliedTrigger = initialTrigger  // [validation-fix NEW-7] seed the dedupe baseline
        SpeakLog.hotkey.info("DictationController: trigger mode applied at init — \(initialTrigger.rawValue, privacy: .public)")

        // Start observing future trigger-mode changes from SettingsView.
        // Uses withObservationTracking — fires only on triggerMode mutations.
        startObservingTriggerMode()
    }

    // MARK: - Trigger-mode observation

    /// Re-arming observation loop: tracks `settingsStore.triggerMode` via
    /// `withObservationTracking` and applies changes to the live monitor.
    ///
    /// `withObservationTracking` is one-shot — the loop re-arms after each fire.
    /// After `onChange` fires, we read the new value on the main actor (the task
    /// is `@MainActor`) then dedupe and apply. [validation-fix NEW-7]
    private func startObservingTriggerMode() {
        triggerModeObserverTask?.cancel()
        triggerModeObserverTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self else { break }
                await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                    withObservationTracking {
                        _ = self.settingsStore.triggerMode
                    } onChange: {
                        continuation.resume()
                    }
                }
                guard !Task.isCancelled else { break }
                let newTrigger = self.settingsStore.triggerMode
                guard newTrigger != self.lastAppliedTrigger else { continue }
                self.lastAppliedTrigger = newTrigger
                let newBinding = self.monitor.binding.with(trigger: newTrigger)
                self.monitor.updateBinding(newBinding)
                SpeakLog.hotkey.info(
                    "DictationController: trigger mode changed — \(newTrigger.rawValue, privacy: .public)"
                )
            }
        }
    }

    // MARK: - Lazy WindowPresenter construction

    /// Returns the live `WindowPresenter`, constructing it on the first call.
    ///
    /// Construction is deferred out of `init()` so `showDashboard()` /
    /// `showHistory()` / `showOnboardingIfNeeded()` work whether or not
    /// `startMonitoring()` has run (DEBUG path, early menu click, normal startup).
    ///
    /// [decision: guarded-lazy over non-optional `let` — avoids the init-time
    ///  definite-initialisation constraint while still guaranteeing a non-nil result
    ///  to every caller without a silent `?` optional chain no-op.]
    @discardableResult
    private func ensureWindowPresenter() -> WindowPresenter {
        if let existing = windowPresenter { return existing }

        // Derive a publisher that fires (on the main thread) each time the hotkey
        // triggers a new dictation session. `_hotkeySubject` fires in `icon.didSet`
        // on the idle → listening edge — the observable proxy for hotkey fires.
        // Already on the main actor so no receive(on:) hop needed.
        let hotkeyFiredPublisher = _hotkeySubject
            .receive(on: RunLoop.main)
            .eraseToAnyPublisher()

        let presenter = WindowPresenter(
            historyStore: historyStore,
            permissionManager: permissionManager,
            settingsStore: settingsStore,
            snippetStore: snippetStore,
            hotkeyComboProvider: { [weak self] in self?.currentHotkeyCombo() ?? ["Fn"] },
            hotkeyFiredPublisher: hotkeyFiredPublisher,
            dictationController: self
        )
        windowPresenter = presenter
        return presenter
    }

    // MARK: - Public API

    // MARK: - startMonitoring

    /// Call once from `applicationDidFinishLaunching`. Arms the hotkey tap
    /// asynchronously and begins consuming events. Safe to call exactly once.
    ///
    /// Phase A: `monitor.start()` is non-throwing. If AX is not yet granted,
    /// the monitor's 100ms watchdog will arm the tap on the untrusted→trusted
    /// edge. This controller responds via `armStateChanges`.
    func startMonitoring() {
        // WindowPresenter is now constructed lazily via ensureWindowPresenter() —
        // calling it here both guarantees it exists for the lifetime of monitoring
        // and triggers the onboarding check on the first clean launch.
        ensureWindowPresenter().showOnboardingIfNeeded()

        // Delegate panel creation to OverlayController — panel is expensive and
        // must be created once, not per-dictation. [task #32] The overlay no longer
        // hosts a Settings gear; Settings is reached from the menu bar / dashboard.
        overlayController.createPanel()
        // W2.2 (updated): wire Escape stop — when the user presses Escape while
        // actively dictating, stop the session and paste (same path as single-press stop).
        // Guard on `icon == .listening` prevents re-entrancy: if the session has already
        // transitioned to `.processing` or `.error` the press is a no-op.
        overlayController.onEscapeStop = { [weak self] in
            guard let self else { return }
            if self.icon == .listening {
                Task { [weak self] in await self?.endDictation() }
            } else if self.icon == .error {
                // [App-M2] Error HUD has no Escape-dismiss path. When Escape is
                // pressed during an error state, dismiss the overlay and reset to
                // idle — the session is already terminal so endDictation() must
                // not be called again.
                self.overlayController.cancelImmediate()
                self.icon = .idle
            }
        }
        SpeakLog.hotkey.info("DictationController: startMonitoring() — arming monitor.")

        // Check immediate AX state to set the initial permissionsNeeded hint.
        let axGranted = permissionManager.status(.accessibility) == .granted
        if !axGranted {
            permissionsNeeded = true
        }

        // Signal the monitor to arm. Arming is async — the watchdog will fire
        // when AX is granted. If already granted, it arms on the first tick.
        monitor.start()

        // Consume arm-state changes so we can react when the tap arms/disarms.
        startArmStateTask()

        // Consume hotkey events. The stream is stable for the monitor's lifetime;
        // events arrive once the tap is armed. Starting the consume task early
        // (before arm) is safe — it just waits on the AsyncStream.
        startEventTask()

        // Command Mode (Wave D): construct the controller + consume the Fn+Ctrl chord
        // stream. [deferred — human verification: the live chord gesture + AX edit.]
        commandModeController = CommandModeController(
            settings: settingsStore,
            cleaner: defaultCleaner(for: settingsStore)
        )
        startCommandChordTask()

        // CLI IPC server (W2.3): register the named CFMessagePort so `speak --start`,
        // `--stop`, and `--status` can drive this running instance.
        // Called AFTER the XCTestConfigurationFilePath early-return in AppDelegate
        // ensures the port is never opened during test-host runs.
        cliPortServer.register(handler: self)
    }

    // MARK: - Window presentation (delegates to WindowPresenter)

    /// Show the Onboarding window if the onboarding flow is not yet complete.
    /// Delegates to `WindowPresenter.showOnboardingIfNeeded()`.
    func showOnboardingIfNeeded() {
        ensureWindowPresenter().showOnboardingIfNeeded()
    }

    /// Show the History window (P9).
    /// Called from `SpeakApp.swift` via the menu button.
    /// Delegates to `WindowPresenter.showHistory()`.
    func showHistory() {
        ensureWindowPresenter().showHistory()
    }

    /// Show the full-window dashboard (Phase-2 UI spine).
    /// Called from `SpeakApp.swift` via the menu button.
    /// Delegates to `WindowPresenter.showDashboard()`.
    func showDashboard() {
        ensureWindowPresenter().showDashboard()
    }

    /// Show the Settings window.
    /// Called from the overlay gear icon or menu.
    /// Delegates to `WindowPresenter.showSettings()`.
    func showSettings() {
        ensureWindowPresenter().showSettings()
    }

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
            self.icon = .idle
            self.monitor.notifySessionEnded()  // [validation-fix C1] keep detector in sync
            SpeakLog.engine.info("DictationController: dictation cancelled by user (Escape).")
        }
    }

    /// Re-paste the most recent finished transcript at the current cursor (Wispr's
    /// "Paste Last Transcript" / Ctrl+Cmd+V). No-op until the first dictation completes.
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

    /// Publisher that fires when a dictation completes (success or error).
    /// Used by the dashboard Home pane to refresh recent dictations after a new
    /// entry is saved to history. [decision P11-c]
    var dictationCompletedPublisher: AnyPublisher<Void, Never> {
        dictationCompletedSubject.eraseToAnyPublisher()
    }

    /// The current hotkey rendered as keycap labels for the dashboard.
    /// Double-tap shows the key symbol twice; hold shows it once.
    /// The symbol is derived from `HotkeyBinding.keySymbol` so it updates
    /// automatically when the user changes the binding (e.g., Fn → Right-Command).
    private func currentHotkeyCombo() -> [String] {
        let currentBinding = monitor.binding
        let keyLabel = currentBinding.keySymbol  // "Fn", "⌘", etc.
        switch currentBinding.trigger {
        case .doubleTap: return [keyLabel, keyLabel]
        case .hold:      return [keyLabel]
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
                self.icon = .idle
            }
        }
    }

    // MARK: - Private task management

    /// Start consuming `monitor.armStateChanges` to update `permissionsNeeded`.
    /// On arm: clear the hint and ensure the event-consume task is running.
    private func startArmStateTask() {
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
    private func startCommandChordTask() {
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
    private func startEventTask() {
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

    private func handle(_ event: HotkeyEvent) async {
        switch event {
        case .startCapture:
            await beginDictation()

        case .stopCapture:
            await endDictation()
        }
    }

#if DEBUG
    // MARK: - Debug helpers

    /// Force the menubar icon to a specific state, held indefinitely.
    /// Used by `--debug-open menubar-icon-<state>` for visual color verification.
    /// Never compiled into release builds.
    func forceIcon(_ state: MenubarIcon) {
        icon = state
        SpeakLog.engine.info(
            "DictationController: [DEBUG] icon forced to .\(String(describing: state), privacy: .public)"
        )
    }
#endif
}
