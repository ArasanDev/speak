---
name: project-p5-hotkey-complete
description: P5 HotkeyMonitor implementation complete — key API decisions, SDK verifications, and deferred items
metadata:
  type: project
---

P5 (global hotkey) complete as of 2026-06-20. `SpeakCore/Hotkey/HotkeyMonitor.swift` +
`SpeakTests/HotkeyMonitorTests.swift` (19 new tests). `make test` 44/44 green.

**Why:** P5 is on the critical path (P3.5 → P5 → P6 → P11 → P13). HotkeyMonitor
must fire while another app has focus, which requires CGEventTap.

**Key SDK findings [verified against macOS 26 SDK with swiftc -typecheck]:**
- `CGEventTapCreate` is obsoleted in Swift 3 → use `CGEvent.tapCreate(tap:place:options:eventsOfInterest:callback:userInfo:)`
- Fn key fires as `CGEventType.flagsChanged` (rawValue=12), NOT keyDown
- Press-edge: `CGEventFlags.maskSecondaryFn` (rawValue=8388608) set = Fn down
- `kVK_Function = 63 = 0x3F` (Carbon/HIToolbox, verified at runtime)
- `CGEvent.tapEnable(tap:enable:)` to re-enable on tapDisabledByTimeout

**Architecture decisions:**
- `DoubleTapDetector` is a pure value-type struct — timestamps injected, no wall-clock
- `self` passed to C callback via `Unmanaged.passUnretained` (no global state, no retain cycle)
- `BindingStoring` protocol boundary makes UserDefaults mockable
- Fn-event model [inferred, DEFERRED]: `.maskSecondaryFn` bit is the Fn/Globe key —
  standard CG convention but live confirmation requires non-sandboxed run with perms granted

**Deferred (needs human verification):**
- Tap fires while another app has focus (Accessibility + Input Monitoring granted)
- Permission prompts appear on first run
- False-trigger rate < 1/30min (P13 dogfood, benchmark.md §7 F_rate)

**How to apply:** Next seam is P6 (PasteboardWriter). Architecture §11 has the
reference implementation for NSPasteboard write + Cmd+V. The paste-provenance
behavior (macOS 26.4 Terminal check) is [unverified] — must test empirically.
See [[project-fn-event-model]] for the Fn detection model details.
