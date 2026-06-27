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
                SettingsView(controller: ctrl)
            }
        }
    }
}

// MARK: - MenuBarLabel
//
// Rendering mechanism (roadmap P8):
//   Each state is rendered as a SwiftUI Image(systemName:) with
//   `.symbolRenderingMode(.palette)` + `.foregroundStyle(tint)` applied.
//
//   WHY PALETTE:
//   A plain `.foregroundStyle(color)` on a SwiftUI MenuBarExtra label is
//   stripped by the system status-item compositor, which forces template
//   (monochrome) rendering on SF Symbols. `.symbolRenderingMode(.palette)`
//   is the SwiftUI-native mechanism to break out of that path — it signals
//   a multi-layer rendering intent that the compositor preserves.
//   [decision: roadmap P8 — palette is the least-invasive SwiftUI fix;
//    the NSStatusItem `isTemplate=false` refactor is deferred to post-P8
//    polish if this proves insufficient]
//
//   SINGLE-ARGUMENT .foregroundStyle:
//   Using `.foregroundStyle(tint)` (not `.foregroundStyle(tint, .clear)`)
//   because some state symbols (waveform, hourglass) are single-layer; the
//   two-argument form sets the secondary layer to .clear, which is safe for
//   multi-layer symbols but redundant for single-layer. Single-argument is
//   correct in both cases. [decision: P8]
//
//   VERIFIED STATUS: [unverified — live menu-bar screencapture is blocked
//   in the agent's headless environment; the system clock does not appear
//   in the captured image either, confirming capture is missing the menubar
//   layer entirely. Human visual check required via:
//     open <Speak.app> --args --debug-open menubar-icon-listening
//   then observe whether the waveform.circle.fill icon is red.]
//
//   If human check shows monochrome: the authorized fallback is NSStatusItem
//   with `button.image?.isTemplate = false`. Surface to orchestrator as a
//   new post-P8 task — do not attempt inline.
//
//   The idle state uses Color(.secondaryLabelColor) — a semi-transparent
//   white on dark menubar, indistinguishable from a normal template icon at
//   rest. Only active states show distinct hues. [decision: P8]
//
//   No animation is used for the done flash — the 600 ms hold already lives
//   in DictationController (doneFlashNanoseconds). Removing animation here
//   makes Reduce-Motion handling moot.

private struct MenuBarLabel: View {
    @ObservedObject var controller: DictationController

    var body: some View {
        let (symbol, tint, label) = presentation(for: controller.icon)
        Image(systemName: symbol)
            .symbolRenderingMode(.palette)   // [decision: P8] prevents template forcing
            .foregroundStyle(tint)           // primary layer tint; single-arg works for all state symbols
            .accessibilityLabel(label)
    }

    /// Returns `(SF Symbol name, tint color, VoiceOver label)` for each icon state.
    ///
    /// Error uses `xmark.circle` (roadmap P8: "red X") rather than
    /// `exclamationmark.triangle` to match the stated spec and make the symbol
    /// visually distinct from processing.
    ///
    /// Idle uses `.secondary` (system secondary label color) to blend into the
    /// menubar at rest — only active states show distinct hues. [decision: P8]
    private func presentation(for icon: MenubarIcon) -> (String, Color, String) {
        switch icon {
        case .idle:
            // [decision]: calm, always-present waveform; secondary color blends into menubar
            return ("waveform", Color(.secondaryLabelColor), "speak — idle")

        case .listening:
            // [decision]: filled circle = mic actively recording; red = recording signal
            return ("waveform.circle.fill", .speakStateListening, "speak — listening")

        case .processing:
            // [decision]: hourglass = work in flight; yellow = in-progress signal
            return ("hourglass", .speakStateProcessing, "speak — processing")

        case .done:
            // [decision]: checkmark = success; green = done signal; held 600 ms by
            // DictationController.doneFlashNanoseconds before reverting to idle
            return ("checkmark.circle", .speakStateDone, "speak — done")

        case .error:
            // [decision]: xmark.circle = explicit failure glyph (roadmap P8 "red X");
            // red matches the listening color but distinct symbol makes the state clear
            return ("xmark.circle", .speakStateError, "speak — error")
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

        QuickSettingsMenu(store: controller.settingsStore)

        Divider()

        Button("Open speak\u{2026}") {
            controller.showDashboard()
        }
        .keyboardShortcut("o")

        Button("History\u{2026}") {
            controller.showHistory()
        }

        Button("Paste Last Transcript") {
            controller.pasteLastTranscript()
        }
        .keyboardShortcut("v", modifiers: [.command, .control])
        .disabled(controller.lastTranscript.isEmpty)

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

// MARK: - QuickSettingsMenu

/// Menubar quick-control submenus (Wispr's quick-control surface): the neat-writing
/// Style and the transcription Language, both bound to `SettingsStore` so a change
/// applies on the next dictation. Observes the store so the checkmark stays in sync.
private struct QuickSettingsMenu: View {
    let store: SettingsStore

    var body: some View {
        Menu("Style") {
            Picker("Style", selection: Binding(
                get: { store.cleanupStyle },
                set: { store.cleanupStyle = $0 }
            )) {
                ForEach(CleanupStyle.allCases, id: \.self) { style in
                    Text(style.displayName).tag(style)
                }
            }
            .pickerStyle(.inline)
        }

        Menu("Language") {
            Picker("Language", selection: Binding(
                get: { store.language.identifier },
                set: { store.language = Locale(identifier: $0) }
            )) {
                Text("English (US)").tag("en-US")
                Text("English (UK)").tag("en-GB")
            }
            .pickerStyle(.inline)
        }
    }
}
