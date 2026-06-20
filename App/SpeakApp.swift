// App/SpeakApp.swift
//
// The app shell: a menubar-only (LSUIElement) SwiftUI app. The dictation engine
// lives in SpeakCore.framework; this target is the thin UI shell (architecture
// §5). The icon reflects capture state; full state-driven icons land at P8.

import SwiftUI
import AppKit
import SpeakCore

@main
struct SpeakApp: App {

    @StateObject private var micTest = MicTestController()

    var body: some Scene {
        MenuBarExtra("speak", systemImage: micTest.isCapturing ? "waveform.circle.fill" : "waveform") {
            SpeakMenu(micTest: micTest)
        }
        .menuBarExtraStyle(.menu)
    }
}

private struct SpeakMenu: View {
    @ObservedObject var micTest: MicTestController

    var body: some View {
        // Temporary P2 affordance — real hotkey-driven capture arrives at P5.
        Button(micTest.isCapturing ? "Stop mic test" : "Start mic test") {
            micTest.toggle()
        }
        Divider()
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
