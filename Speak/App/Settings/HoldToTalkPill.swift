// App/Settings/HoldToTalkPill.swift
//
// The "Test My Voice" trigger: a capsule pill that records while held, with a
// tap-to-latch mode for trackpad users — a press shorter than `latchThreshold`
// keeps recording until the next tap, so both interaction styles work.
//
// Implementation: `DragGesture(minimumDistance: 0)` gives press-down/press-up
// edges without a minimum duration — SwiftUI's `LongPressGesture` would eat
// quick taps, and `Button` exposes no release event. [decision]
//
// STATE VISUALS (themed tokens only):
//   idle     — mica wash + cardBorder hairline, mic glyph
//   arming   — held but capture not live yet → speakUIAccent tint
//   recording— onAir fill + solid border (the mic IS capturing — the tally
//              rule holds); latched swaps the border to a dashed stroke and a
//              deeper fill to read "hands-free"
//   busy     — cleanup in flight → spinner, mica, hit-testing off
//   disabled — mic permission missing → dimmed wash, mic.slash glyph

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

    /// What the user meant by a release that happened before capture went
    /// live — `onBegin` is async, so a fast tap can lift off while the phase
    /// is still `.idle`. Without this, that tap would neither latch nor end
    /// and the recording would run orphaned until the safety cap.
    private enum PendingRelease { case end, latch }

    @State private var pressing = false
    @State private var latched = false
    @State private var pressStart = Date()
    @State private var pendingRelease: PendingRelease?
    /// Marks the press that UN-latched a recording — its release must not
    /// compute a latch/end intent (the end is already in flight).
    @State private var unlatchPress = false

    private var active: Bool { model.phase == .listening }
    private var busy: Bool { model.phase == .processing }
    /// Held down but capture hasn't gone live yet — the "arming" edge, shown
    /// in the UI accent so the press registers visually before `onBegin` lands.
    private var arming: Bool { pressing && !active && !busy }

    var body: some View {
        HStack(spacing: SpeakSpacing.xs) {
            if busy {
                ProgressView()
                    .controlSize(.mini)
                    .tint(Color.speakMica)
            } else {
                Image(systemName: iconName)
            }
            Text(labelText)
        }
        .font(.speakBody(.caption, semibold: true))
        .padding(.horizontal, SpeakSpacing.md)
        .padding(.vertical, SpeakSpacing.sm)
        .background(Capsule().fill(fill))
        .overlay(
            Capsule().stroke(
                borderColor,
                style: latched && active
                    ? StrokeStyle(lineWidth: 1, dash: [4, 3]) // [decision: dashes = "pinned" hands-free]
                    : StrokeStyle(lineWidth: 1)
            )
        )
        .foregroundStyle(foreground)
        .scaleEffect(pressing && !latched ? 0.97 : 1)
        .contentShape(Capsule())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in pressDown() }
                .onEnded { _ in pressUp() }
        )
        .allowsHitTesting(isEnabled && !busy)
        .onChange(of: model.phase) { _, phase in
            // Apply a release intent deferred while `onBegin` was in flight.
            guard let pending = pendingRelease else { return }
            switch phase {
            case .listening:                     apply(pending)
            case .processing, .done, .failed:    pendingRelease = nil
            case .idle:                          break
            }
        }
        .animation(.spring(duration: 0.15), value: active)
        .animation(.spring(duration: 0.15), value: pressing)
        .animation(.spring(duration: 0.15), value: latched)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(active ? "Stop test recording" : "Test your voice")
        .accessibilityHint(
            isEnabled
                ? "Hold to record, release to finish — or tap once to keep recording."
                : "Requires microphone permission."
        )
    }

    // MARK: - State visuals

    private var iconName: String {
        if !isEnabled { return "mic.slash" }
        return active ? "stop.fill" : "mic.fill"
    }

    private var fill: Color {
        if !isEnabled { return Color.speakMica.opacity(0.05) }
        if active { return Color.speakOnAir.opacity(latched ? 0.24 : 0.16) }
        if arming { return Color.speakUIAccent.opacity(0.12) }
        return Color.speakMica.opacity(0.10)
    }

    private var borderColor: Color {
        if !isEnabled { return Color.speakCardBorder.opacity(0.5) }
        if active { return Color.speakOnAir }
        if arming { return Color.speakUIAccent }
        return Color.speakCardBorder
    }

    private var foreground: Color {
        if active { return Color.speakOnAir }
        if !isEnabled { return Color.speakMica }
        if arming { return Color.speakUIAccent }
        return Color.speakBone
    }

    private var labelText: String {
        if !isEnabled { return "Microphone needed" }
        switch model.phase {
        case .listening:
            return latched ? "Recording — tap to stop" : "Recording — release to finish"

        case .processing:
            return "Cleaning up…"

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
            pendingRelease = nil
            unlatchPress = true
            Task { await onEnd() }
        } else if model.phase != .listening {
            pressStart = Date()
            Task { await onBegin() }
        }
    }

    private func pressUp() {
        guard pressing else { return }
        pressing = false
        if unlatchPress { unlatchPress = false; return }
        if latched { return }
        let intended: PendingRelease =
            Date().timeIntervalSince(pressStart) < Self.latchThreshold ? .latch : .end
        if model.phase == .listening {
            apply(intended)
        } else {
            // `onBegin` hasn't flipped the phase to .listening yet — defer the
            // intent; the onChange handler applies it once capture is live
            // (or drops it if the start failed).
            pendingRelease = intended
        }
    }

    private func apply(_ action: PendingRelease) {
        pendingRelease = nil
        switch action {
        case .latch: latched = true

        case .end:   Task { await onEnd() }
        }
    }
}
