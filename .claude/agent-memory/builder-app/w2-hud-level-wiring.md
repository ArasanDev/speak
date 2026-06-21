---
name: w2-hud-level-wiring
description: W2.1+W2.2 HUD rebuild — how live mic level is sourced, wired, and displayed; key design decisions for OverlayState .error and VoiceOver
metadata:
  type: project
---

## W2.1: Live mic level path

`AudioCapture.rmsLevel(buffer:)` (static, audio-thread-safe) computes RMS on the input buffer
alongside the existing PCM conversion tap. Yields `Double` (0…1) on a parallel `AsyncStream<Double>`
via `startLevelStream()` — called AFTER `start()`, never consumes the PCM stream.

`AudioCaptureProviding` protocol (narrow — only `AppleSpeechTranscriber` conforms) exposes
`.audioCapture: AudioCapture?` so `CaptureSession.levels()` can call `startLevelStream()` without
widening the `Transcribing` protocol.

`SpeakEngine.currentLevels()` mirrors `currentPartials()` — same nil-when-idle pattern.

`OverlayController` drains levels in a parallel `levelsTask` (torn down identically to `partialsTask`
on `.processing` transition / stop / error). One-pole smoothing via `levelSmoothed(previous:target:)`.

**Why:** The PCM buffer stream is single-consumer (transcriber). A separate continuation avoids
starving the STT engine.

## W2.2: OverlayState .error design

`.error` is payload-free (automatic `Equatable`). Reason lives in separate `@Published var errorReason: String?`
on `OverlayViewModel` — mirrors how `partialText`/`elapsedSeconds` are separate from state.

**Why:** giving `.error` an associated value breaks `==` comparisons on `OverlayState` without declaring
`Equatable` manually. The separate-property pattern avoids that.

## W2.2: VoiceOver announcements API (macOS 26)

`NSAccessibility.post(element:notification:userInfo:)` with `.announcementRequested` and
`NSAccessibility.NotificationUserInfoKey.announcement` / `.priority` — the macOS 26 renamed API.
Old names (`NSAccessibilityAnnouncementKey`, `NSAccessibilityPriorityKey`) are deprecated aliases.
**Verified:** compiled cleanly against local macOS 26 SDK.

## W2.2: Escape-to-cancel

Global `NSEvent.addGlobalMonitorForEvents(matching: .keyDown)` monitor; keyCode 53 = Escape.
Return type is `Any?` (not `NSObjectProtocol`). Cannot consume the event (global monitors
are observe-only). Monitor installed at `start()`, removed at `stop()`/`cancelImmediate()`.
`DictationController.onEscapeCancel` callback → `cancelDictation()` → `engine.cancelDictation()`.

**Why global monitor:** panel is non-activating (LSUIElement app); local monitors never fire when
another app is focused.

## WaveformView: 15-bar vs 5-bar

v0 used 5 bars (Handy reference). W2.2 uses 15 bars (VoiceInk blueprint, research §0 finding #1).
`levelBarHeightsPhased(level:phase:barCount:…)` in `LevelMath.swift` adds per-bar sinusoidal ripple.
Phase is caller-controlled (from SwiftUI animation state) so the function stays pure + unit-testable.
