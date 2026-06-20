// App/Debug/DebugLaunchDispatcher.swift
//
// DEBUG-ONLY: Handles `--debug-open <target>` launch arguments so an automated
// verification agent can drive the UI and the live engine path using only
// `open --args` + `screencapture`, without requiring Accessibility/AX grants.
//
// CONTRACT (from the v0 human-verification spec):
//   `open /path/to/Speak.app --args --debug-open <target>`
//
//   Targets:
//     onboarding-welcome          → onboarding window forced to .welcome
//     onboarding-microphone       → onboarding window forced to .microphone
//     onboarding-accessibility    → onboarding window forced to .accessibility
//     onboarding-inputmonitoring  → onboarding window forced to .inputMonitoring
//     onboarding-hotkey           → onboarding window forced to .hotkey
//     onboarding-done             → onboarding window forced to .done
//     settings                    → Settings window, frontmost
//     history                     → History window, frontmost
//     overlay-demo                → Overlay panel with sample partial text
//     simulate-dictation          → Real engine pipeline, fixture audio, pastes
//                                   into whatever app is frontmost after 2.5 s
//
// DESIGN:
//   - All code in this file is wrapped in `#if DEBUG`. Nothing reaches release.
//   - When a `--debug-open` target is detected, the dispatcher handles it and
//     returns `true`. The caller (`AppDelegate`) skips `startMonitoring()` for
//     targets that require focus to remain in another app (`simulate-dictation`).
//     All other targets call `startMonitoring()` normally so the menubar icon
//     and normal app lifecycle still work.
//   - The dispatcher does NOT call `startMonitoring()` for `simulate-dictation`
//     because `startMonitoring()` calls `showOnboardingIfNeeded()`, which on a
//     machine with incomplete onboarding would pop a window and activate the app,
//     stealing focus and causing the paste to land in the wrong app.
//
// THREADING:
//   All methods are `@MainActor` — they interact with NSApp and NSWindow.

#if DEBUG

import AppKit
import SwiftUI
import SpeakCore
import os

// MARK: - DebugTarget

/// The decoded target from `--debug-open <target>`.
enum DebugTarget: String {
    case onboardingWelcome       = "onboarding-welcome"
    case onboardingMicrophone    = "onboarding-microphone"
    case onboardingAccessibility = "onboarding-accessibility"
    case onboardingInputMonitoring = "onboarding-inputmonitoring"
    case onboardingHotkey        = "onboarding-hotkey"
    case onboardingDone          = "onboarding-done"
    case settings                = "settings"
    case history                 = "history"
    case overlayDemo             = "overlay-demo"
    case simulateDictation       = "simulate-dictation"
}

// MARK: - DebugLaunchDispatcher

/// Parses launch arguments and dispatches to the appropriate verification
/// surface. All methods must be called on `@MainActor`.
@MainActor
final class DebugLaunchDispatcher {

    private let log = SpeakLog.engine

    // MARK: - Parse

    /// Parse `CommandLine.arguments` for `--debug-open <target>`.
    /// Returns the decoded `DebugTarget`, or `nil` when none is present.
    static func parseTarget() -> DebugTarget? {
        let args = CommandLine.arguments
        guard let idx = args.firstIndex(of: "--debug-open"),
              args.indices.contains(idx + 1) else { return nil }
        let rawValue = args[idx + 1]
        guard let target = DebugTarget(rawValue: rawValue) else {
            // Unknown target — log and return nil so normal startup proceeds.
            SpeakLog.engine.error(
                "DebugLaunchDispatcher: unrecognized --debug-open target '\(rawValue, privacy: .public)'. Proceeding with normal startup."
            )
            return nil
        }
        return target
    }

    // MARK: - Dispatch

    /// Dispatch the debug target. Returns `true` if the target requires
    /// skipping `startMonitoring()` (`simulate-dictation`); `false` otherwise.
    ///
    /// - Parameters:
    ///   - target: The decoded target.
    ///   - controller: The live `DictationController` for the session.
    func dispatch(target: DebugTarget, controller: DictationController) -> Bool {
        log.info("DebugLaunchDispatcher: handling target=\(target.rawValue, privacy: .public)")
        switch target {
        case .onboardingWelcome:
            openOnboarding(step: .welcome, controller: controller)
            return false
        case .onboardingMicrophone:
            openOnboarding(step: .microphone, controller: controller)
            return false
        case .onboardingAccessibility:
            openOnboarding(step: .accessibility, controller: controller)
            return false
        case .onboardingInputMonitoring:
            openOnboarding(step: .inputMonitoring, controller: controller)
            return false
        case .onboardingHotkey:
            openOnboarding(step: .hotkey, controller: controller)
            return false
        case .onboardingDone:
            openOnboarding(step: .done, controller: controller)
            return false
        case .settings:
            openSettings(controller: controller)
            return false
        case .history:
            openHistory(controller: controller)
            return false
        case .overlayDemo:
            openOverlayDemo(controller: controller)
            return false
        case .simulateDictation:
            // Simulate-dictation must not call startMonitoring() — it needs focus
            // to remain in the target app (e.g. TextEdit) so paste lands correctly.
            // Return true to tell AppDelegate to skip startMonitoring().
            startSimulateDictation(controller: controller)
            return true
        }
    }

    // MARK: - Onboarding targets

    private func openOnboarding(step: OnboardingStep, controller: DictationController) {
        // Use the existing (or create a new) OnboardingWindowController,
        // but call showForcedStep(_:) to bypass permission-gated auto-advance.
        let vc = OnboardingWindowController(
            permissionManager: controller.permissionManager,
            settings: controller.settingsStore
        )
        vc.showForcedStep(step)
        // Retain the controller for the app lifetime via a stored property on the task.
        // We hold it in a local Task to keep it alive without global mutable state.
        keepAlive(vc)
        log.info("DebugLaunchDispatcher: onboarding window opened at step \(String(describing: step), privacy: .public)")
    }

    // MARK: - Settings target

    private func openSettings(controller: DictationController) {
        // SwiftUI's `SettingsLink` action can only be triggered inside a menu;
        // from `applicationDidFinishLaunching` it is not callable directly.
        // Fall back to a manually constructed NSWindow hosting SettingsView —
        // same view, same data, reliable from any launch context.
        // [decision: NSWindow + NSHostingView mirrors OnboardingWindowController
        //  and HistoryWindowController; avoids relying on NSApp.sendAction
        //  Selector("showSettingsWindow:") which is runtime-fragile on macOS 26]
        let view = SettingsView(store: controller.settingsStore)
        let hosting = NSHostingView(rootView: view)
        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 400),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        win.title = "speak — Settings"
        win.contentView = hosting
        win.isReleasedWhenClosed = false
        win.center()
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        keepAlive(win)
        log.info("DebugLaunchDispatcher: Settings window opened.")
    }

    // MARK: - History target

    private func openHistory(controller: DictationController) {
        let vc = HistoryWindowController(store: controller.historyStore)
        vc.show()
        keepAlive(vc)
        log.info("DebugLaunchDispatcher: History window opened.")
    }

    // MARK: - Overlay demo target

    private func openOverlayDemo(controller: DictationController) {
        // The overlay panel is owned by DictationController and created in
        // startMonitoring(). We replicate the panel construction here for the
        // debug path. The sample string exercises the overlay's text rendering.
        //
        // "the quick brown fox" — chosen to provide readable, renderable text
        // that demonstrates the overlay panel visually. [decision: hardcoded
        // sample; sufficient for screenshot verification of rendering]
        let samplePartial = "the quick brown fox"
        let overlayModel = OverlayViewModel()
        overlayModel.partialText = samplePartial
        let panel = TranscriptOverlayPanel(overlayModel: overlayModel)
        panel.show()
        keepAlive(panel)
        keepAlive(overlayModel)
        log.info("DebugLaunchDispatcher: overlay panel shown with sample text '\(samplePartial, privacy: .public)'")
    }

    // MARK: - Simulate dictation target

    /// Runs the REAL engine pipeline with fixture audio, waiting 2.5 s after
    /// launch before starting so the harness can bring a target app frontmost.
    ///
    /// Pipeline: real `AppleSpeechTranscriber` (fixture audio producer) +
    /// real cleaner via factory + real `PasteboardWriter` + real history.
    ///
    /// [decision: 2.5 s pre-dictation delay — matches the task spec contract.]
    /// [decision: 3.5 s post-begin delay before endDictation()]:
    ///   hello_speech.caf is 1.334 s (21338 frames at 16kHz).
    ///   FixtureAudioProducer streams in ~21338/4096 ≈ 6 chunks × 1ms = 6ms delay.
    ///   SpeechAnalyzer needs time to process chunks and emit results.
    ///   3.5 s = 1.334 s fixture + 2.166 s STT processing margin.
    ///   endDictation() calls CaptureSession.stop() which calls transcriber.stop()
    ///   (SessionState.stopSession()) — this ends the buffer stream and awaits
    ///   the full pipeline drain (bridge → finalize → results). The 3.5 s wait
    ///   ensures the fixture has finished streaming so stop() flushes naturally
    ///   rather than truncating mid-stream. [verified in CaptureSession.swift §157-203]
    private func startSimulateDictation(controller: DictationController) {
        Task { [weak self] in
            guard let self else { return }

            self.log.info("DebugLaunchDispatcher: simulate-dictation starting — waiting 2.5 s for harness to prepare target app.")

            // 2.5 s wait so the automation harness can bring a target app (e.g.
            // TextEdit) to the front before dictation begins. [decision per spec]
            let preDelayNanoseconds: UInt64 = 2_500_000_000
            try? await Task.sleep(nanoseconds: preDelayNanoseconds)

            // Resolve the fixture.
            guard let fixtureURL = FixtureAudioProducer.helloSpeechFixture() else {
                self.log.error("DebugLaunchDispatcher: hello_speech.caf not found — simulate-dictation aborted.")
                return
            }
            self.log.info("DebugLaunchDispatcher: fixture resolved at \(fixtureURL.path, privacy: .public)")

            // Build a fixture-backed transcriber. All other components are
            // identical to the production engine wired in DictationController.init().
            // [design: reuse the same factory functions (defaultTranscriber /
            //  defaultCleaner) but override the audio producer — the minimum
            //  delta from production. The engine is assembled fresh here to avoid
            //  mutating the production engine's currentSession while it is idle.]
            let store = controller.settingsStore
            let fixtureProducer = FixtureAudioProducer(fileURL: fixtureURL)

            // Replace only the audio producer; keep real STT implementation.
            let fixtureTranscriber: any Transcribing
            if #available(macOS 26.0, *) {
                fixtureTranscriber = AppleSpeechTranscriber(audioProducer: fixtureProducer)
            } else {
                self.log.error("DebugLaunchDispatcher: macOS 26 required for AppleSpeechTranscriber — simulate-dictation aborted.")
                return
            }

            let engine = SpeakEngine(
                transcriber: fixtureTranscriber,
                cleaner: defaultCleaner(for: store),
                inserter: PasteboardWriter(),
                history: controller.historyStore,
                settings: store
            )

            self.log.info("DebugLaunchDispatcher: simulate-dictation engine assembled — beginning dictation.")

            do {
                try await engine.beginDictation()
                self.log.info("DebugLaunchDispatcher: simulate-dictation listening — fixture audio streaming.")

                // Wait for the fixture to stream to completion before ending.
                // 3.5 s covers the 1.334 s fixture duration plus 2.166 s margin
                // for SpeechAnalyzer to process and emit results. See [decision] above.
                let postBeginWaitNanoseconds: UInt64 = 3_500_000_000
                try? await Task.sleep(nanoseconds: postBeginWaitNanoseconds)
                self.log.info("DebugLaunchDispatcher: simulate-dictation ending dictation.")

                let result = try await engine.endDictation()
                self.log.info("""
                    DebugLaunchDispatcher: simulate-dictation complete. \
                    raw='\(result.rawText.prefix(120), privacy: .private)' \
                    cleaned='\(result.cleanedText?.prefix(120) ?? "(none)", privacy: .private)' \
                    engineId='\(result.engineId, privacy: .public)'
                    """)
            } catch {
                self.log.error(
                    "DebugLaunchDispatcher: simulate-dictation error — \(error.localizedDescription, privacy: .public)"
                )
            }
        }
    }

    // MARK: - Lifetime management

    /// Keeps a reference alive for the app lifetime without global mutable state.
    /// Uses an actor-isolated store so this is data-race-free.
    private func keepAlive(_ object: AnyObject) {
        Task {
            await DebugObjectStore.shared.retain(object)
        }
    }
}

// MARK: - DebugObjectStore

/// Actor that retains DEBUG-lifecycle objects (window controllers, panels) for
/// the process lifetime without using global mutable state.
/// [decision: actor-isolated array — data-race-safe; avoids any global `var`]
private actor DebugObjectStore {
    static let shared = DebugObjectStore()
    private var objects: [AnyObject] = []

    func retain(_ object: AnyObject) {
        objects.append(object)
    }
}

#endif
