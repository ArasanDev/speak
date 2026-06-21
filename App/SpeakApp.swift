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

import SwiftUI
import AppKit
import SpeakCore

// MARK: - AppDelegate

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    /// Owned here for its lifetime. Passed to SwiftUI via the App's body.
    /// Optional because we may terminate early in the single-instance guard.
    var controller: DictationController?

    func applicationDidFinishLaunching(_ notification: Notification) {
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
        MenuBarExtra {
            if let ctrl = appDelegate.controller {
                SpeakMenu(controller: ctrl)
            }
        } label: {
            if let ctrl = appDelegate.controller {
                MenuBarLabel(controller: ctrl)
            } else {
                Image(systemName: "waveform")
            }
        }
        .menuBarExtraStyle(.menu)

        Settings {
            if let ctrl = appDelegate.controller {
                SettingsView(store: ctrl.settingsStore)
            }
        }
    }
}

// MARK: - MenuBarLabel

private struct MenuBarLabel: View {
    @ObservedObject var controller: DictationController

    var body: some View {
        Image(systemName: systemImage(for: controller.icon))
    }

    private func systemImage(for icon: MenubarIcon) -> String {
        switch icon {
        case .idle:
            return "waveform"                       // [decision]: calm, always-present waveform
        case .listening:
            return "waveform.circle.fill"           // [decision]: filled = active capture
        case .processing:
            return "hourglass"                      // [decision]: processing / cleanup in flight
        case .done:
            return "checkmark.circle"               // [decision]: brief success flash
        case .error:
            return "exclamationmark.triangle"       // [decision]: error state
        }
    }
}

// MARK: - SpeakMenu

private struct SpeakMenu: View {
    @ObservedObject var controller: DictationController

    var body: some View {
        Text(statusLine(for: controller.icon))
            .foregroundStyle(.secondary)

        if controller.permissionsNeeded {
            Divider()
            Button("Grant Accessibility Permission") {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                    NSWorkspace.shared.open(url)
                }
            }
        }

        Divider()

        Button(controller.isMuted ? "Unmute Microphone" : "Mute Microphone") {
            controller.toggleMute()
        }
        if controller.isMuted {
            Text("Muted — dictation disabled")
                .foregroundStyle(.secondary)
        }

        Divider()

        Button("History\u{2026}") {
            controller.showHistory()
        }

        SettingsLink {
            Text("Settings\u{2026}")
        }
        .keyboardShortcut(",")

        Divider()

        Button("About speak\u{2026}") {
            NSApplication.shared.orderFrontStandardAboutPanel(nil)
            NSApplication.shared.activate(ignoringOtherApps: true)
        }

        Divider()

        Button("Quit speak") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }

    private func statusLine(for icon: MenubarIcon) -> String {
        switch icon {
        case .idle:       return "speak — ready (double-tap Fn to start)"
        case .listening:  return "speak — listening…"
        case .processing: return "speak — processing…"
        case .done:       return "speak — done"
        case .error:      return "speak — error (try again)"
        }
    }
}
