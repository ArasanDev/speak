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

    // MARK: - Private components

    private let engine: SpeakEngine
    private let monitor: HotkeyMonitor
    private var eventTask: Task<Void, Never>?

    // MARK: - Settings store

    /// Shared settings store. Exposed so the Settings window can bind to it.
    /// One instance for the app lifetime; the engine reads from it at each
    /// `newSession()` call so toggle changes take effect per-dictation without
    /// an engine restart.
    private(set) var settingsStore: SettingsStore

    // MARK: - Init

    init() {
        // --- Settings store (single instance for the app lifetime) ---
        // Created first; passed to the engine below so both the Settings
        // window and the engine share one source of truth.
        let store = SettingsStore()
        self.settingsStore = store

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

    /// Call once from `applicationDidFinishLaunching`. Arms the hotkey tap and
    /// begins consuming events. Safe to call exactly once; calling again is a no-op
    /// (the prior eventTask is still running).
    func startMonitoring() {
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
            return
        } catch SpeakError.inputMonitoringDenied {
            SpeakLog.permissions.error(
                "DictationController: Input Monitoring permission denied — hotkey tap not armed."
            )
            permissionsNeeded = true
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
        } catch {
            icon = .error
            SpeakLog.engine.error(
                "DictationController: beginDictation failed — \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    private func endDictation() async {
        do {
            // Show .processing during STT-finalize + cleanup (the await below),
            // so the menubar reflects every transition (idle→listening→processing
            // →done→idle), per roadmap P8. With Foundation Models unavailable this
            // is brief, but the state is still surfaced rather than skipped.
            icon = .processing
            _ = try await engine.endDictation()
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
            icon = .error
            SpeakLog.engine.error(
                "DictationController: endDictation failed — \(error.localizedDescription, privacy: .public)"
            )
        }
    }
}
