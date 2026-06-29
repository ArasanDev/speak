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
final class AppDelegate: NSObject, NSApplicationDelegate {

    /// Owned here for its lifetime. Passed to SwiftUI via the App's body.
    /// Optional because we may terminate early in the single-instance guard.
    var controller: DictationController?

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

        // Single-instance guard (spec §1.4).
        // Detect any OTHER running instance of this app (exclude self).
        // Uses `com.speak.app` — the PRODUCT_BUNDLE_IDENTIFIER from project.yml.
        // [verified: NSRunningApplication.runningApplications(withBundleIdentifier:)
        //  returns all processes with that bundle id, including the current one].
        let bundleID = "com.speak.app"
        let others = NSRunningApplication
            .runningApplications(withBundleIdentifier: bundleID)
            .filter { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }

        if let existingInstance = others.first {
            SpeakLog.hotkey.warning(
                "speak: another instance is already running (pid=\(existingInstance.processIdentifier, privacy: .public)) — activating it and terminating."
            )
            existingInstance.activate()
            NSApplication.shared.terminate(nil)
            return
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

// MARK: - SpeakApp

@main
struct SpeakApp: App {

    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // AppShell window — opened on demand from the menu, not at launch.
        // Window scene renders when presented; doesn't auto-open on app start.
        Window("speak", id: "appshell") {
            if let ctrl = appDelegate.controller {
                AppShell(controller: ctrl)
            }
        }
        .defaultPosition(.center)
        .defaultSize(width: 960, height: 600)

        Settings {
            if let ctrl = appDelegate.controller {
                SettingsView(controller: ctrl)
            }
        }
    }
}
