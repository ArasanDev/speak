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

## W2.3: Perceptual level mapping + asymmetric smoothing + cold-start fix

**Problem:** raw RMS for speech clusters at 0.01–0.08 (1–8% of bar range) — imperceptible.
**Fix:** `levelPerceptual(rms:)` in `LevelMath.swift` — dB normalization mapping [-55 dBFS noise
floor … -3 dBFS clip ceiling] → [0…1]. Speech fills bars naturally; silence drops to calm.

**Smoothing:** `levelSmoothedAsymmetric(previous:target:attackCoeff:decayCoeff:)` replaces the
symmetric `levelSmoothed` in the drain path. attackCoeff=0.5 (snappy onset), decayCoeff=0.85
(natural tail). `levelSmoothed` itself is unchanged — its tests pin the 0.7/0.3 coefficients.

**Pipeline order:** raw RMS → `levelPerceptual` → `levelSmoothedAsymmetric` → `overlayModel.level`
Perceptual mapping runs on instantaneous RMS; smoothing then operates in the perceptual space
the user sees. This order gives correct attack/release feel at the display scale.

**Cold-start race:** `AppleSpeechTranscriber.startStream()` spawns a background Task. `audioProducer.start()`
(which sets `pendingLevelStream`) runs *inside* that Task. `OverlayController.startLevelsDrain` calls
`await provider()` → `startLevelStream()` which races against Task startup. Fix: retry loop in
`startLevelsDrain` — up to 5 attempts × 50ms = 250ms max wait. First dictation now behaves like
warm ones. Static retry constants `levelStreamRetryCount`/`levelStreamRetryIntervalNs` are on `OverlayController`.

**Goal B:** 200ms minimum processing dwell added in `DictationController.endDictation` BEFORE `.done`
transition (paste already happened inside `endDictation()`, so zero text-latency cost). Existing
600ms done-flash preserved.

**Tests (30 total in OverlayLevelTests.swift):** W2.3 adds 10 new cases (21–30) covering:
`levelPerceptual` boundary/speech/noise-floor cases + `levelSmoothedAsymmetric` math/direction cases.
