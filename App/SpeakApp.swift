// App/SpeakApp.swift
//
// The app shell: a menubar-only (LSUIElement) SwiftUI app. v0 P1 scaffold —
// idle waveform icon + a menu with About and Quit. The dictation engine lives
// in SpeakCore.framework; this target is the thin UI shell (architecture §5).

import SwiftUI
import AppKit
import SpeakCore

@main
struct SpeakApp: App {

    init() {
        // Proves SpeakCore links and the logging seam works from the app target.
        SpeakLog.engine.info("speak launched")
    }

    var body: some Scene {
        MenuBarExtra("speak", systemImage: "waveform") {
            SpeakMenu()
        }
        .menuBarExtraStyle(.menu)
    }
}

private struct SpeakMenu: View {
    var body: some View {
        Button("About speak…") {
            NSApplication.shared.orderFrontStandardAboutPanel(nil)
            NSApplication.shared.activate(ignoringOtherApps: true)
        }
        Divider()
        Button("Quit speak") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}
