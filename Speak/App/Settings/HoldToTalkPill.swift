// App/Settings/HoldToTalkPill.swift
//
// The "Test My Voice" trigger: a capsule pill that records while held, with a
// tap-to-latch mode for trackpad users — a press shorter than `latchThreshold`
// keeps recording until the next tap, so both interaction styles work.
//
// Implementation: `DragGesture(minimumDistance: 0)` gives press-down/press-up
// edges without a minimum duration — SwiftUI's `LongPressGesture` would eat
// quick taps, and `Button` exposes no release event. [decision]

import SpeakCore
import SwiftUI

struct HoldToTalkPill: View {

    /// Drives the label/level state — the pill reflects the sandbox phase.
    let model: VoiceSandboxModel
    /// When false the pill is inert (e.g. mic permission missing).
    var isEnabled: Bool = true
    let onBegin: () async -> Void
    let onEnd: () async -> Void

    /// A press shorter than this latches recording until the next tap.
    /// [decision: 350 ms — above a deliberate click (~120 ms), below a
    ///  deliberate hold; same order as the hotkey double-tap window]
    static let latchThreshold: TimeInterval = 0.35

    @State private var pressing = false
    @State private var latched = false
    @State private var pressStart = Date()

    private var active: Bool { model.phase == .listening }
    private var busy: Bool { model.phase == .processing }

    var body: some View {
        HStack(spacing: SpeakSpacing.xs) {
            if busy {
                ProgressView().controlSize(.mini)
            } else {
                Image(systemName: active ? "stop.fill" : "mic.fill")
            }
            Text(labelText)
        }
        .font(.speakBody(.caption, semibold: true))
        .padding(.horizontal, SpeakSpacing.md)
        .padding(.vertical, SpeakSpacing.sm)
        .background(
            Capsule().fill(
                active
                    ? Color.speakOnAir.opacity(0.16)
                    : Color.primary.opacity(isEnabled ? 0.07 : 0.03)
            )
        )
        .overlay(
            Capsule().stroke(
                active ? Color.speakOnAir : Color.speakCardBorder,
                lineWidth: 1
            )
        )
        .foregroundStyle(
            active ? Color.speakOnAir : Color.speakBone.opacity(isEnabled ? 1 : 0.4)
        )
        .scaleEffect(pressing && !latched ? 0.97 : 1)
        .contentShape(Capsule())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in pressDown() }
                .onEnded { _ in pressUp() }
        )
        .allowsHitTesting(isEnabled && !busy)
        .animation(.spring(duration: 0.15), value: active)
        .animation(.spring(duration: 0.15), value: pressing)
        .accessibilityLabel("Test your voice")
        .accessibilityHint("Hold to record, release to run cleanup — or tap once to latch.")
    }

    private var labelText: String {
        switch model.phase {
        case .listening:
            return latched ? "Recording — tap to stop" : "Recording — release to clean"

        case .processing:
            return "Cleaning…"

        case .done:
            return "Hold to test again"

        case .failed:
            return "Hold to retry"

        case .idle:
            return "Hold to test your voice"
        }
    }

    // MARK: - Press edges

    private func pressDown() {
        guard !pressing, isEnabled, !busy else { return }
        pressing = true
        if latched {
            latched = false
            Task { await onEnd() }
        } else if model.phase != .listening {
            pressStart = Date()
            Task { await onBegin() }
        }
    }

    private func pressUp() {
        guard pressing else { return }
        pressing = false
        if latched { return }
        guard model.phase == .listening else { return }
        if Date().timeIntervalSince(pressStart) < Self.latchThreshold {
            latched = true
        } else {
            Task { await onEnd() }
        }
    }
}
