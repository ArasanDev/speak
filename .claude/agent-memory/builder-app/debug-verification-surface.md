---
name: debug-verification-surface
description: #if DEBUG --debug-open verification harness added for v0 human verification gate; files, commands, design decisions
metadata:
  type: project
---

The `--debug-open <target>` DEBUG-only launch-arg surface was implemented to let an automated agent drive the UI and live engine path using only `open --args` + `screencapture`.

**Why:** v0 is code-complete; the human-verification gate (`docs/human-verification.md`) requires live app screenshots + paste behavior. AX/System Events UI-scripting is blocked without accessibility grants.

**How to apply:** When human-verification tasks come up, the harness is already present — just use the `open --args` commands below.

## Files added (all `#if DEBUG` guarded)

- `App/Debug/DebugLaunchDispatcher.swift` — parses `--debug-open`, dispatches to handlers, manages DEBUG-only lifetimes via `DebugObjectStore` actor
- `SpeakCore/Debug/FixtureAudioProducer.swift` — `AudioBufferProducing` that streams `hello_speech.caf`; resolves via `#filePath`-anchored source-tree path

## Files modified (additions all `#if DEBUG` guarded)

- `App/SpeakApp.swift` — `applicationDidFinishLaunching` dispatches before `startMonitoring()`
- `App/Onboarding/OnboardingViewModel.swift` — `forceStep(_:)` DEBUG method; suppresses poll
- `App/Onboarding/OnboardingWindowController.swift` — `showForcedStep(_:)` DEBUG method; skips `watchForCompletion()`

## Exact open --args commands

Assume app is at `build/DerivedData/Build/Products/Debug/Speak.app`.

```
# Onboarding screens
open build/DerivedData/Build/Products/Debug/Speak.app --args --debug-open onboarding-welcome
open build/DerivedData/Build/Products/Debug/Speak.app --args --debug-open onboarding-microphone
open build/DerivedData/Build/Products/Debug/Speak.app --args --debug-open onboarding-accessibility
open build/DerivedData/Build/Products/Debug/Speak.app --args --debug-open onboarding-inputmonitoring
open build/DerivedData/Build/Products/Debug/Speak.app --args --debug-open onboarding-hotkey
open build/DerivedData/Build/Products/Debug/Speak.app --args --debug-open onboarding-done

# Windows
open build/DerivedData/Build/Products/Debug/Speak.app --args --debug-open settings
open build/DerivedData/Build/Products/Debug/Speak.app --args --debug-open history

# Overlay panel
open build/DerivedData/Build/Products/Debug/Speak.app --args --debug-open overlay-demo

# Real engine pipeline (paste into frontmost app after 2.5+3.5s)
open build/DerivedData/Build/Products/Debug/Speak.app --args --debug-open simulate-dictation
```

## Key design decisions

- `simulate-dictation` skips `startMonitoring()` entirely to prevent onboarding from stealing focus
- All other targets call `startMonitoring()` normally
- `simulate-dictation` waits 2.5s pre-begin (harness prepares TextEdit) then 3.5s post-begin (fixture duration 1.334s + 2.166s STT margin) before `endDictation()`
- `FixtureAudioProducer.helloSpeechFixture()` walks up `#filePath` 3 levels to repo root, then `SpeakTests/Fixtures/hello_speech.caf`
- `DebugObjectStore` is an actor holding window controllers/panels alive without global mutable state
- Settings window uses `NSWindow + NSHostingView` (not `NSApp.sendAction Selector("showSettingsWindow:")` which is runtime-fragile on macOS 26)
- Onboarding forced-step suppresses both the poll loop and `watchForCompletion()` auto-close
