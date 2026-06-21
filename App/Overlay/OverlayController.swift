// App/Overlay/OverlayController.swift
//
// Owns the overlay lifecycle: OverlayViewModel, TranscriptOverlayPanel,
// the partials-drain Task, and the start / transition(to:) / stop surface.
//
// Responsibilities:
//   - Holds the `OverlayViewModel` (the model that drives `TranscriptOverlayView`).
//   - Constructs and owns the single `TranscriptOverlayPanel` (created lazily at
//     `createPanel()`, called from `DictationController.startMonitoring()` so the
//     NSHostingView cost is paid once, not per-dictation, matching the original
//     panel-creation timing in `DictationController`).
//   - `start(partialsProvider:)` — resets the model, shows the panel, and begins
//     draining partial-transcript chunks from the provided async-stream closure.
//   - `transition(to:)` — updates the model state; cancels the partials task when
//     moving to `.processing` (no more chunks will arrive).
//   - `stop()` — cancels the partials task, resets the model, and hides the panel.
//
// Honesty boundary:
//   - Panel visibility (`orderFrontRegardless` / `orderOut`) is live-window-server
//     behaviour — not autonomously verifiable in unit tests. Tests construct and
//     call the controller but should not assert on physical visibility.
//   - Model state transitions ARE verifiable from unit tests (the model is @MainActor
//     and has no hidden state).
//
// Threading:
//   - `OverlayController` is `@MainActor`. All mutations of `overlayModel` and
//     `partialText` are on the main thread.
//   - The partials-drain Task runs on a background executor but posts to MainActor
//     via `MainActor.run { }` when writing to the model.
//   - `[weak self]` captures avoid retain cycles in the drain Task.
//
// CREATION TIMING:
//   `createPanel()` must be called exactly once from `startMonitoring()`, not from
//   `init`. `NSHostingView` is expensive; recreating it per-dictation is not the
//   right model. This matches the original behaviour in `DictationController`.

import AppKit
import SwiftUI
import SpeakCore

// MARK: - OverlayController

@MainActor
final class OverlayController {

    // MARK: - Internals (internal for @testable access in SpeakTests)

    /// The view-model bound to `TranscriptOverlayView`. Internal so tests can
    /// assert on `overlayState` and `partialText` without going through the panel.
    let overlayModel = OverlayViewModel()

    /// The running partial text — mirrors `overlayModel.partialText` so callers
    /// that only need the string (e.g. the enclosing `DictationController`) can
    /// observe it without referencing the model directly.
    private(set) var partialText: String = ""

    // MARK: - Private

    private var panel: TranscriptOverlayPanel?
    private var partialsTask: Task<Void, Never>?
    /// 1 Hz timer driving the HUD duration counter. Lives only while listening.
    private var durationTask: Task<Void, Never>?

    // MARK: - Init

    init() {}

    // MARK: - Panel setup (call once from startMonitoring)

    /// Create the overlay panel. Call exactly once from `DictationController.startMonitoring()`.
    /// Creating the panel here (not in init) matches the original timing: the NSHostingView
    /// is expensive and we defer that cost until monitoring actually starts.
    func createPanel() {
        guard panel == nil else { return }
        panel = TranscriptOverlayPanel(overlayModel: overlayModel)
    }

    // MARK: - Lifecycle

    /// Show the overlay in the `.listening` state and begin draining partial
    /// transcript chunks from `partialsProvider`.
    ///
    /// - Parameter partialsProvider: An async closure that returns the partials
    ///   `AsyncStream<TranscriptChunk>?` for the current dictation session. Called
    ///   after the panel is shown — same timing as the original `currentPartials()`
    ///   call site in `DictationController.startOverlay()`. Passing `nil` (or a
    ///   closure that returns `nil`) is safe — the drain task exits early.
    func start(partialsProvider: @escaping () async -> AsyncStream<TranscriptChunk>?) {
        // Reset to listening state with empty text before showing.
        overlayModel.partialText = ""
        overlayModel.overlayState = .listening
        overlayModel.elapsedSeconds = 0
        partialText = ""
        panel?.show()

        // Drive the HUD duration counter at 1 Hz while listening.
        startDurationTimer()

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
                }
            }
            SpeakLog.engine.info("OverlayController: partials stream finished.")
        }
    }

    /// Transition the overlay to a new visual state.
    ///
    /// Cancels the partials task when moving to `.processing` — no more chunks
    /// will arrive once the engine transitions to the cleanup phase.
    /// Does NOT hide the panel; call `stop()` for that.
    func transition(to state: OverlayState) {
        overlayModel.overlayState = state
        if state == .processing {
            // No more partial text will arrive once processing begins.
            partialsTask?.cancel()
            partialsTask = nil
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
        durationTask?.cancel()
        durationTask = nil
        overlayModel.partialText = ""
        overlayModel.overlayState = .listening   // reset for next dictation
        overlayModel.elapsedSeconds = 0
        partialText = ""
        panel?.hide()
        SpeakLog.engine.info("OverlayController: overlay hidden.")
    }

    // MARK: - Duration timer

    /// Increment `overlayModel.elapsedSeconds` once per second while listening.
    /// A cancellable Task (not a `Timer`) so it composes with the actor model and is
    /// torn down deterministically on transition/stop. [decision: 1 s tick — the HUD
    /// shows whole seconds; sub-second precision adds no user value.]
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
}
