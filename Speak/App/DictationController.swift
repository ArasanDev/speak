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
import CoreAudio
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

// MARK: - NullAgentCallStore

/// AVB-7: a no-op `AgentCallStoring` used when `AgentCallStore`'s SQLite open
/// fails. Mirrors `NullHistoryStore`'s degradation shape — the durable-call
/// surface is silently disabled for the session rather than crashing the app;
/// `speak_request_input`'s own round-trip is entirely unaffected (its durable
/// side effect is a best-effort write that swallows errors already).
private actor NullAgentCallStore: AgentCallStoring {
    func submit(_ submission: AgentCallSubmission) async throws -> AgentCallSubmitResult {
        throw SpeakError.unknown("AgentCallStore unavailable")
    }
    func get(id: UUID, requestingSessionId: String?) async throws -> AgentCall? { nil }
    func pendingAndPresented() async throws -> [AgentCall] { [] }
    func markPresented(id: UUID) async throws {}
    @discardableResult
    func resolve(id: UUID, outcome: HumanResponseOutcome) async throws -> Bool { false }
    func expireOverdue(now: Date) async throws {}
}

/// Open the production `AgentCallStore`, falling back to `NullAgentCallStore`
/// on failure. A free function (not a method) so `DictationController`'s own
/// class body stays under SwiftLint's `type_body_length` cap — pure code
/// motion, no behavior change, matching this file's existing precedent
/// (`applyAppearance`/`rebindExtraBindings` moved to an extension for the
/// same reason).
private func makeAgentCallStore() -> any AgentCallStoring {
    do {
        return try AgentCallStore.makeProductionStore()
    } catch {
        SpeakLog.storage.error(
            "DictationController: AgentCallStore open failed — durable calls disabled. \(error.localizedDescription, privacy: .public)"
        )
        return NullAgentCallStore()
    }
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
                // Seed the effective-input baseline for the route-change cue —
                // pinned-device-aware so a later topology/default event is
                // compared against what capture is actually using.
                lastEffectiveInputID = CoreAudioDeviceMonitor.shared
                    .resolvedInputDevice(preferredUID: settingsStore.preferredInputDeviceUID)?.id
                // Sensory edge: engage chime/haptic (Settings ▸ Hotkeys ▸ Feedback).
                DictationFeedback.play(
                    .engaged,
                    soundsEnabled: settingsStore.dictationFeedbackSounds,
                    hapticsEnabled: settingsStore.dictationFeedbackHaptics
                )
            } else if oldValue == .listening, icon != .listening {
                // Sensory edge: release chime/haptic on leave-listening
                // (processing, done, or error — the release cue still applies).
                DictationFeedback.play(
                    .released,
                    soundsEnabled: settingsStore.dictationFeedbackSounds,
                    hapticsEnabled: settingsStore.dictationFeedbackHaptics
                )
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
    /// Not `private(set)` — the setter is written from `DictationController+Session.swift`'s
    /// `toggleMute()` (same module, different file; Swift's `private` is file-scoped).
    var isMuted: Bool = false

    // MARK: - Private components

    let engine: SpeakEngine
    let monitor: HotkeyMonitor
    // nonisolated(unsafe): reachable from deinit for task cancellation.
    @ObservationIgnored
    nonisolated(unsafe) var eventTask: Task<Void, Never>?
    @ObservationIgnored
    nonisolated(unsafe) var armStateTask: Task<Void, Never>?
    /// CoreAudio default-input callback token — registered in `startMonitoring()`
    /// so a mid-dictation device switch plays the `.routeChanged` cue.
    /// nonisolated(unsafe): unregistered from deinit.
    @ObservationIgnored
    nonisolated(unsafe) var routeCueToken: UUID?
    /// Topology-channel twin of `routeCueToken` — needed so a *pinned* mic
    /// disappearing mid-dictation (no default change fires) still cues.
    @ObservationIgnored
    nonisolated(unsafe) var routeCueTopologyToken: UUID?
    /// The device capture is actually using, seeded on `.listening` entry —
    /// the cue compares against this so it fires on EFFECTIVE-input changes
    /// (pinned-device loss included), not merely OS default changes.
    private var lastEffectiveInputID: AudioDeviceID?
    @ObservationIgnored
    nonisolated(unsafe) var inputPrefObserverTask: Task<Void, Never>?

    let historyStore: any HistoryStoring

    /// The snippets store — owned here, shared with the engine (expansion at dictation
    /// start) and the dashboard's Snippets pane.
    let snippetStore = SnippetStore()

    /// The profile store (PE-2) — owned here, shared with the engine (profile resolution
    /// at dictation start) and the dashboard's AI Studio pane. One instance so an edit in
    /// AI Studio is the same set the engine reads on the next dictation.
    let profileStore = ProfileStore()

    /// The paste writer — held so the engine and the "Paste Last Transcript" action
    /// share one instance (re-paste writes the clipboard + simulates Cmd+V).
    let pasteboardWriter = PasteboardWriter()

    /// H-2: on-device TTS readback (specs/horizon-voice-os.md Pillar 2). One instance
    /// for the app's lifetime — `toggleReadback()` (DictationController+VoiceOut.swift)
    /// speaks `lastTranscript` or interrupts an in-flight readback. Internal (not
    /// `private`) so the `+VoiceOut` extension can reach it, matching `lastTranscript`/
    /// `lastRawTranscript`'s visibility below.
    let voiceOut: any SpeechSynthesizing
    let agentSpeechQueue: AgentSpeechQueue

    /// AVB-6 (specs/agent-voice-bridge.md §7.1): in-memory registry backing
    /// `speak_register_session` and sessionId threading through the rest of
    /// the agent-bridge tool surface. The TYPE lives in SpeakCore (so tests
    /// and AVB-7 can reuse it); this instance is owned here, alongside the
    /// rest of the CLI-handler state. [decision: AVB-6]
    let agentSessionRegistry = AgentSessionRegistry()

    /// AVB-7: durable-call store backing speak_submit_call/speak_get_call, the
    /// request_input adapter's side effect, and the inbox pane. Falls back to a
    /// no-op store on open failure, mirroring `historyStore`.
    let agentCallStore: any AgentCallStoring

    /// The most recent finished transcript (cleaned if available, else raw). Drives the
    /// "Paste Last Transcript" menu item; empty until the
    /// first dictation completes. Observed reactively so the menu enables/disables.
    var lastTranscript: String = ""

    /// PE-4: raw text from the last successful dictation, stored for `recleanCurrentTranscript()`.
    /// Nil until the first successful `endDictation()`. [decision PE-4]
    var lastRawTranscript: String?

    // MARK: - PE-3 live-panel shaping state (per-dictation, reversible)

    /// The destination profile resolved for the current/next dictation. Drives the live
    /// panel's destination row (which chip is active) and is the target the stop-time
    /// engine override applies. Resolved at `beginDictation` from the frontmost app, then
    /// mutated by a chip tap for THIS dictation ONLY — never writes `ProfileStore`, so the
    /// saved default is untouched. (PE-3, specs/live-panel-prompt-shaper.md.)
    /// Set by the `+LivePanel` extension; read at stop in `+ErrorHandling`. Module-internal.
    var activeDestination: Profile = DefaultProfiles.defaultProfile

    /// The Agent sub-category for the current dictation — only meaningful when
    /// `activeDestination` is the Agent destination. Defaults to `.task`. (PE-3.)
    var activeCategory: AgentCategory = .task

    /// True once the user has shaped THIS dictation via a chip. Gates the stop-time
    /// override: when false the session keeps the mode latched at start (`.styled` for the
    /// default path), preserving the verified v0-base behavior. Reset each `beginDictation`.
    /// Set by `+LivePanel`, read by `+ErrorHandling` at stop. Module-internal.
    var didOverrideThisSession = false

    /// True when the user's per-dictation override is `Raw` (AI off for this dictation) rather
    /// than a profile. Routes the stop-time apply to `applyRawOverride` instead of
    /// `applyProfileOverride`. Reset each `beginDictation`. (PE-3c.) Module-internal.
    var overrodeToRaw = false

    // MARK: - PE-3.2 pin-to-context state

    /// The frontmost app bundle ID captured at `beginDictation`. Empty string when no
    /// frontmost app was available. Set in `resolveActiveDestination(frontmostBundleID:)`.
    /// [decision PE-3.2]
    var activeBundleID: String = ""

    /// Consecutive manual-override count per bundle ID. Survives across dictation sessions
    /// (not reset in `resolveActiveDestination`) so the prompt fires on the 2nd override
    /// across two separate dictations to the same app. Reset to 0 after pinning or dismiss.
    /// [decision PE-3.2]
    var overrideCountPerApp: [String: Int] = [:]

    /// Provides per-app pinned destination+category. Initialized with `.standard` at init;
    /// injectable for tests. [decision PE-3.2]
    var pinnedContextStore: PinnedContextStore = PinnedContextStore()

    /// True when the "pin this destination?" banner should appear in the calm HUD.
    /// Synced to `overlayController.overlayModel` via `syncPinPromptToOverlay()`.
    /// [decision PE-3.2]
    var showPinPrompt: Bool = false

    // MARK: - Collaborators (H3)

    /// Owns the overlay lifecycle (model + panel + partials drain).
    /// H-UI: constructed in `init()` (not at property-declaration time) so it
    /// can share the same `SettingsStore` instance as `self.settingsStore` —
    /// required for `OverlayRootView`'s live `hudStyle` switch to observe
    /// changes made from `SettingsView` (a second, separate `SettingsStore`
    /// instance would read the same `UserDefaults` but never fire `@Observable`
    /// change notifications to this one).
    let overlayController: OverlayController

    /// P2.2: Caret-anchored raw-preview panel. Shown alongside the main HUD while
    /// listening; hidden at every terminal state. Separate from the main overlay.
    /// Internal (not private) so the +ErrorHandling extension can call show/hide.
    let caretOverlay = CaretOverlayController()

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
    var commandModeController: CommandModeController?
    @ObservationIgnored
    nonisolated(unsafe) var commandChordTask: Task<Void, Never>?

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

    /// CLI IPC server (W2.3): owns the named CFMessagePort server for the `speak` CLI tool.
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

    /// [V01-5] The current set of extra (additive) hotkey bindings, up to 4 per
    /// action. Observed reactively so the Shortcuts settings tab refreshes its
    /// list without a relaunch. Updated atomically by `rebindExtraBindings(_:)`.
    private(set) var activeExtraBindings: ExtraBindingSet = .empty

    /// Apply a new extra-bindings set from the Shortcuts settings editor (V01-5).
    ///
    /// Single point of truth, mirroring `rebindHotkey(_:)`:
    ///   1. `monitor.updateExtraBindings` — swaps the live set, rebuilds the tap's
    ///      mask only if mouse-binding presence flipped, persists via the
    ///      monitor's own `BindingStoring`.
    ///   2. Updates `settingsStore.extraBindings` (the user-facing mirror) so the
    ///      next-launch reconcile in `init` converges on the saved value.
    ///   3. Publishes `activeExtraBindings` so the Settings UI refreshes.
    ///
    /// Must be called on the main actor (this class is `@MainActor`).
    /// Implementation in the extra-bindings extension below ([lint] type_body_length).

    // MARK: - Trigger-mode wiring (Phase B)

    /// Task that re-arms observation tracking each time `settingsStore.triggerMode`
    /// changes, applying the new trigger to the live monitor without relaunch.
    ///
    /// Uses `withObservationTracking` (from `@Observable`) instead of a Combine
    /// subscription — fires only on `triggerMode` mutations (not on every settings
    /// write), so the dedupe guard is a last-defence against same-value writes.
    @ObservationIgnored
    nonisolated(unsafe) private var triggerModeObserverTask: Task<Void, Never>?

    /// The last trigger applied to the live monitor. [validation-fix NEW-7]
    /// Guards against same-value `withMutation` fires that would produce spurious
    /// `updateBinding` + UserDefaults writes.
    private var lastAppliedTrigger: HotkeyBinding.Trigger = .doubleTap

    /// [V01-5] Task that re-arms observation tracking each time
    /// `settingsStore.extraBindings` changes, applying the new set to the live
    /// monitor without relaunch. Same `withObservationTracking` pattern as
    /// `triggerModeObserverTask`.
    @ObservationIgnored
    nonisolated(unsafe) private var extraBindingsObserverTask: Task<Void, Never>?

    /// [V01-5] The last extra-bindings set applied to the live monitor — dedupe
    /// guard against same-value `withMutation` fires, mirroring `lastAppliedTrigger`.
    private var lastAppliedExtraBindings: ExtraBindingSet = .empty

    /// The last appearance theme applied to NSApplication.
    /// Guards against redundant appearance updates.
    private var lastAppliedAppearance: AppTheme = .system

    /// The in-flight appearance observation task, cancelled when a new one replaces it.
    @ObservationIgnored
    nonisolated(unsafe) private var appearanceObserverTask: Task<Void, Never>?

    // MARK: - Onboarding

    let permissionManager: PermissionManager

    // MARK: - Init

    init() {
        let speechSynthesizer = AppleSpeechSynthesizer()
        self.voiceOut = speechSynthesizer
        self.agentSpeechQueue = AgentSpeechQueue(synthesizer: speechSynthesizer)
        let store = SettingsStore()
        self.settingsStore = store
        self.overlayController = OverlayController(settingsStore: store)
        // Felt-speed filmstrip: reuse the engine's cleaner for live per-block AI polish.
        // `defaultCleaner(for:)` is the same stateless factory the engine uses, so
        // availability + engine selection always match. [decision: felt-speed]
        overlayController.filmstripCleaner = defaultCleaner(for: store)
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

        self.agentCallStore = makeAgentCallStore()

        engine = SpeakEngine(
            transcriber: DictationController.resolveTranscriber(for: store),
            cleaner: defaultCleaner(for: store),
            inserter: pasteboardWriter,
            history: historyStore,
            settings: store,
            snippetStore: snippetStore,
            profileStore: profileStore,
            // [H-1] Voice Actions live executor (specs/horizon-voice-os.md, Pillar 1).
            // ShortcutsCLIExecutor is all-SpeakCore (wraps `/usr/bin/shortcuts`), so the
            // engine stays AppKit-free. Consulted only when `settings.voiceActionsEnabled`
            // is on (default false → zero behavior change).
            voiceActionsExecutor: ShortcutsCLIExecutor(),
            // [H-1] Voice Actions `.command` route: wired to the same App-layer AX
            // conformer (`AccessibilitySelection`) already used in production by the
            // pre-H-1 Command Mode feature (`CommandModeController`, line ~584 below).
            // `defaultCleaner(for: store)` is the same stateless factory used for the
            // `cleaner:` param above — called again here (matching the established
            // pattern at `commandModeController`'s construction) rather than caching an
            // instance. `nil` only when cleanup is disabled (`defaultCleaner` returns
            // `nil`), in which case `.command` degrades to dictation, same as the
            // `voiceActionsExecutor == nil` case. The live AX read/replace I/O itself
            // remains [deferred — human verification]: grant Accessibility, select text
            // in TextEdit/Slack, confirm read + replace — only the wiring is verified
            // here (see CommandModeServiceTests for the unit-tested orchestration).
            voiceActionsCommandService: defaultCleaner(for: store).map {
                CommandModeService(selection: AccessibilitySelection(), cleaner: $0)
            }
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

        // [V01-5] Reconcile extra bindings the same way as trigger mode:
        // `settingsStore.extraBindings` (own key) is the user-facing authoritative
        // value; `monitor`'s own `BindingStoring`-backed copy may be stale/absent
        // (e.g. after an install that predates V01-5). Apply the settings value now.
        let initialExtraBindings = store.extraBindings
        monitor.updateExtraBindings(initialExtraBindings)
        activeExtraBindings = initialExtraBindings
        lastAppliedExtraBindings = initialExtraBindings
        SpeakLog.hotkey.info(
            "DictationController: extra bindings applied at init — count=\(initialExtraBindings.bindings.count, privacy: .public)"
        )
        startObservingExtraBindings()

        // Apply appearance theme on init.
        let initialAppearance = store.appTheme
        applyAppearance(initialAppearance)
        lastAppliedAppearance = initialAppearance

        // Start observing future appearance theme changes from SettingsView.
        startObservingAppearance()

        // Mic picker (Settings → Microphone): apply the persisted pin now and
        // observe future changes — setting it mid-dictation live-switches the
        // capture via AudioCapture's preference didSet → rebuild path.
        // [decision: pinned-device selection]
        engine.setPreferredInputDeviceUID(store.preferredInputDeviceUID)
        startObservingInputDevicePreference()

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


    /// Re-arming observation loop for `settingsStore.preferredInputDeviceUID` —
    /// pushes picker changes into the engine, which re-resolves the effective
    /// input and live-switches a running capture when it actually differs.
    private func startObservingInputDevicePreference() {
        inputPrefObserverTask?.cancel()
        inputPrefObserverTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self else { break }
                await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                    withObservationTracking {
                        _ = self.settingsStore.preferredInputDeviceUID
                    } onChange: {
                        continuation.resume()
                    }
                }
                guard !Task.isCancelled else { break }
                let uid = self.settingsStore.preferredInputDeviceUID
                self.engine.setPreferredInputDeviceUID(uid)
                SpeakLog.audio.info(
                    "DictationController: mic preference changed → \(uid ?? "system default", privacy: .public)"
                )
            }
        }
    }

    // MARK: - Appearance theme observation
    // `applyAppearance(_:)` lives in the extension below ([lint] type_body_length).

    /// Re-arming observation loop: tracks `settingsStore.appTheme` via
    /// `withObservationTracking` and applies changes to NSApplication appearance.
    ///
    /// `withObservationTracking` is one-shot — the loop re-arms after each fire.
    /// Dedupes same-value writes to avoid redundant NSApplication.appearance updates.
    private func startObservingAppearance() {
        appearanceObserverTask?.cancel()
        appearanceObserverTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self else { break }
                await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                    withObservationTracking {
                        _ = self.settingsStore.appTheme
                    } onChange: {
                        continuation.resume()
                    }
                }
                guard !Task.isCancelled else { break }
                let newTheme = self.settingsStore.appTheme
                guard newTheme != self.lastAppliedAppearance else { continue }
                self.lastAppliedAppearance = newTheme
                self.applyAppearance(newTheme)
                SpeakLog.storage.info(
                    "DictationController: appearance theme changed — \(newTheme.rawValue, privacy: .public)"
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
        // and presents the onboarding window or the dashboard window on launch.
        ensureWindowPresenter().showInitialWindowIfNeeded()

        // Delegate panel creation to OverlayController — panel is expensive and
        // must be created once, not per-dictation. [task #32] The overlay no longer
        // hosts a Settings gear; Settings is reached from the menu bar / dashboard.
        overlayController.createPanel()
        // W2.2 (updated): wire Escape stop — when the user presses Escape while
        // actively dictating, stop the session and paste (same path as single-press stop).
        // Guard on `icon == .listening` prevents re-entrancy: if the session has already
        // transitioned to `.processing` or `.error` the press is a no-op.
        // P2.2: forward partial-text updates from the main overlay drain to the
        // caret panel. Called on the main actor (onPartialTextUpdated fires inside
        // MainActor.run in OverlayController's drain task).
        overlayController.onPartialTextUpdated = { [weak self] text in
            self?.caretOverlay.update(partialText: text)
            // P2.3: track the latest non-empty partial so showProcessing() can display
            // it during the cleanup window. Guard: don't clobber with empty partials
            // (SpeechAnalyzer may emit an empty chunk at window boundaries).
            if !text.isEmpty {
                self?.lastRawTranscript = text
            }
        }

        // [fix: wedge] The partials stream ending on its own while the icon is
        // still `.listening` means the session's stream died underneath us
        // (e.g. unrecoverable route change → `captureInterrupted` → failStream →
        // `.error` → partials finished). Run the normal endDictation path so the
        // stored error surfaces on the HUD and the engine releases the session,
        // instead of wedging the menubar in a dead listening state.
        overlayController.onPartialsEnded = { [weak self] in
            await self?.handlePartialsStreamEnded()
        }

        overlayController.onEscapeStop = { [weak self] in
            guard let self else { return }
            // [PE-3c] If the profile-selector card is open, Escape closes IT first — a
            // graceful exit that does NOT stop the dictation (recording keeps running).
            if self.overlayController.isProfilePanelOpen {
                self.overlayController.closeProfilePanel()
                SpeakLog.engine.info("DictationController: Escape closed the profile panel (dictation continues).")
                return
            }
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

        registerRouteChangeCue()

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
        registerCLIPortAndSweepAgentCalls()
    }

    /// Route-change cue: fires when the EFFECTIVE input changes while we're
    /// listening — headset grabbing the default, active mic unplugged →
    /// fallback, or a pinned device (dis)connecting. Registers on both HAL
    /// channels because a pinned-device loss changes what we're capturing
    /// without ever changing the system default. Idle changes don't cue —
    /// the Settings roster + capture-side rebuild handle those. Callbacks
    /// arrive on arbitrary threads; gate + feedback run on the main actor.
    private func registerRouteChangeCue() {
        routeCueToken = CoreAudioDeviceMonitor.shared.registerCallback { _ in
            Task { @MainActor [weak self] in self?.evaluateRouteCue() }
        }
        routeCueTopologyToken = CoreAudioDeviceMonitor.shared.registerTopologyCallback { _ in
            Task { @MainActor [weak self] in self?.evaluateRouteCue() }
        }
    }

    /// Compares the resolved input against the dictation-start baseline and
    /// plays `.routeChanged` when they differ — the cue means "the mic
    /// feeding you changed," not "the OS default changed."
    private func evaluateRouteCue() {
        guard icon == .listening else { return }
        let resolved = CoreAudioDeviceMonitor.shared.resolvedInputDevice(
            preferredUID: settingsStore.preferredInputDeviceUID
        )
        guard let resolved, resolved.id != lastEffectiveInputID else { return }
        lastEffectiveInputID = resolved.id
        SpeakLog.audio.info(
            "DictationController: effective input switched mid-dictation → \(resolved.name, privacy: .public)"
        )
        DictationFeedback.play(
            .routeChanged,
            soundsEnabled: settingsStore.dictationFeedbackSounds,
            hapticsEnabled: settingsStore.dictationFeedbackHaptics
        )
    }

    // MARK: - Window presentation (delegates to WindowPresenter)

    /// Show onboarding if setup is incomplete; otherwise show the dashboard.
    func showInitialWindowIfNeeded() {
        ensureWindowPresenter().showInitialWindowIfNeeded()
    }

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

    /// Re-arms the hotkey tap, checks and registers permissions, cancels any stuck sessions,
    /// and prewarms speech recognition to restore full app health.
    func selfHeal() {
        SpeakLog.app.info("DictationController: executing self-heal routine...")
        cancelDictation()
        monitor.start()
        let axTrusted = permissionManager.status(.accessibility) == .granted
        permissionsNeeded = !axTrusted
        _ = permissionManager.status(.microphone)
        SpeechPrewarmer.shared.prewarm(locale: settingsStore.language)
        SpeakLog.app.info("DictationController: self-heal completed successfully.")
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

    // MARK: - Hardware mute, task management, and event handling
    // (`toggleMute`, `startArmStateTask`, `startCommandChordTask`, `startEventTask`,
    // `handle(_:)`) moved to `DictationController+Session.swift` ([lint] type_body_length)
    // — pure code motion, no behavior change.

    // Cancel every active Task loop on deallocation.
    deinit {
        triggerModeObserverTask?.cancel()
        appearanceObserverTask?.cancel()
        extraBindingsObserverTask?.cancel()
        eventTask?.cancel()
        armStateTask?.cancel()
        commandChordTask?.cancel()
        inputPrefObserverTask?.cancel()
        if let routeCueToken {
            CoreAudioDeviceMonitor.shared.unregisterCallback(routeCueToken)
        }
        if let routeCueTopologyToken {
            CoreAudioDeviceMonitor.shared.unregisterCallback(routeCueTopologyToken)
        }
    }

}

#if DEBUG
// MARK: - Debug helpers
//
// [lint] In an extension (not the class body) to keep `DictationController`
// under SwiftLint's `type_body_length` cap — pure code motion.
extension DictationController {
    /// Force the menubar icon to a specific state, held indefinitely.
    /// Used by `--debug-open menubar-icon-<state>` for visual color verification.
    /// Never compiled into release builds.
    func forceIcon(_ state: MenubarIcon) {
        icon = state
        SpeakLog.engine.info(
            "DictationController: [DEBUG] icon forced to .\(String(describing: state), privacy: .public)"
        )
    }
}
#endif

// MARK: - Extra-bindings observation (V01-5)
//
// [lint] Moved out of the main class body into a `private extension` to keep
// `DictationController`'s type body under SwiftLint's `type_body_length` cap —
// pure code motion, no behavior change. `private` members declared in the class
// remain reachable from an extension of the same type in the same file
// (Swift's file-scoped access rule): `extraBindingsObserverTask`,
// `settingsStore`, `lastAppliedExtraBindings`, `monitor`, `activeExtraBindings`.
extension DictationController {

    /// Apply the theme to NSApplication.shared.appearance based on the AppTheme
    /// setting. Moved here for [lint] type_body_length — pure code motion.
    /// Registers the CLI port and runs the AVB-7 recovery sweep (any call whose
    /// `expiresAt` passed while the app was closed becomes `.expired`, not stuck
    /// `.pending` forever). Bundled into one call from `startMonitoring()` and
    /// moved here for [lint] type_body_length — pure code motion, no behavior change.
    func registerCLIPortAndSweepAgentCalls() {
        cliPortServer.register(handler: self)
        Task { [agentCallStore] in
            do {
                try await agentCallStore.expireOverdue(now: Date())
            } catch {
                SpeakLog.storage.error(
                    "DictationController: AgentCallStore.expireOverdue on launch failed — \(error.localizedDescription, privacy: .public)"
                )
            }
        }
    }

    func applyAppearance(_ theme: AppTheme) {
        let appearance: NSAppearance? = {
            switch theme {
            case .light:
                return NSAppearance(named: .aqua)
            case .dark:
                return NSAppearance(named: .darkAqua)
            case .system:
                return nil  // nil lets macOS follow system setting
            }
        }()
        NSApplication.shared.appearance = appearance
    }

    /// Apply a new extra-bindings set from the Shortcuts settings editor (V01-5).
    /// See the declaration note in the class body; moved here for
    /// [lint] type_body_length. Same file, so private members stay reachable.
    func rebindExtraBindings(_ newSet: ExtraBindingSet) {
        monitor.updateExtraBindings(newSet)
        lastAppliedExtraBindings = newSet
        settingsStore.extraBindings = newSet
        activeExtraBindings = newSet
        SpeakLog.hotkey.info(
            "DictationController: extra bindings rebound — count=\(newSet.bindings.count, privacy: .public)"
        )
    }

    /// [V01-5] Re-arming observation loop: tracks `settingsStore.extraBindings`
    /// via `withObservationTracking` and applies changes to the live monitor.
    /// Same shape as `startObservingTriggerMode()`.
    func startObservingExtraBindings() {
        extraBindingsObserverTask?.cancel()
        extraBindingsObserverTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self else { break }
                await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                    withObservationTracking {
                        _ = self.settingsStore.extraBindings
                    } onChange: {
                        continuation.resume()
                    }
                }
                guard !Task.isCancelled else { break }
                let newSet = self.settingsStore.extraBindings
                guard newSet != self.lastAppliedExtraBindings else { continue }
                self.lastAppliedExtraBindings = newSet
                self.monitor.updateExtraBindings(newSet)
                self.activeExtraBindings = newSet
                SpeakLog.hotkey.info(
                    "DictationController: extra bindings changed — count=\(newSet.bindings.count, privacy: .public)"
                )
            }
        }
    }
}
