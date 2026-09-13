// App/SpeakApp.swift
//
// The app shell: a menubar-only (LSUIElement) SwiftUI app. The dictation engine
// lives in SpeakCore.framework; this target is the thin UI shell (architecture §5).
//
// Wiring:
//   AppDelegate constructs DictationController and calls startMonitoring() in
//   applicationDidFinishLaunching — the only correct hook for a menubar-only app.
//   Using .onAppear on the MenuBarExtra menu content would defer arming the
//   hotkey tap until the user first *opens* the menu, which would break the
//   "double-tap Fn works immediately after launch" requirement.
//
// Single-instance guard (Phase A, spec §1.4):
//   If another instance of `com.speak.app` is already running, we activate it
//   and exit early so duplicate launches don't contend for the CGEventTap.
//   The guard runs BEFORE any DictationController construction so resources are
//   not allocated on the secondary instance. The `--debug-open` path is NOT
//   exempted — duplicate debug launches should also terminate early (each
//   debug launch target is self-contained and doesn't need two instances).
//
// Icon mapping (presentation layer):
//   MenubarIcon (SpeakCore, pure+tested) → SF Symbol name (here, App layer).
//   Full P8 polish is deferred; these are functional placeholders.

import AppKit
import SpeakCore
import SwiftUI

// MARK: - AppDelegate

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject {

    /// Owned here for its lifetime. Passed to SwiftUI via the App's body.
    /// Optional because we may terminate early in the single-instance guard.
    /// @Published so the Settings scene re-evaluates once the controller is
    /// assigned in applicationDidFinishLaunching — the scene's body can be
    /// built before that assignment and would otherwise stay empty forever.
    @Published var controller: DictationController?

    /// The NSStatusItem controller, retained for the app lifetime.
    private var statusBarController: StatusBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // H2: XCTest startup gate — must come FIRST, before the single-instance
        // guard below. When SpeakTests runs with TEST_HOST=Speak, the app binary
        // is launched as the test host. Without this guard the single-instance
        // terminate() call (lines below) would fire if a dev instance of speak is
        // already running, non-deterministically killing the test runner process.
        // [decision: gate on XCTestConfigurationFilePath per XCTest convention;
        //  this env var is set by xcodebuild/Xcode for every test run.]
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            return  // hosted as TEST_HOST: skip monitoring, single-instance guard, and onboarding
        }

        // Single-instance & upgrade handoff guard (spec §1.4).
        // Detect any OTHER running instance of this app (exclude self).
        // Uses `com.speak.app` — the PRODUCT_BUNDLE_IDENTIFIER from project.yml.
        let bundleID = "com.speak.app"
        let others = NSRunningApplication
            .runningApplications(withBundleIdentifier: bundleID)
            .filter { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }

        if !others.isEmpty {
            let isReplaceRequested = CommandLine.arguments.contains("--replace") || CommandLine.arguments.contains("--relaunch")
            let currentPath = Bundle.main.bundleURL.path
            let isCurrentCanonical = currentPath.hasPrefix("/Applications/")
            let hasNonCanonicalOther = others.contains { !($0.bundleURL?.path.hasPrefix("/Applications/") ?? false) }

            // If user passed --replace OR the new instance is the canonical /Applications install
            // while the older instance was running from a dev/derived-data path, terminate the older instance!
            if isReplaceRequested || (isCurrentCanonical && hasNonCanonicalOther) {
                for other in others {
                    SpeakLog.app.info("speak: terminating older instance (pid=\(other.processIdentifier, privacy: .public)) to hand off execution.")
                    other.terminate()
                }
                // Brief pause to allow the older instance to release its event tap and IPC ports.
                usleep(150_000)
            } else if let existingInstance = others.first {
                SpeakLog.hotkey.warning(
                    "speak: another instance is already running (pid=\(existingInstance.processIdentifier, privacy: .public)) — activating it and terminating."
                )
                existingInstance.activate()
                if let bundleURL = existingInstance.bundleURL {
                    NSWorkspace.shared.openApplication(at: bundleURL, configuration: NSWorkspace.OpenConfiguration()) { _, _ in }
                }
                NSApplication.shared.terminate(nil)
                return
            }
        }

        // Build the controller now (after the guard — not wasted on secondary instance).
        let ctrl = DictationController()
        self.controller = ctrl

#if DEBUG
        let debugDispatcher = DebugLaunchDispatcher()
        if let target = DebugLaunchDispatcher.parseTarget() {
            _ = debugDispatcher.dispatch(target: target, controller: ctrl)
            self.debugDispatcherStorage = debugDispatcher
            return
        }
#endif
        ctrl.startMonitoring()

        // Create and retain the NSStatusItem controller after monitoring is armed.
        self.statusBarController = StatusBarController(controller: ctrl)

        // Prewarm speech recognition model ~2s after launch without blocking startup render.
        let language = ctrl.settingsStore.language
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            SpeechPrewarmer.shared.prewarm(locale: language)
        }
    }

    /// Open the dashboard window when the user "re-opens" the already-running app —
    /// double-clicking Speak.app in Finder/Launchpad, hitting Enter on it in Spotlight,
    /// or clicking a Dock icon. For a menubar-only (LSUIElement) app this is the natural,
    /// reliable "open the app" gesture, independent of the MenuBarExtra menu (which can be
    /// unresponsive in a background .accessory app). Returns true so AppKit performs no
    /// default reopen behaviour beyond ours.
    /// [decision: 2026-06-29 — user could not open the window via the menubar click;
    ///  re-launch → showDashboard() is a testable, menubar-independent entry point.]
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        controller?.showDashboard()
        return true
    }

#if DEBUG
    private var debugDispatcherStorage: DebugLaunchDispatcher?
#endif
}

// MARK: - SettingsSceneHost

/// Observes `AppDelegate.controller` so the Settings window renders the shared
/// `SettingsExperienceView` once the controller exists. Without observation the
/// scene captured a nil controller at launch and stayed blank forever.
private struct SettingsSceneHost: View {
    @ObservedObject var appDelegate: AppDelegate

    var body: some View {
        if let ctrl = appDelegate.controller {
            let context = ctrl.makeSettingsContext()
            SettingsExperienceView(
                context: context,
                presentation: .standalone,
                onOpenSection: { section in ctrl.showDashboardSection(section) }
            )
            .speakThemed(with: context.themeEngine)
        }
    }
}

// MARK: - SpeakApp

@main
struct SpeakApp: App {

    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // [decision: removed the "appshell" Window scene — dead code superseded by
        //  WindowPresenter.showDashboard() -> DashboardWindowController (plain AppKit).
        //  Nothing in the app ever called openWindow(id: "appshell"); the only thing that
        //  could resurrect it was macOS's automatic window-state restoration reopening a
        //  stale saved window with no content wired up, producing a blank "speak" window.]
        // [decision: one Settings surface, one window — Cmd+, routes to the
        //  dashboard's Mode B via `controller.showSettings()`, same as the
        //  gear icon and menubar item. The SwiftUI `Settings` scene hosts
        //  EmptyView and never opens: its default "Settings…" appSettings
        //  command is replaced by ours. The scene is kept because a
        //  CommandGroup must hang off *some* scene to reach the app menu.
        //  Rationale: the Settings scene creates its window eagerly at launch,
        //  before `controller` exists — producing a degenerate 0×0 window that
        //  autosave then restores forever. Routing to Mode B removes that
        //  whole class of bug plus the second, divergent Settings surface.]
        Settings {
            SettingsSceneHost(appDelegate: appDelegate)
                .frame(minWidth: 760, idealWidth: 940, minHeight: 480, idealHeight: 620)
        }
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") {
                    appDelegate.controller?.showSettings()
                }
                .keyboardShortcut(",")
            }
        }
    }
}
