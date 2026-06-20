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
// Icon mapping (presentation layer):
//   MenubarIcon (SpeakCore, pure+tested) → SF Symbol name (here, App layer).
//   Full P8 polish is deferred; these are functional placeholders.
//   Exact SF Symbol names are [decision] comments below.

import SwiftUI
import AppKit
import SpeakCore

// MARK: - AppDelegate

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    /// Owned here for its lifetime. Passed to SwiftUI via the App's body.
    let controller = DictationController()

    func applicationDidFinishLaunching(_ notification: Notification) {
#if DEBUG
        let debugDispatcher = DebugLaunchDispatcher()
        if let target = DebugLaunchDispatcher.parseTarget() {
            // A debug target fully owns the launch: do NOT call startMonitoring()
            // for ANY target. startMonitoring() runs showOnboardingIfNeeded(),
            // which pops the production onboarding window (when onboarding is
            // incomplete) on top of the requested debug window — defeating the
            // isolation each screenshot needs. The dispatcher opens exactly the
            // one surface the harness asked for; nothing else should draw.
            _ = debugDispatcher.dispatch(target: target, controller: controller)
            // Keep the dispatcher alive for the process lifetime so retained
            // window controllers / panels are not deallocated.
            self.debugDispatcherStorage = debugDispatcher
            return
        }
#endif
        controller.startMonitoring()
    }

#if DEBUG
    /// Holds the `DebugLaunchDispatcher` alive for the process lifetime when a
    /// `--debug-open` target is present. `nil` in normal (non-debug-launch) runs.
    /// [decision: stored on AppDelegate — avoids global mutable state while
    ///  keeping the dispatcher for the full process lifetime]
    private var debugDispatcherStorage: DebugLaunchDispatcher?
#endif
}

// MARK: - SpeakApp

@main
struct SpeakApp: App {

    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            SpeakMenu(controller: appDelegate.controller)
        } label: {
            MenuBarLabel(controller: appDelegate.controller)
        }
        .menuBarExtraStyle(.menu)

        // Settings window — opened via "Settings…" menu item or Cmd+,.
        // [deferred — human verification]: whether this renders and persists
        // live requires running on a Mac with the app active.
        Settings {
            SettingsView(store: appDelegate.controller.settingsStore)
        }
    }
}

// MARK: - MenuBarLabel

/// The always-visible status-bar icon. Updates reactively as `icon` changes.
private struct MenuBarLabel: View {
    @ObservedObject var controller: DictationController

    var body: some View {
        Image(systemName: systemImage(for: controller.icon))
    }

    /// Map the semantic icon to an SF Symbol name (presentation only).
    /// P8 polish: full intent-matched icon set. These are functional placeholders. [decision]
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
        // Status line — reflects current capture state.
        Text(statusLine(for: controller.icon))
            .foregroundStyle(.secondary)

        if controller.permissionsNeeded {
            Divider()
            Button("Grant Accessibility + Input Monitoring") {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy") {
                    NSWorkspace.shared.open(url)
                }
            }
        }

        Divider()

        // Hardware mute (SPEC §7.4). Toggles capture; when muted, the engine
        // refuses to start a session — no audio is read. The label reflects the
        // live mute state.
        Button(controller.isMuted ? "Unmute Microphone" : "Mute Microphone") {
            controller.toggleMute()
        }
        if controller.isMuted {
            Text("Muted — dictation disabled")
                .foregroundStyle(.secondary)
        }

        Divider()

        // Opens the History window (roadmap P9) — searchable past dictations.
        Button("History\u{2026}") {
            controller.showHistory()
        }

        // Opens the Settings scene declared in SpeakApp.body.
        // `SettingsLink` is the canonical SwiftUI way to open a Settings scene
        // from a MenuBarExtra menu — it uses the platform's openSettings action
        // under the hood. [verified: SwiftUI API, macOS 13+]
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
