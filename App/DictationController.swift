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
//   - `DictationController` is `@MainActor`: all `@Published` mutations are
//     on the main thread (required by SwiftUI/Combine).
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

import Foundation
import SwiftUI
import AppKit
import Combine
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

    /// `true` when the hotkey monitor has not yet armed (AX not granted).
    /// Drives a ⚠️ hint in the menu so the user knows to grant permissions.
    @Published private(set) var permissionsNeeded: Bool = false

    /// The current running partial transcript text (empty when not listening).
    /// Mirrors `overlayController.partialText` for callers that observe this controller.
    @Published private(set) var partialText: String = ""

    /// Hardware-mute state (SPEC §7.4). Mirrors `engine.isMuted` for the menu
    /// checkmark. The authoritative state lives in the engine.
    @Published private(set) var isMuted: Bool = false

    // MARK: - Private components

    private let engine: SpeakEngine
    private let monitor: HotkeyMonitor
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
    /// first dictation completes. `@Published` so the menu enables/disables reactively.
    @Published private(set) var lastTranscript: String = ""

    // MARK: - Collaborators (H3)

    /// Owns the overlay lifecycle (model + panel + partials drain).
    private let overlayController = OverlayController()

    /// Owns History, Onboarding, and Dashboard window presentation.
    /// Nil until first access — constructed lazily via `ensureWindowPresenter()` so
    /// that `showDashboard()` / `showHistory()` / `showOnboardingIfNeeded()` work
    /// whether or not `startMonitoring()` has been called (e.g. the DEBUG path or
    /// a very-early menu open before monitoring arms).
    /// [decision: lazy guard, not init-time construction — hotkeyFiredPublisher derives
    /// from self.$icon via a Combine pipeline, which requires self to be fully initialised
    /// before the publisher can be formed without a definite-initialisation compile error.]
    private var windowPresenter: WindowPresenter?

    /// Drives Command Mode (Wave D) from the Fn+Ctrl chord. Constructed in
    /// `startMonitoring()`; consumes `monitor.commandChordEvents`.
    private var commandModeController: CommandModeController?
    private var commandChordTask: Task<Void, Never>?

    // MARK: - Settings store

    private(set) var settingsStore: SettingsStore

    /// The human-readable label for the current hotkey binding, e.g. "⌘ Right Command ×2".
    /// Forwarded from the live `HotkeyMonitor.binding.displayString` so the Settings
    /// Shortcuts tab can show a read-only summary without accessing the private monitor.
    /// [decision: W3.1 — Settings shows binding read-only; W3.2 will add the record UI]
    var currentHotkeyDisplayString: String { monitor.binding.displayString }

    // MARK: - Trigger-mode wiring (Phase B)

    /// Holds the Combine subscription that applies `settingsStore.triggerMode`
    /// changes to the live monitor without relaunch.
    ///
    /// `objectWillChange` fires *before* the value is written, so the `sink`
    /// callback defers reading via `DispatchQueue.main.async`. The async hop
    /// also ensures we are not on any SwiftUI rendering path when we call
    /// `monitor.updateBinding(_:)`.
    private var triggerModeCancellable: AnyCancellable?

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
        SpeakLog.hotkey.info("DictationController: trigger mode applied at init — \(initialTrigger.rawValue, privacy: .public)")

        // Subscribe to future trigger-mode changes from SettingsView.
        // `objectWillChange` fires before the write, so we schedule a read for
        // the next run-loop turn when the value has settled.
        triggerModeCancellable = store.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    let newTrigger = self.settingsStore.triggerMode
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
    /// Construction is deferred out of `init()` for two reasons:
    /// 1. `hotkeyFiredPublisher` is derived from `self.$icon` (a Combine `@Published`
    ///    pipeline), which requires `self` to be fully initialised before access.
    /// 2. Keeps `showDashboard()` / `showHistory()` / `showOnboardingIfNeeded()` safe
    ///    whether or not `startMonitoring()` has run — the DEBUG launch path, an early
    ///    menu click, and the normal startup path all converge here.
    ///
    /// [decision: guarded-lazy over non-optional `let` — avoids the init-time
    ///  definite-initialisation constraint while still guaranteeing a non-nil result
    ///  to every caller without a silent `?` optional chain no-op.]
    @discardableResult
    private func ensureWindowPresenter() -> WindowPresenter {
        if let existing = windowPresenter { return existing }

        // Derive a publisher that fires (on the main thread) each time the hotkey
        // triggers a new dictation session. `$icon` transitions to `.listening` on
        // every startCapture event — this is the observable proxy for hotkey fires.
        // `.removeDuplicates()` ensures we only emit on the idle→listening EDGE,
        // not if `.listening` is re-published while already listening.
        // `receive(on: RunLoop.main)` ensures the subscriber (onboarding VM) hops to
        // the main thread before touching @Published properties.
        let hotkeyFiredPublisher = $icon
            .removeDuplicates()
            .filter { $0 == .listening }
            .map { _ in () }
            .receive(on: RunLoop.main)
            .eraseToAnyPublisher()

        let presenter = WindowPresenter(
            historyStore: historyStore,
            permissionManager: permissionManager,
            settingsStore: settingsStore,
            snippetStore: snippetStore,
            hotkeyComboProvider: { [weak self] in self?.currentHotkeyCombo() ?? ["Fn"] },
            hotkeyFiredPublisher: hotkeyFiredPublisher
        )
        windowPresenter = presenter
        return presenter
    }

    // MARK: - Public API

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
        // must be created once, not per-dictation.
        overlayController.createPanel()
        // W2.2 (updated): wire Escape stop — when the user presses Escape while
        // actively dictating, stop the session and paste (same path as single-press stop).
        // Guard on `icon == .listening` prevents re-entrancy: if the session has already
        // transitioned to `.processing` or `.error` the press is a no-op.
        overlayController.onEscapeStop = { [weak self] in
            guard let self, self.icon == .listening else { return }
            Task { [weak self] in
                await self?.endDictation()
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
                        self.permissionsNeeded = true
                        SpeakLog.hotkey.warning("DictationController: tap disarmed — permissionsNeeded set.")
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

    private func beginDictation() async {
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

    private func endDictation() async {
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
        }
    }
}
