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
    private var historyController: HistoryWindowController?

    // MARK: - Overlay (P4)

    private let overlayModel = OverlayViewModel()
    private var overlayPanel: TranscriptOverlayPanel?
    private var partialsTask: Task<Void, Never>?

    // MARK: - Settings store

    private(set) var settingsStore: SettingsStore

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

    private var onboardingController: OnboardingWindowController?
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
            inserter: PasteboardWriter(),
            history: historyStore,
            settings: store
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

    // MARK: - Public API

    /// Call once from `applicationDidFinishLaunching`. Arms the hotkey tap
    /// asynchronously and begins consuming events. Safe to call exactly once.
    ///
    /// Phase A: `monitor.start()` is non-throwing. If AX is not yet granted,
    /// the monitor's 100ms watchdog will arm the tap on the untrusted→trusted
    /// edge. This controller responds via `armStateChanges`.
    func startMonitoring() {
        showOnboardingIfNeeded()
        overlayPanel = TranscriptOverlayPanel(overlayModel: overlayModel)
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
    }

    // MARK: - Onboarding

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

    // MARK: - Hardware mute (SPEC §7.4)

    func toggleMute() {
        Task { [weak self] in
            guard let self else { return }
            let nowMuted = await self.engine.toggleMute()
            self.isMuted = nowMuted
            if nowMuted {
                self.stopOverlay()
                self.icon = .idle
            }
        }
    }

    // MARK: - History window (P9)

    func showHistory() {
        if historyController == nil {
            historyController = HistoryWindowController(store: historyStore)
        }
        historyController?.show()
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
            startOverlay()
        } catch SpeakError.microphoneMuted {
            icon = .idle
            SpeakLog.engine.info("DictationController: start ignored — microphone muted.")
        } catch {
            icon = .error
            SpeakLog.engine.error(
                "DictationController: beginDictation failed — \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    private func endDictation() async {
        do {
            // Phase C: transition overlay to .processing before the cleanup await.
            // This keeps the panel visible showing "Cleaning up…" during the LLM pass.
            // The panel is hidden AFTER the done flash, not immediately on stop.
            icon = .processing
            transitionOverlay(to: .processing)
            _ = try await engine.endDictation()
            icon = .done
            // Phase C: show done state briefly before hiding the panel.
            transitionOverlay(to: .done)
            SpeakLog.engine.info("DictationController: endDictation succeeded → .done")
            // 600ms done-flash — roadmap.md P8 [decision].
            let doneFlashNanoseconds: UInt64 = 600_000_000  // [decision] roadmap.md P8
            try? await Task.sleep(nanoseconds: doneFlashNanoseconds)
            stopOverlay()
            icon = .idle
        } catch SpeakError.pasteRequiresAccessibility {
            // Graceful degradation: text was written to the clipboard (the
            // clipboard-floor step in PasteboardWriter always runs), but
            // synthetic Cmd+V was skipped because AX is not granted.
            // Outcome: NOT a fault — the user can paste manually (Cmd+V).
            // Mirror the `.microphoneMuted` soft-catch pattern: hide overlay,
            // stay idle, surface the permissions hint via `permissionsNeeded`.
            stopOverlay()
            icon = .idle
            permissionsNeeded = true
            SpeakLog.engine.info(
                "DictationController: paste fell back to clipboard — Accessibility needed"
            )
        } catch {
            // Error: hide the panel immediately — no done flash on failure.
            stopOverlay()
            icon = .error
            SpeakLog.engine.error(
                "DictationController: endDictation failed — \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    // MARK: - Overlay lifecycle (Phase C)

    private func startOverlay() {
        // Reset to listening state with empty text before showing.
        overlayModel.partialText = ""
        overlayModel.overlayState = .listening
        overlayPanel?.show()
        partialsTask?.cancel()
        partialsTask = nil

        partialsTask = Task { [weak self] in
            guard let self else { return }
            guard let stream = await self.engine.currentPartials() else {
                SpeakLog.engine.info("DictationController: partials stream unavailable.")
                return
            }

            var accumulator = OverlayTextAccumulator()
            for await chunk in stream {
                if Task.isCancelled { break }
                let displayed = accumulator.next(chunk)
                await MainActor.run {
                    self.overlayModel.partialText = displayed
                    self.partialText = displayed
                }
            }
            SpeakLog.engine.info("DictationController: partials stream finished.")
        }
    }

    /// Transition the overlay to a new visual state.
    /// Cancels the partials task when moving to .processing (no more partials coming).
    /// Does NOT hide the panel — `stopOverlay()` is responsible for hiding.
    private func transitionOverlay(to state: OverlayState) {
        overlayModel.overlayState = state
        if state == .processing {
            // No more partial text will arrive once processing begins.
            partialsTask?.cancel()
            partialsTask = nil
        }
        SpeakLog.engine.info(
            "DictationController: overlay transitioned to .\(String(describing: state), privacy: .public)"
        )
    }

    /// Hide the overlay panel and reset all overlay state.
    /// Call this only AFTER the done flash is complete (or immediately on error).
    private func stopOverlay() {
        partialsTask?.cancel()
        partialsTask = nil
        overlayModel.partialText = ""
        overlayModel.overlayState = .listening   // reset for next dictation
        partialText = ""
        overlayPanel?.hide()
        SpeakLog.engine.info("DictationController: overlay hidden.")
    }
}
