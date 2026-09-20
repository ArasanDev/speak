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
//     simulate-dictation-scripted:<text>
//                                 → Real engine pipeline (cleanup/paste/history/
//                                   overlay), but STT is replaced by a
//                                   ScriptedTranscriber that reveals <text>
//                                   word-by-word — no mic, no fixture audio, no
//                                   SpeechAnalyzer. Lets a human or an automation
//                                   harness exercise arbitrary UI behaviors
//                                   repeatedly without giving any real input.
//                                   Defaults to a sample sentence if <text> is
//                                   omitted.
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
import SpeakLLM
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
    case simulateDictationScripted = "simulate-dictation-scripted"
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
        // `simulate-dictation-scripted:<text>` carries its script text after the colon.
        if rawValue.hasPrefix("simulate-dictation-scripted") { return .simulateDictationScripted }
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

        case .simulateDictationScripted:
            // Same focus-preservation reasoning as .simulateDictation.
            let text = Self.scriptedDictationText(in: CommandLine.arguments)
                ?? "the quick brown fox jumps over the lazy dog"
            startSimulateDictationScripted(text: text, controller: controller)
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
        // Route to the canonical Settings surface — the dashboard's Mode B —
        // instead of hosting the legacy tabbed SettingsView in a one-off window.
        // [decision: one Settings surface everywhere; debug launches must show
        //  the real UI, not a second implementation.]
        controller.showSettings()
        log.info("DebugLaunchDispatcher: Settings (dashboard Mode B) opened.")
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
        // `--debug-theme <id>` seeds the active color theme so themed
        // screenshots are verifiable headlessly (the suite is wiped above, so
        // this must run AFTER removePersistentDomain).
        if let themeIdx = CommandLine.arguments.firstIndex(of: "--debug-theme"),
           CommandLine.arguments.indices.contains(themeIdx + 1) {
            settings.themeID = CommandLine.arguments[themeIdx + 1]
        }

        let (section, settingsCategory) = Self.parseDashboardSection()
        let context = DashboardContext(
            settingsStore: settings,
            historyStore: DebugSeededHistoryStore(),
            hotkeyCombo: ["Fn", "Fn"],
            snippetStore: snippets,
            // A real synthesizer so Settings ▸ Text to Speech previews and the
            // Pipeline "Read it aloud" affordance actually speak in debug runs.
            voiceOut: AppleSpeechSynthesizer(),
            // Bound to the SAME seeded defaults suite so debug theme edits
            // never touch the user's real settings.
            themeEngine: ThemeEngine(settingsStore: settings),
            // The controller's shared server — the debug dashboard's Inference
            // pane / Playground must drive the same listener as a real session.
            inferenceServer: controller.inferenceServer
        )
        let vc = DashboardWindowController(
            context: context,
            initialSection: section,
            initialSettingsCategory: settingsCategory
        )
        vc.show()
        keepAlive(vc)
        let destination = "section=\(section.rawValue) settingsCategory=\(settingsCategory.rawValue)"
        log.info("DebugLaunchDispatcher: Dashboard opened at \(destination, privacy: .public) (seeded).")
    }

    /// Parse `--debug-open dashboard:<section>[:<settingsCategory>]`
    /// (defaults to Home / Voice Pipeline). The third component deep-links a
    /// Settings category so every Mode B screen can be screenshot-verified
    /// directly: `dashboard:settings:hotkeys`, `dashboard:settings:textToSpeech`, …
    private static func parseDashboardSection() -> (DashboardSection, SettingsCategory) {
        let args = CommandLine.arguments
        guard let idx = args.firstIndex(of: "--debug-open"), args.indices.contains(idx + 1) else {
            return (.home, .pipeline)
        }
        let parts = args[idx + 1].split(separator: ":").map(String.init)
        guard parts.count > 1 else { return (.home, .pipeline) }
        let section = DashboardSection(rawValue: parts[1]) ?? .home
        let category = parts.count > 2
            ? (SettingsCategory(rawValue: parts[2]) ?? .pipeline)
            : .pipeline
        return (section, category)
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
            // `windowText` is what the pill's text lane renders;
            // `elapsedSeconds` fills the header row so the demo shows the real
            // HUD composition, not a bare placeholder.
            overlayModel.windowText = "the quick brown fox jumps over the lazy dog"
            overlayModel.elapsedSeconds = 12
            overlayModel.level = 0.6   // [decision: 0.6 = mid-level, visually interesting]

        case .processing:
            // Processing shows spinner + label, no text needed.
            overlayModel.partialText = ""

        case .done:
            // Done shows the delivered tick + frozen final time in the header.
            overlayModel.partialText = ""
            overlayModel.elapsedSeconds = 9

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

    // MARK: - Simulate dictation (scripted) target

    /// Parse the script text from `--debug-open simulate-dictation-scripted:<text>`
    /// out of arbitrary `args` (not necessarily `CommandLine.arguments` — this is
    /// called from `DictationController.init()`, at construction time, to decide
    /// which transcriber to build). Returns `nil` when the target isn't present at
    /// all, so callers can distinguish "no scripted debug launch" from "scripted
    /// launch with empty/omitted text" (which falls back to a sample sentence).
    ///
    /// NOTE: `open --args` splits on whitespace — pass the whole value quoted,
    /// e.g. `--debug-open "simulate-dictation-scripted:hello there"`, or only the
    /// first word survives.
    static func scriptedDictationText(in args: [String]) -> String? {
        guard let idx = args.firstIndex(of: "--debug-open"), args.indices.contains(idx + 1) else {
            return nil
        }
        let raw = args[idx + 1]
        guard raw.hasPrefix("simulate-dictation-scripted") else { return nil }
        let fallback = "the quick brown fox jumps over the lazy dog"
        guard let colon = raw.firstIndex(of: ":") else { return fallback }
        let text = String(raw[raw.index(after: colon)...])
        return text.isEmpty ? fallback : text
    }

    /// Drives the controller's REAL `beginDictation()`/`endDictation()` path —
    /// the same one the hotkey and CLI use — so the overlay, caret overlay, and
    /// menubar icon (all of which observe `controller.engine`, not a throwaway
    /// instance) actually animate. The scripted reveal itself already happened:
    /// `DictationController.init()` built `controller.engine` with a
    /// `ScriptedTranscriber` (see `resolveTranscriber(for:)`) when this target was
    /// detected, before this dispatcher ever ran. This method only supplies the
    /// timing — waiting for the reveal to finish before calling `endDictation()`.
    ///
    /// [decision: mirrors `startSimulateDictation`'s 2.5 s pre-delay so the
    ///  harness can bring a target app frontmost before dictation begins; the
    ///  post-begin wait is computed from the actual script length instead of a
    ///  fixed guess, since the reveal cadence is deterministic here.]
    private func startSimulateDictationScripted(text: String, controller: DictationController) {
        Task { [weak self] in
            guard let self else { return }

            self.log.info("DebugLaunchDispatcher: simulate-dictation-scripted starting — waiting 2.5 s for harness to prepare target app.")
            let preDelayNanoseconds: UInt64 = 2_500_000_000
            try? await Task.sleep(nanoseconds: preDelayNanoseconds)

            self.log.info(
                "DebugLaunchDispatcher: simulate-dictation-scripted beginning dictation via controller.beginDictation() with text='\(text.prefix(80), privacy: .private)'."
            )

            let outcome = await controller.beginDictation()
            guard outcome == .started else {
                self.log.error(
                    "DebugLaunchDispatcher: simulate-dictation-scripted beginDictation did not start (outcome=\(String(describing: outcome), privacy: .public))."
                )
                return
            }

            // Wait for the scripted reveal to finish (word count × per-word
            // delay) plus a small margin for cleanup/paste to settle, then end.
            let wordDelayNanoseconds = ScriptedTranscriber.defaultWordDelayNanoseconds
            let wordCount = text.split(separator: " ").count
            let revealNanoseconds = UInt64(max(wordCount - 1, 0)) * wordDelayNanoseconds
            let marginNanoseconds: UInt64 = 500_000_000
            try? await Task.sleep(nanoseconds: revealNanoseconds + marginNanoseconds)

            self.log.info("DebugLaunchDispatcher: simulate-dictation-scripted ending dictation via controller.endDictation().")
            await controller.endDictation()
            self.log.info("DebugLaunchDispatcher: simulate-dictation-scripted complete.")
        }
    }

    // MARK: - Lifetime management

    /// Keeps a reference alive for the app lifetime without global mutable state.
    /// Uses an actor-isolated store so this is data-race-free.
    private func keepAlive(_ object: AnyObject) {
        DebugObjectStore.shared.retain(object)
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
@MainActor
private final class DebugObjectStore {
    static let shared = DebugObjectStore()
    private var objects: [AnyObject] = []

    func retain(_ object: AnyObject) {
        objects.append(object)
    }
}

#endif
