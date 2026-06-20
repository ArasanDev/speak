---
name: cgeventtap-hotkey
description: Use when implementing or modifying the CGEventTap-based global hotkey monitor in SpeakCore — specifically HotkeyMonitor, double-tap Fn detection, HotkeyBinding persistence, or Accessibility/Input Monitoring permission integration.
---

# CGEventTap Hotkey Monitor — Implementation Pointer

## Architectural Seam

Type: `HotkeyMonitor` — lives at `SpeakCore/Hotkey/HotkeyMonitor.swift`

Uses **CGEventTap** (CoreGraphics) to intercept system-wide keyboard events and emit:

```swift
enum HotkeyEvent {
    case startCapture
    case stopCapture
}
```

Default binding: double-tap Fn key (`keyCode kVK_Function = 0x3F`), detection window = **400 ms** — this is a `[decision]`, to be tuned empirically at P13; it is not a magic number.

`HotkeyBinding` is `Codable` for persistence. `modifiers: CGEventFlags` requires custom `Codable` conformance (raw integer encode/decode).

## Hard Constraints

- The tap must fire while **another app has focus** — this is a system-wide event tap, not an in-app key listener.
- Requires two OS permissions: **Accessibility** and **Input Monitoring**. The tap must not be installed until both are granted; attempting without them silently fails or crashes.
- **False-trigger rate target**: fewer than 1 unintended activation per 30 minutes of normal use (`benchmark.md` metric `F_rate`). The 400 ms window is the primary tuning knob.
- Double-tap logic must be stateful: record first Fn keydown timestamp, check second Fn keydown against the window, emit `startCapture`. A second double-tap (or an explicit binding) emits `stopCapture`.
- Use `os.Logger`. No `print`. No force-unwrap. No main-thread blocking (the CGEventTap callback runs on a dedicated run loop thread).
- v0: Apple frameworks only. No third-party hotkey libraries.

## Roadmap P5 Done-When

- `HotkeyMonitor` installs a CGEventTap that detects double-tap Fn from any foreground app.
- Emits `HotkeyEvent.startCapture` on first double-tap, `HotkeyEvent.stopCapture` on second.
- `HotkeyBinding` round-trips through `Codable` correctly, including `CGEventFlags`.
- Permission absence is detected before tap installation and surfaces a clear error rather than silent failure.
- Manual test: double-tap Fn in Safari → `speak` overlay activates.

## Verify at Implementation Time

**Do not rely on recalled CGEventTap callback signatures or run-loop wiring.** The exact callback type, how to install the tap, which run loop to add it to, and how to detect Fn-key events (some key codes behave differently with `NSEvent` vs raw `CGEvent`) must all be confirmed against current Apple documentation before coding.

Use the `apple-docs-mcp` MCP server (if available) to look up `CGEventTap` and `CGEventTapCreate`. Otherwise, consult `https://developer.apple.com/documentation/coregraphics`. Tag every claim `[verified]`, `[inferred]`, or `[unverified]`. If Fn-key detection requires a different approach than standard keyCode matching, document the finding and tag it `[verified]` once confirmed.
