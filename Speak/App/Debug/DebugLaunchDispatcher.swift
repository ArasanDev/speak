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
import os
import SpeakCore
import SwiftUI

// MARK: - DebugTarget

/// The decoded target from `--debug-open <target>`.
enum DebugTarget: String {
    case onboardingWelcome       = "onboarding-welcome"
    case onboardingMicrophone    = "onboarding-microphone"
    case onboardingAccessibility = "onboarding-accessibility"
    case onboardingHotkey        = "onboarding-hotkey"
    case onboardingDone          = "onboarding-done"
    case settings                = "settings"
    case history                 = "history"
    case dashboard               = "dashboard"   // full-window app, seeded feed (Phase 2)
    // Overlay demo targets (Phase C — one per visual state for screenshot verification):
    //   overlay-demo            → .listening state, sample partial text, mid-level meter
    //   overlay-demo-processing → .processing state, "Cleaning up…" + spinner
    //   overlay-demo-done       → .done state, checkmark
    //   overlay-demo-error      → W2.2 .error state, red pill + reason
    case overlayDemo             = "overlay-demo"
    case overlayDemoProcessing   = "overlay-demo-processing"
    case overlayDemoDone         = "overlay-demo-done"
    case overlayDemoError        = "overlay-demo-error"
    case simulateDictation       = "simulate-dictation"
    // Menubar icon color verification (roadmap P8):
    //   Each target holds the menubar icon in the given state indefinitely so a
    //   `screencapture` can confirm the color survives the menu-bar compositor.
    //   Use `listening` or `error` (red), NOT `idle` (gray — indistinguishable from template).
    case menubarIconListening    = "menubar-icon-listening"
    case menubarIconError        = "menubar-icon-error"
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
        // `dashboard:<section>` opens the dashboard straight to a pane (verification).
        if rawValue.hasPrefix("dashboard") { return .dashboard }
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

        case .dashboard:
            openDashboard(controller: controller)
            return false

        case .overlayDemo:
            openOverlayDemo(state: .listening, controller: controller)
            return false

        case .overlayDemoProcessing:
            openOverlayDemo(state: .processing, controller: controller)
            return false

        case .overlayDemoDone:
            openOverlayDemo(state: .done, controller: controller)
            return false

        case .overlayDemoError:
            openOverlayDemo(state: .error, controller: controller)
            return false

        case .simulateDictation:
            // Simulate-dictation must not call startMonitoring() — it needs focus
            // to remain in the target app (e.g. TextEdit) so paste lands correctly.
            // Return true to tell AppDelegate to skip startMonitoring().
            startSimulateDictation(controller: controller)
            return true

        case .menubarIconListening:
            // Force the menubar icon to .listening (red) and hold it indefinitely.
            // Allows screencapture to verify the color survives the system compositor.
            controller.forceIcon(.listening)
            return false

        case .menubarIconError:
            // Force the menubar icon to .error (red + xmark) and hold it indefinitely.
            controller.forceIcon(.error)
            return false
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
        let view = SettingsView(controller: controller)
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

    // MARK: - Dashboard target (Phase 2 — full-window app)

    /// Open the full-window dashboard with a SEEDED in-memory history store so the
    /// day-grouped Home feed + stats rail render with realistic content for a
    /// screenshot. Uses a throwaway store — never touches the production SQLite DB.
    /// [decision: seeded in-memory store keeps the visual-verification path side-effect-free]
    private func openDashboard(controller: DictationController) {
        // Isolated, seeded stores so EVERY pane renders with content (incl. the populated
        // List paths in Snippets/Dictionary/History — the diffRows crash risk) WITHOUT
        // touching production UserDefaults. [decision: a fixed debug suite, cleared first.]
        let suite = "speak.debug.dashboard"
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        defaults.removePersistentDomain(forName: suite)
        let settings = SettingsStore(defaults: defaults)
        settings.customVocabulary = ["Tamilarasan", "Kubernetes", "SpeakCore", "camelCase"]
        let snippets = SnippetStore(defaults: defaults)
        snippets.add(trigger: "omw", expansion: "on my way")
        snippets.add(trigger: "sig", expansion: "Best,\nTamil")

        let section = Self.parseDashboardSection()
        let context = DashboardContext(
            settingsStore: settings,
            historyStore: DebugSeededHistoryStore(),
            hotkeyCombo: ["Fn", "Fn"],
            snippetStore: snippets
        )
        let vc = DashboardWindowController(context: context, initialSection: section)
        vc.show()
        keepAlive(vc)
        log.info("DebugLaunchDispatcher: Dashboard opened at section=\(section.rawValue, privacy: .public) (seeded).")
    }

    /// Parse the section from `--debug-open dashboard:<section>` (defaults to Home).
    private static func parseDashboardSection() -> DashboardSection {
        let args = CommandLine.arguments
        guard let idx = args.firstIndex(of: "--debug-open"), args.indices.contains(idx + 1) else {
            return .home
        }
        let raw = args[idx + 1]
        guard let colon = raw.firstIndex(of: ":") else { return .home }
        let name = String(raw[raw.index(after: colon)...])
        return DashboardSection(rawValue: name) ?? .home
    }

    // MARK: - Overlay demo target (Phase C)
    //
    // Three debug targets cover the three visual states for screenshot verification:
    //
    //   overlay-demo            → .listening state, sample partial text, level=0.6 (mid)
    //   overlay-demo-processing → .processing state
    //   overlay-demo-done       → .done state
    //   overlay-demo-error      → W2.2 .error state, red pill + sample reason
    //
    // Setting a static level (0.6) for the listening screenshot is honest — the demo
    // is a rendering test, not a real mic feed. The level drives the bar-height math
    // but the animation is the same idle-breathing used when no real feed is available.
    //
    // Invocations (replace <path> with the built Speak.app path):
    //   open <path> --args --debug-open overlay-demo
    //   open <path> --args --debug-open overlay-demo-processing
    //   open <path> --args --debug-open overlay-demo-done

    private func openOverlayDemo(state: OverlayState, controller: DictationController) {
        let overlayModel = OverlayViewModel()
        overlayModel.overlayState = state

        switch state {
        case .listening:
            // [decision: "the quick brown fox" — readable sample that exercises
            //  the partial-text rendering path. Static level 0.6 shows mid-range bars.]
            overlayModel.partialText = "the quick brown fox"
            overlayModel.level = 0.6   // [decision: 0.6 = mid-level, visually interesting]

        case .processing:
            // Processing shows spinner + label, no text needed.
            overlayModel.partialText = ""

        case .done:
            // Done shows checkmark only.
            overlayModel.partialText = ""

        case .error:
            // W2.2: error demo — show a sample reason in the red pill.
            overlayModel.errorReason = "Speech engine unavailable"
            overlayModel.partialText = ""
        }

        let panel = TranscriptOverlayPanel(
            overlayModel: overlayModel
        )
        panel.show()
        keepAlive(panel)
        keepAlive(overlayModel)
        log.info(
            "DebugLaunchDispatcher: overlay demo shown in state .\(String(describing: state), privacy: .public)"
        )
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

// MARK: - DebugSeededHistoryStore

/// A read-only in-memory `HistoryStoring` seeded with sample dictations spanning
/// today + yesterday, so the dashboard's day-grouped feed and stats rail render
/// realistically for screenshot verification. Writes are no-ops; never persisted.
private final class DebugSeededHistoryStore: HistoryStoring, @unchecked Sendable {

    private let entries: [HistoryEntry]

    init() {
        let now = Date()
        let hour: TimeInterval = 3600
        let day: TimeInterval = 86_400
        func entry(_ raw: String, _ cleaned: String, ago: TimeInterval) -> HistoryEntry {
            // Derive a plausible duration from the cleaned word count at ~130 wpm so the
            // seeded dashboard shows a realistic words/min figure.
            let words = cleaned.split(whereSeparator: \.isWhitespace).count
            let duration = Double(words) / 130.0 * 60.0
            return HistoryEntry(rawText: raw, cleanedText: cleaned,
                                createdAt: now.addingTimeInterval(-ago),
                                engineId: "apple-speech-en-US+foundation-models",
                                duration: duration)
        }
        entries = [
            entry("um can you hear me",
                  "Can you hear me?", ago: hour),
            entry("lets ship the dashboard today and then verify the final output",
                  "Let's ship the dashboard today, and then verify the final output.", ago: 2 * hour),
            entry("the env file has real api keys we need to test and validate everything",
                  "The .env file has real API keys — we need to test and validate everything.", ago: 5 * hour),
            entry("understand the project explore deeply ideate the current state",
                  "Understand the project, explore deeply, ideate the current state.", ago: day + hour),
            entry("explore the project and understand the sdk we are building on",
                  "Explore the project and understand the SDK we are building on.", ago: day + 3 * hour)
        ]
    }

    func save(_ entry: HistoryEntry) throws {}
    func recent(limit: Int) throws -> [HistoryEntry] { Array(entries.prefix(limit)) }
    func search(_ substring: String) throws -> [HistoryEntry] {
        entries.filter { ($0.cleanedText ?? $0.rawText).localizedCaseInsensitiveContains(substring) }
    }
    func clear() throws {}
    func export() throws -> String { "[]" }
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
