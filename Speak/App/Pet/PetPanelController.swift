// App/Pet/PetPanelController.swift
//
// FE-1 (specs/frontend-identity.md §5): Pip's panel lifecycle. Mirrors the
// established overlay-panel precedents:
//   - `TranscriptOverlayPanel`: non-activating, always-on-top NSPanel,
//     `.canJoinAllSpaces` + `.fullScreenAuxiliary`, `FirstMouseHostingView`
//     so the first click lands without stealing focus.
//   - `CaretOverlayController`: owns model + panel + show/hide lifecycle.
//
// DRAG + EDGE-SNAP: dragging is implemented via `NSPanel.performDrag`-free
// manual tracking (`mouseDown`/`mouseDragged`/`mouseUp` on the hosting view),
// because `PetView` also needs left-click (toggle dictation) and right-click
// (menu) to work — a plain `.movable` panel would consume the mouse-down for
// window dragging before SwiftUI's gesture recognizers see it. On release,
// `PetGeometry.snappedOrigin` computes the final position (pure, tested).
//
// STATE WIRING: `PetPanelController` owns a `Task` that polls the three
// signal sources (engine/permission availability, `DictationController.icon`,
// `AgentSpeechQueue.queuedCount`, `PetAttentionProviding.count`) and resolves
// them through `PetState.resolve(from:)` — the single source of truth for
// "what is Pip doing right now."
//
// HARD RULES (never violate):
//   - Pip's own code never opens the mic — clicks route through
//     `DictationController.beginDictation()`/`endDictation()`, the SAME path
//     the hotkey uses. No parallel capture path.
//   - Never steals/holds keyboard focus (`canBecomeKey`/`canBecomeMain` both
//     false, matching `TranscriptOverlayPanel`).

import AppKit
import CoreGraphics
import Foundation
import SpeakCore
import SwiftUI

// MARK: - PetPanelModel

@Observable
@MainActor
final class PetPanelModel {
    var state: PetState = .dormant
    var level: Double = 0
    var attentionCount: Int = 0
    var statusText: String = ""
    var isHovering: Bool = false
}

// MARK: - PetHostingView (drag + click routing)

/// Hosts `PetView` and implements manual drag-to-move + edge-snap-on-release,
/// plus left-click (toggle dictation) / right-click (menu) / hover routing.
/// `acceptsFirstMouse` mirrors `FirstMouseHostingView` (`TranscriptOverlayPanel.swift`)
/// — required because the panel is `.nonactivatingPanel` / never key.
fileprivate final class PetHostingView: NSHostingView<PetView> {
    var onClick: (() -> Void)?
    var onRightClick: (() -> Void)?
    var onDragEnded: ((CGPoint) -> Void)?
    var onHoverChanged: ((Bool) -> Void)?

    private var dragOrigin: CGPoint?
    private var mouseDownWindowOrigin: CGPoint?
    private var didDrag = false
    private var trackingArea: NSTrackingArea?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) { onHoverChanged?(true) }
    override func mouseExited(with event: NSEvent) { onHoverChanged?(false) }

    override func mouseDown(with event: NSEvent) {
        didDrag = false
        dragOrigin = NSEvent.mouseLocation
        mouseDownWindowOrigin = window?.frame.origin
    }

    override func mouseDragged(with event: NSEvent) {
        guard let dragOrigin, let mouseDownWindowOrigin, let window else { return }
        let current = NSEvent.mouseLocation
        let delta = CGPoint(x: current.x - dragOrigin.x, y: current.y - dragOrigin.y)
        // A small dead-zone before treating this as a drag (vs. a click).
        if !didDrag, abs(delta.x) < 3, abs(delta.y) < 3 { return }
        didDrag = true
        window.setFrameOrigin(CGPoint(
            x: mouseDownWindowOrigin.x + delta.x,
            y: mouseDownWindowOrigin.y + delta.y
        ))
    }

    override func mouseUp(with event: NSEvent) {
        defer {
            dragOrigin = nil
            mouseDownWindowOrigin = nil
        }
        if didDrag, let origin = window?.frame.origin {
            onDragEnded?(origin)
        } else {
            onClick?()
        }
        didDrag = false
    }

    override func rightMouseDown(with event: NSEvent) {
        onRightClick?()
    }
}

// MARK: - PetPanel

/// A non-activating, always-on-top NSPanel hosting Pip. Follows
/// `TranscriptOverlayPanel`'s focus-steal-prevention layers exactly.
final class PetPanel: NSPanel {
    static let size = CGSize(width: 56, height: 36)

    private var hostingView: PetHostingView?

    init(model: PetPanelModel) {
        let mask: NSWindow.StyleMask = [.nonactivatingPanel, .borderless]
        super.init(
            contentRect: CGRect(origin: .zero, size: Self.size),
            styleMask: mask,
            backing: .buffered,
            defer: true
        )
        isFloatingPanel = true
        hidesOnDeactivate = false
        level = .floating
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]

        let view = PetHostingView(rootView: PetView(
            state: model.state,
            level: model.level,
            attentionCount: model.attentionCount,
            statusText: model.statusText,
            isHovering: model.isHovering
        ))
        view.frame = CGRect(origin: .zero, size: Self.size)
        contentView = view
        hostingView = view
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func updateRootView(_ view: PetView) {
        hostingView?.rootView = view
    }

    fileprivate var interactionHandlers: PetHostingView? { hostingView }

    func show() { orderFrontRegardless() }
    func hide() { orderOut(nil) }
}

// MARK: - PetPanelController

/// Owns Pip's panel, model, state-resolution loop, and interaction wiring.
/// Constructed by `DictationController` when `settingsStore.petEnabled`
/// becomes true; torn down when it becomes false. See `DictationController`'s
/// `startObservingPetEnabled()` for the live-apply wiring.
@MainActor
final class PetPanelController {
    private let model = PetPanelModel()
    private let panel: PetPanel
    private let settingsStore: SettingsStore
    private let permissionManager: PermissionManager
    private let agentSpeechQueue: AgentSpeechQueue
    private let attentionProvider: any PetAttentionProviding
    /// Weak-ish by construction: closures capture `[weak controller]` where
    /// `controller` is the owning `DictationController`, avoiding a retain
    /// cycle (`DictationController` owns this `PetPanelController`).
    private weak var dictationController: DictationController?

    private var resolveTask: Task<Void, Never>?
    private var levelTask: Task<Void, Never>?
    private var lastAppliedState: PetState = .dormant
    /// Retains the right-click menu's Obj-C target for the controller's lifetime.
    private var contextMenuTarget: AnyObject?

    init(
        dictationController: DictationController,
        settingsStore: SettingsStore,
        permissionManager: PermissionManager,
        agentSpeechQueue: AgentSpeechQueue,
        attentionProvider: any PetAttentionProviding = StubPetAttentionProvider()
    ) {
        self.dictationController = dictationController
        self.settingsStore = settingsStore
        self.permissionManager = permissionManager
        self.agentSpeechQueue = agentSpeechQueue
        self.attentionProvider = attentionProvider
        self.panel = PetPanel(model: model)

        wireInteraction()
        restorePosition()
        panel.show()
        startResolveLoop()
    }

    func tearDown() {
        resolveTask?.cancel()
        resolveTask = nil
        levelTask?.cancel()
        levelTask = nil
        panel.hide()
    }

    // MARK: - Interaction wiring

    private func wireInteraction() {
        let hosting = panel.interactionHandlers
        hosting?.onClick = { [weak self] in
            self?.handleClick()
        }
        hosting?.onRightClick = { [weak self] in
            self?.showContextMenu()
        }
        hosting?.onDragEnded = { [weak self] origin in
            self?.snapAndPersist(releasedAt: origin)
        }
        hosting?.onHoverChanged = { [weak self] hovering in
            self?.model.isHovering = hovering
            self?.refreshRootView()
        }
    }

    /// Left click: toggle dictation via `DictationController`'s existing
    /// hotkey path — NEVER a parallel capture path (hard rule, spec §5).
    private func handleClick() {
        guard let dictationController else { return }
        Task {
            if dictationController.icon == .listening {
                await dictationController.endDictation()
            } else {
                await dictationController.beginDictation()
            }
        }
    }

    /// Right-click menu (spec §5): Start/Stop Dictation · Open speak ·
    /// Hide Pip (session) · Disable Pip (setting).
    private func showContextMenu() {
        guard let dictationController else { return }
        let menu = NSMenu()

        let toggleItem = NSMenuItem(
            title: dictationController.icon == .listening ? "Stop Dictation" : "Start Dictation",
            action: #selector(MenuActionTarget.toggleDictation),
            keyEquivalent: ""
        )
        let target = MenuActionTarget(controller: self)
        toggleItem.target = target
        menu.addItem(toggleItem)

        let openItem = NSMenuItem(
            title: "Open speak",
            action: #selector(MenuActionTarget.openSpeak),
            keyEquivalent: ""
        )
        openItem.target = target
        menu.addItem(openItem)

        menu.addItem(.separator())

        let hideItem = NSMenuItem(
            title: "Hide Pip",
            action: #selector(MenuActionTarget.hideSession),
            keyEquivalent: ""
        )
        hideItem.target = target
        menu.addItem(hideItem)

        let disableItem = NSMenuItem(
            title: "Disable Pip",
            action: #selector(MenuActionTarget.disablePet),
            keyEquivalent: ""
        )
        disableItem.target = target
        menu.addItem(disableItem)

        // Retained on `self` (not the menu) for the controller's lifetime —
        // simpler and safer than an associated-object trick, since
        // `PetPanelController` already outlives any single menu pop-up.
        contextMenuTarget = target
        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }

    /// A tiny `NSObject` target for the NSMenu's target/action pairs — NSMenuItem
    /// has no closure-based initializer, so a minimal Obj-C target is the
    /// standard bridge (same pattern as `StatusBarController.buildMenu()`).
    @MainActor
    private final class MenuActionTarget: NSObject {
        weak var controller: PetPanelController?
        init(controller: PetPanelController) { self.controller = controller }

        @objc func toggleDictation() { controller?.handleClick() }
        @objc func openSpeak() { controller?.dictationController?.showDashboard() }
        @objc func hideSession() { controller?.panel.hide() }
        @objc func disablePet() { controller?.settingsStore.petEnabled = false }
    }

    // MARK: - Position persistence (per display UUID)

    /// The screen Pip is actually on (review fix, 2026-07-11).
    ///
    /// `NSScreen.main` ALWAYS resolves to the primary display for a non-key
    /// `.nonactivatingPanel` (this panel can never be key), so using it for
    /// snap math / persistence keys would pin both to the primary display no
    /// matter where the user drags Pip. Resolution order:
    ///   1. `panel.screen` — AppKit's own answer for a positioned window;
    ///   2. the screen whose frame maximally intersects `panelFrame`
    ///      (pure, tested — `PetGeometry.indexOfScreenMaximallyIntersecting`);
    ///   3. `NSScreen.main` as the last resort (panel entirely off-screen).
    ///
    /// [unverified — live multi-display drag/snap requires human dogfood;
    ///  same caveat as `TranscriptOverlayPanel`'s multi-display placement.]
    private func resolvedScreen(for panelFrame: CGRect) -> NSScreen? {
        if let own = panel.screen { return own }
        let screens = NSScreen.screens
        if let idx = PetGeometry.indexOfScreenMaximallyIntersecting(
            panelFrame: panelFrame,
            screenFrames: screens.map(\.frame)
        ) {
            return screens[idx]
        }
        return NSScreen.main
    }

    private func restorePosition() {
        // Before the first positioning, `panel.screen` is nil and the frame is
        // meaningless — the primary screen (NSScreen.main via resolvedScreen's
        // fallback) is the correct restore target for a fresh panel.
        guard let screen = resolvedScreen(for: panel.frame) else { return }
        let key = Self.displayUUID(for: screen)
        if let saved = settingsStore.petPositions[key] {
            panel.setFrameOrigin(saved)
        } else {
            // Default: bottom-right corner, inset. [decision FE-1]
            let visible = screen.visibleFrame
            let origin = CGPoint(
                x: visible.maxX - PetPanel.size.width - PetGeometry.edgeInset,
                y: visible.minY + PetGeometry.edgeInset
            )
            panel.setFrameOrigin(origin)
        }
    }

    private func snapAndPersist(releasedAt origin: CGPoint) {
        let releasedFrame = CGRect(origin: origin, size: PetPanel.size)
        guard let screen = resolvedScreen(for: releasedFrame) else { return }
        let snapped = PetGeometry.snappedOrigin(
            releasedAt: origin,
            panelSize: PetPanel.size,
            screenFrame: screen.visibleFrame
        )
        panel.setFrameOrigin(snapped)
        var positions = settingsStore.petPositions
        positions[Self.displayUUID(for: screen)] = snapped
        settingsStore.petPositions = positions
    }

    /// A stable per-display identifier, used as the `petPositions` dictionary
    /// key. Falls back to the screen's `localizedName` if the UUID lookup
    /// fails (defensive — should not happen on any real display).
    static func displayUUID(for screen: NSScreen) -> String {
        guard let screenNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            return screen.localizedName
        }
        let displayID = CGDirectDisplayID(screenNumber.uint32Value)
        guard let cfUUID = CGDisplayCreateUUIDFromDisplayID(displayID)?.takeRetainedValue() else {
            return screen.localizedName
        }
        return CFUUIDCreateString(nil, cfUUID) as String? ?? screen.localizedName
    }

    // MARK: - State resolution loop

    /// Polls the signal sources at a light cadence and resolves them through
    /// `PetState.resolve(from:)`. A polling loop (not pure Observation) because
    /// the level signal and `AgentSpeechQueue`/`PetAttentionProviding` counts
    /// are async/actor-isolated — matching `OverlayController`'s levels-drain
    /// pattern in spirit (a bounded loop, not per-value notification).
    private func startResolveLoop() {
        resolveTask?.cancel()
        resolveTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.tick()
                try? await Task.sleep(nanoseconds: 200_000_000)  // 5Hz — state doesn't need 60fps
            }
        }
    }

    private func tick() async {
        guard let dictationController else { return }
        let micGranted = permissionManager.status(.microphone) == .granted
        let axGranted = permissionManager.status(.accessibility) == .granted
        let queuedCount = await agentSpeechQueue.queuedCount
        let attentionCount = await attentionProvider.count

        let inputs = PetStateInputs(
            engineAvailable: micGranted && axGranted,
            isListening: dictationController.icon == .listening,
            isProcessing: dictationController.icon == .processing,
            isSpeaking: queuedCount > 0,
            isAgentWorking: false,  // reserved — no producer until AVB-7's agentWorking signal exists
            hasAttention: attentionCount > 0
        )
        let resolved = PetState.resolve(from: inputs)

        model.attentionCount = attentionCount
        model.statusText = Self.statusText(for: resolved, attentionCount: attentionCount)
        // CONVERGENCE RULE (review fix, 2026-07-11): `resolve()` is the single
        // source of truth and `model.state` ALWAYS converges to its output,
        // unconditionally, every tick. The transition graph is ADVISORY ONLY —
        // an unexpected edge is logged (it means a signal source skipped a
        // beat, worth knowing) but must NEVER block state application:
        // rejecting truth can only ever display a stale state, e.g. a frozen
        // "Listening" + onAir tally after the mic closed — a direct violation
        // of the spec §2 hard rule (onAir iff capturing).
        if resolved != lastAppliedState {
            if !lastAppliedState.canTransition(to: resolved) {
                SpeakLog.app.error(
                    "PetPanelController: unexpected state edge \(self.lastAppliedState.rawValue, privacy: .public) → \(resolved.rawValue, privacy: .public) — applying anyway (advisory graph)"
                )
            }
            lastAppliedState = resolved
            updateLevelDrain(for: resolved)
        }
        model.state = resolved
        refreshRootView()
    }

    /// Pip's bars read the SAME level signal as the Aurora HUD (spec §5:
    /// "the same signal as HUD"). Drains `SpeakEngine.currentLevels()` only
    /// while `.listening`; resets to 0 otherwise. Uses the SpeakCore-level
    /// perceptual mapping + asymmetric smoothing helpers `OverlayController`
    /// already established (`LevelMath.swift`), so Pip's bars and the HUD's
    /// waveform read identically for the same audio.
    private func updateLevelDrain(for state: PetState) {
        levelTask?.cancel()
        levelTask = nil
        model.level = 0
        guard state == .listening, let dictationController else { return }
        let engineRef = dictationController.engine
        levelTask = Task { [weak self] in
            guard let stream = await engineRef.currentLevels() else { return }
            var smoothed = 0.0
            for await raw in stream {
                if Task.isCancelled { break }
                let perceptual = levelPerceptual(rms: raw)
                smoothed = levelSmoothedAsymmetric(previous: smoothed, target: perceptual)
                await MainActor.run { [weak self] in
                    self?.model.level = smoothed
                }
            }
            await MainActor.run { [weak self] in
                self?.model.level = 0
            }
        }
    }

    /// Copy voice per spec §7: plain verbs, sentence case.
    private static func statusText(for state: PetState, attentionCount: Int) -> String {
        switch state {
        case .dormant: return "Pet is asleep"
        case .idle: return "Ready"
        case .listening: return "Pet is listening"
        case .processing: return "Pet is processing transcript"
        case .agentWorking: return "Agent working"
        case .attention: return "Pet needs attention (\(attentionCount) queued)"
        case .speaking: return "Pet is speaking"
        }
    }

    private func refreshRootView() {
        panel.updateRootView(PetView(
            state: model.state,
            level: model.level,
            attentionCount: model.attentionCount,
            statusText: model.statusText,
            isHovering: model.isHovering
        ))
    }
}
