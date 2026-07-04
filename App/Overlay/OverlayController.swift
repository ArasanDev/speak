// App/Overlay/OverlayController.swift
//
// Owns the overlay lifecycle: OverlayViewModel, TranscriptOverlayPanel,
// the partials-drain Task, the W2.1 level-drain Task, the Escape-cancel monitor,
// and the start / transition(to:) / stop surface.
//
// Responsibilities:
//   - Holds the `OverlayViewModel` (the model that drives `TranscriptOverlayView`).
//   - Constructs and owns the single `TranscriptOverlayPanel` (created lazily at
//     `createPanel()`, called from `DictationController.startMonitoring()` so the
//     NSHostingView cost is paid once, not per-dictation).
//   - `start(partialsProvider:levelsProvider:isCleaningUp:)` — resets the model,
//     shows the panel, drains partials and level values, and arms the Escape monitor.
//   - `transition(to:)` — updates the model state.
//   - `stop()` — cancels all tasks, resets the model, hides the panel.
//   - `showError(_:)` — transitions to `.error` with a reason; a retry affordance
//     is shown in the HUD. Call AFTER stop() has not been called (the panel stays
//     visible in error state so the user can act).
//   - `cancelImmediate()` — hides immediately without done-flash (mute cancel; Escape now routes to stop).
//
// W2.1 — Live level drain:
//   A parallel `levelsTask` runs alongside `partialsTask`. It drains
//   `AsyncStream<Double>` from the audio-engine RMS feed, applies one-pole smoothing
//   via `levelSmoothed(previous:target:)`, and writes `overlayModel.level` on every
//   value. Torn down identically to `durationTask` on transition/stop.
//
// W2.2 — Escape-to-stop:
//   A global `NSEvent.addGlobalMonitorForEvents(matching:)` handler intercepts
//   Escape keystrokes while the panel is visible. A *global* monitor is used (not
//   local) because the panel is non-activating and the app is LSUIElement; a local
//   monitor never fires when another app is focused. Global monitors cannot consume
//   (suppress) the event — which is fine: we want Escape to also dismiss dialogs in
//   the target app if the user pressed it there. The monitor is installed at
//   `start()` and removed at `stop()` / `cancelImmediate()`.
//   Escape is treated as a stop-and-paste gesture (same as single-press stop), NOT
//   as a cancel. The `onEscapeStop` callback is guarded by the caller on
//   `icon == .listening` to avoid re-entrancy during `.processing` or `.error`.
//   [decision W2.2: Escape = stop+paste, not cancel; guard is in DictationController]
//
// Threading:
//   - `OverlayController` is `@MainActor`. All mutations of `overlayModel` and
//     `partialText` are on the main thread.
//   - The drain Tasks run on a background executor but post to MainActor
//     via `MainActor.run { }` when writing to the model.
//   - `[weak self]` captures avoid retain cycles in drain Tasks.

import AppKit
import SpeakCore
import SwiftUI

// MARK: - OverlayController

@MainActor
final class OverlayController {

    // MARK: - Internals (internal for @testable access in SpeakTests)

    /// The view-model bound to `TranscriptOverlayView`. Internal so tests can
    /// assert on `overlayState` and `partialText` without going through the panel.
    let overlayModel = OverlayViewModel()

    /// The running partial transcript text — mirrors `overlayModel.partialText` so callers
    /// that only need the string (e.g. the enclosing `DictationController`) can
    /// observe it without referencing the model directly.
    private(set) var partialText: String = ""

    // MARK: - Private

    private var panel: TranscriptOverlayPanel?
    /// P-Code: the second, dynamically-sized panel for the "Code" Agent category's
    /// real-time customization surface. Created lazily on first open (see
    /// `ensureCodingPanel()`) — mirrors `CaretOverlayController`'s lazy-panel pattern,
    /// not `TranscriptOverlayPanel`'s create-once-at-`createPanel()` pattern, since this
    /// panel is opened only occasionally rather than for every dictation.
    private var codingPanel: CodingCustomizationPanel?
    private var partialsTask: Task<Void, Never>?
    /// W2.1: parallel task draining the RMS level stream into `overlayModel.level`.
    private var levelsTask: Task<Void, Never>?
    /// 1 Hz timer driving the HUD duration counter. Lives only while listening.
    private var durationTask: Task<Void, Never>?
    /// W2.2: global NSEvent monitor for the Escape key. Installed while the panel
    /// is showing, removed on stop/cancel. Nil when idle.
    /// `NSEvent.addGlobalMonitorForEvents` returns `Any?` not `NSObjectProtocol`.
    private var escapeMonitor: Any?
    /// W2.2: callback invoked when the user presses Escape while dictating.
    /// The caller is responsible for guarding on the active-capture state to
    /// prevent re-entrancy during `.processing` or `.error` (see DictationController).
    var onEscapeStop: (() -> Void)?

    /// P2.2: callback invoked on the main actor each time the partial transcript
    /// text updates. Used by `CaretOverlayController` to track the in-flight text
    /// without creating a coupling from OverlayController to the caret overlay.
    var onPartialTextUpdated: ((String) -> Void)?

    // MARK: - Init

    init() {
        // P-Code: pure overlay/UI concern — wired directly here rather than via
        // `DictationController` (unlike `onSelectDestination`/`onSelectCategory`, which
        // route per-dictation engine state). Opening/closing the second panel never
        // touches the engine or the saved profile, so no coupling to DictationController
        // is needed.
        overlayModel.onCodingPanelOpenChanged = { [weak self] isOpen in
            self?.setCodingPanelOpen(isOpen)
        }
    }

    // MARK: - Panel setup (call once from startMonitoring)

    /// Create the overlay panel. Call exactly once from `DictationController.startMonitoring()`.
    /// Creating the panel here (not in init) matches the original timing: the NSHostingView
    /// is expensive and we defer that cost until monitoring actually starts.
    func createPanel() {
        guard panel == nil else { return }
        panel = TranscriptOverlayPanel(
            overlayModel: overlayModel
        )
    }

    // MARK: - PE-3 live-panel destination strip

    /// Configure the destination chips shown while listening. Called by `DictationController`
    /// at dictation start with the resolved active destination + a tap handler. Pass empty
    /// `choices` to hide the strip (e.g. AI cleanup off). (specs/live-panel-prompt-shaper.md.)
    func configureDestinationStrip(
        choices: [OverlayDestinationChoice],
        active: OverlayDestinationChoice?,
        activeCategory: AgentCategory,
        onSelect: @escaping (OverlayDestinationChoice) -> Void,
        onSelectCategory: @escaping (AgentCategory) -> Void
    ) {
        overlayModel.destinationChoices = choices
        overlayModel.activeDestinationChoice = active
        overlayModel.activeCategory = activeCategory
        overlayModel.onSelectDestination = onSelect
        overlayModel.onSelectCategory = onSelectCategory
    }

    /// PE-4: Wire the per-dictation knob callbacks into the overlay model. Called by
    /// `DictationController` in `beginDictation` alongside `configureDestinationStrip`.
    /// `onKnobChanged` fires when any knob changes (signals DictationController to flag
    /// the session as overridden). `onCancel` routes to `cancelDictation()`.
    func configureKnobs(
        onKnobChanged: @escaping () -> Void,
        onCancel: @escaping () -> Void,
        onReclean: @escaping () -> Void
    ) {
        overlayModel.onKnobChanged = onKnobChanged
        overlayModel.onCancel = onCancel
        overlayModel.onReclean = onReclean
    }

    /// Update the highlighted Agent category after a tap (per-dictation override).
    func setActiveCategory(_ category: AgentCategory) {
        overlayModel.activeCategory = category
    }

    /// Update which destination chip is highlighted after a tap (per-dictation override).
    func setActiveDestinationChoice(_ choice: OverlayDestinationChoice?) {
        overlayModel.activeDestinationChoice = choice
    }

    /// Whether the anchored profile-selector card is currently covering the HUD.
    var isProfilePanelOpen: Bool { overlayModel.isProfilePanelOpen }

    /// Close the profile-selector card (Escape, or after a selection). Idempotent.
    /// Also resets the card to its destinations page so the next open starts there.
    func closeProfilePanel() {
        overlayModel.isProfilePanelOpen = false
        overlayModel.isShowingAgentCategories = false
    }

    // MARK: - P-Code coding customization panel

    /// Show or hide `CodingCustomizationPanel`, anchored above the base HUD panel's
    /// current frame. Creating the panel lazily on first open (see `ensureCodingPanel()`).
    private func setCodingPanelOpen(_ isOpen: Bool) {
        if isOpen {
            let baseFrame = panel?.frame ?? .zero
            let codingPanel = ensureCodingPanel()
            codingPanel.show(anchoredAbove: baseFrame)
        } else {
            codingPanel?.hide()
        }
    }

    /// Lazily construct `CodingCustomizationPanel`, bound to the same `overlayModel`
    /// instance the base HUD uses (knob state stays in sync between the two panels).
    private func ensureCodingPanel() -> CodingCustomizationPanel {
        if let existing = codingPanel { return existing }
        let created = CodingCustomizationPanel(overlayModel: overlayModel)
        codingPanel = created
        return created
    }

    /// Force-close the coding panel without going through `overlayModel.isCodingPanelOpen`
    /// (used when resetting overlay state wholesale in `start()`/`stop()`/`cancelImmediate()`).
    private func resetCodingPanel() {
        overlayModel.isCodingPanelOpen = false
        codingPanel?.hide()
    }

    // MARK: - PE-3.2 pin-to-context banner

    /// Show the pin-suggestion banner in the calm HUD below the waveform row.
    func showPinBanner(label: String, onPin: @escaping () -> Void, onDismissPin: @escaping () -> Void) {
        overlayModel.pinContextLabel = label
        overlayModel.onPin = onPin
        overlayModel.onDismissPin = onDismissPin
        overlayModel.showPinPrompt = true
    }

    /// Hide the pin-suggestion banner. Idempotent.
    func hidePinBanner() {
        overlayModel.showPinPrompt = false
    }

    // MARK: - Lifecycle

    /// Show the overlay in the `.listening` state and begin draining partial
    /// transcript chunks and RMS levels.
    ///
    /// - Parameters:
    ///   - partialsProvider: Returns the partials `AsyncStream<TranscriptChunk>?`.
    ///   - levelsProvider: Returns the levels `AsyncStream<Double>?` (W2.1).
    ///     Passing a nil-returning closure is safe — the levels task exits early
    ///     and the bar chart falls back to the idle-breathing animation.
    ///   - isCleaningUp: `true` when AI cleanup will run after capture ends.
    ///     Controls the "Cleaning up…" vs "Pasting…" copy in `.processing` state (W2.2).
    func start(
        partialsProvider: @escaping () async -> AsyncStream<TranscriptChunk>?,
        levelsProvider: @escaping () async -> AsyncStream<Double>?,
        isCleaningUp: Bool
    ) {
        // Reset to listening state with empty text before showing.
        overlayModel.partialText = ""
        overlayModel.overlayState = .listening
        overlayModel.elapsedSeconds = 0
        overlayModel.level = 0.0
        overlayModel.errorReason = nil
        overlayModel.isCleaningUp = isCleaningUp
        overlayModel.isProfilePanelOpen = false   // PE-3c: always start on the calm HUD
        overlayModel.isShowingAgentCategories = false
        overlayModel.showPinPrompt = false         // PE-3.2: reset pin banner
        overlayModel.perDictationFormat = .asIs    // PE-4: reset knob overrides each dictation
        overlayModel.perDictationTone = .neutral
        overlayModel.perDictationLength = .preserve
        overlayModel.onKnobChanged = nil
        overlayModel.onCancel = nil
        overlayModel.onReclean = nil
        overlayModel.customInstructions = ""       // P-Code v2: reset per-dictation prompt addition
        resetCodingPanel()                         // P-Code: always start with the panel closed
        partialText = ""
        panel?.show()

        // Drive the HUD duration counter at 1 Hz while listening.
        startDurationTimer()

        // W2.1: start the level drain task.
        startLevelsDrain(provider: levelsProvider)

        // W2.2: arm the Escape-key global monitor while the panel is visible.
        installEscapeMonitor()

        partialsTask?.cancel()
        partialsTask = nil

        partialsTask = Task { [weak self] in
            guard let self else { return }
            guard let stream = await partialsProvider() else {
                SpeakLog.engine.info("OverlayController: partials stream unavailable.")
                return
            }

            var accumulator = OverlayTextAccumulator()
            for await chunk: TranscriptChunk in stream {
                if Task.isCancelled { break }
                let displayed = accumulator.next(chunk)
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    self.overlayModel.partialText = displayed
                    self.partialText = displayed
                    self.onPartialTextUpdated?(displayed)
                }
            }
            SpeakLog.engine.info("OverlayController: partials stream finished.")
        }
    }

    /// Transition the overlay to a new visual state.
    ///
    /// Cancels the partials + levels tasks when moving to `.processing` — no more
    /// chunks or level values will arrive once the engine transitions to cleanup.
    func transition(to state: OverlayState) {
        overlayModel.overlayState = state
        if state == .processing {
            // No more partial text or level data will arrive once processing begins.
            partialsTask?.cancel()
            partialsTask = nil
            levelsTask?.cancel()
            levelsTask = nil
            // Reset level to 0 — bars should be at rest during processing.
            overlayModel.level = 0.0
            // Stop the duration counter — dictation has ended, cleanup is running.
            durationTask?.cancel()
            durationTask = nil
        }
        SpeakLog.engine.info(
            "OverlayController: overlay transitioned to .\(String(describing: state), privacy: .public)"
        )
    }

    /// Hide the overlay panel and reset all overlay state.
    ///
    /// Call this AFTER the done flash is complete (or immediately on error).
    /// Safe to call when the panel was never shown — hide is a no-op in that case.
    func stop() {
        partialsTask?.cancel()
        partialsTask = nil
        levelsTask?.cancel()
        levelsTask = nil
        durationTask?.cancel()
        durationTask = nil
        removeEscapeMonitor()
        overlayModel.partialText = ""
        overlayModel.overlayState = .listening   // reset for next dictation
        overlayModel.elapsedSeconds = 0
        overlayModel.level = 0.0
        overlayModel.errorReason = nil
        overlayModel.isCleaningUp = false
        overlayModel.isProfilePanelOpen = false   // PE-3c: reset the selector card
        overlayModel.isShowingAgentCategories = false
        overlayModel.showPinPrompt = false         // PE-3.2: reset pin banner
        overlayModel.perDictationFormat = .asIs    // PE-4: reset knob overrides
        overlayModel.perDictationTone = .neutral
        overlayModel.perDictationLength = .preserve
        overlayModel.onKnobChanged = nil
        overlayModel.onCancel = nil
        overlayModel.customInstructions = ""       // P-Code v2: reset per-dictation prompt addition
        overlayModel.defaultSystemPrompt = ""      // P-Code v2: reset until next beginDictation
        resetCodingPanel()   // P-Code: close the coding panel with the rest of overlay state
        partialText = ""
        panel?.hide()
        SpeakLog.engine.info("OverlayController: overlay hidden.")
    }

    /// W2.2: Show an error state in the HUD with a short reason string.
    ///
    /// Cancels all running tasks, leaves the panel visible so the user sees
    /// the error. Call `stop()` after the user acknowledges (or after a timeout).
    /// [decision W2.2: brief reason surfaced in the HUD instead of silent hide]
    func showError(_ reason: String) {
        partialsTask?.cancel()
        partialsTask = nil
        levelsTask?.cancel()
        levelsTask = nil
        durationTask?.cancel()
        durationTask = nil
        // Ensure escape monitor is installed so the user can dismiss via Escape,
        // even if start() never ran (begin-failure path). installEscapeMonitor() is
        // idempotent — it removes any prior monitor before installing a new one.
        installEscapeMonitor()
        overlayModel.level = 0.0
        overlayModel.errorReason = reason
        overlayModel.overlayState = .error
        // Ensure panel is showing — if beginDictation never called start(), show now.
        panel?.show()
        SpeakLog.engine.info(
            "OverlayController: error state shown — \(reason, privacy: .public)"
        )
    }

    /// W2.2: Immediate cancel — hide the panel without a done-flash. Used for
    /// Escape-to-cancel and mute. Resets identically to `stop()`.
    func cancelImmediate() {
        partialsTask?.cancel()
        partialsTask = nil
        levelsTask?.cancel()
        levelsTask = nil
        durationTask?.cancel()
        durationTask = nil
        removeEscapeMonitor()
        overlayModel.partialText = ""
        overlayModel.overlayState = .listening
        overlayModel.elapsedSeconds = 0
        overlayModel.level = 0.0
        overlayModel.errorReason = nil
        overlayModel.isCleaningUp = false
        overlayModel.isProfilePanelOpen = false   // PE-3c: reset the selector card
        overlayModel.isShowingAgentCategories = false
        overlayModel.showPinPrompt = false         // PE-3.2: reset pin banner
        overlayModel.perDictationFormat = .asIs    // PE-4: reset knob overrides
        overlayModel.perDictationTone = .neutral
        overlayModel.perDictationLength = .preserve
        overlayModel.onKnobChanged = nil
        overlayModel.onCancel = nil
        overlayModel.customInstructions = ""       // P-Code v2: reset per-dictation prompt addition
        overlayModel.defaultSystemPrompt = ""      // P-Code v2: reset until next beginDictation
        resetCodingPanel()   // P-Code: close the coding panel with the rest of overlay state
        partialText = ""
        panel?.hide()
        SpeakLog.engine.info("OverlayController: dictation cancelled (immediate hide).")
    }

    // MARK: - Duration timer

    /// Increment `overlayModel.elapsedSeconds` once per second while listening.
    private func startDurationTimer() {
        durationTask?.cancel()
        durationTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                if Task.isCancelled { break }
                await MainActor.run { [weak self] in
                    self?.overlayModel.elapsedSeconds += 1
                }
            }
        }
    }

    // MARK: - W2.1: Level drain

    /// Drain the RMS level stream and write `overlayModel.level` with perceptual
    /// mapping and asymmetric smoothing (W2.3). Cancelled automatically on
    /// `transition(to: .processing)` and `stop()`.
    ///
    /// Cold-start retry: on the first dictation, `AudioCapture.start()` runs inside
    /// a background Task launched by `AppleSpeechTranscriber.startStream()`. There is
    /// a narrow race window where `startLevelStream()` is called before that Task has
    /// had a chance to set `pendingLevelStream`. We retry up to `levelStreamRetryCount`
    /// times with `levelStreamRetryIntervalNs` between attempts so the first dictation
    /// behaves identically to subsequent warm ones.
    /// [decision W2.3: 5 retries × 50 ms = 250 ms maximum wait; audio engine start
    ///  is observed to complete in < 100 ms on Apple Silicon. benchmark.md §7]
    private static let levelStreamRetryCount: Int    = 5
    // [decision W2.3: 50 ms retry interval — short enough to not delay waveform start,
    //  long enough for the audio Task to schedule. benchmark.md §7]
    private static let levelStreamRetryIntervalNs: UInt64 = 50_000_000  // 50 ms

    private func startLevelsDrain(provider: @escaping () async -> AsyncStream<Double>?) {
        levelsTask?.cancel()
        levelsTask = nil

        levelsTask = Task { [weak self] in
            guard let self else { return }

            // Cold-start retry loop: the first dictation may hit a race where
            // AudioCapture.pendingLevelStream is not yet set when we call currentLevels().
            var stream: AsyncStream<Double>?
            for attempt in 0 ..< Self.levelStreamRetryCount {
                stream = await provider()
                if stream != nil { break }
                guard !Task.isCancelled else { return }
                if attempt < Self.levelStreamRetryCount - 1 {
                    try? await Task.sleep(nanoseconds: Self.levelStreamRetryIntervalNs)
                }
            }

            guard let stream else {
                SpeakLog.engine.info("OverlayController: level stream unavailable after retries — bars use idle animation.")
                return
            }

            var smoothed = 0.0
            for await rawLevel in stream {
                if Task.isCancelled { break }
                // W2.3: Perceptual mapping (dB normalization) then asymmetric smoothing.
                // Maps speech RMS (typically 0.01–0.08) to a healthy bar range,
                // with fast attack and natural release (see LevelMath.swift §W2.3).
                let perceptual = levelPerceptual(rms: rawLevel)
                let next = levelSmoothedAsymmetric(previous: smoothed, target: perceptual)
                smoothed = next
                let levelToSet = next
                await MainActor.run { [weak self] in
                    self?.overlayModel.level = levelToSet
                }
            }
            // Stream ended (capture stopped) — reset level to 0.
            await MainActor.run { [weak self] in
                self?.overlayModel.level = 0.0
            }
            SpeakLog.engine.info("OverlayController: level stream finished.")
        }
    }

    // MARK: - W2.2: Escape monitor

    /// Install a *global* NSEvent monitor for Escape (keyCode 53).
    ///
    /// Global monitors fire regardless of which app is frontmost — required here
    /// because the panel is non-activating (LSUIElement app, never key). Cannot
    /// consume the event, which is acceptable: Escape reaching the target app
    /// is harmless and usually desirable.
    ///
    /// The callback (`onEscapeStop`) is invoked unconditionally here — re-entrancy
    /// guarding (only active-capture state triggers stop) lives in `DictationController`,
    /// keeping OverlayController free of icon-state coupling.
    ///
    /// [decision W2.2: global monitor; no consumption; AX/Input Monitoring already granted]
    private func installEscapeMonitor() {
        removeEscapeMonitor()   // idempotent — remove prior monitor if any
        escapeMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            // keyCode 53 is Escape on all Apple keyboard layouts. [decision: kVK_Escape = 53]
            guard event.keyCode == 53 else { return }
            Task { @MainActor [weak self] in
                guard let self else { return }
                SpeakLog.engine.info("OverlayController: Escape key detected — stopping dictation.")
                self.onEscapeStop?()
            }
        }
    }

    private func removeEscapeMonitor() {
        if let monitor = escapeMonitor {
            NSEvent.removeMonitor(monitor)
            escapeMonitor = nil
        }
    }
}
