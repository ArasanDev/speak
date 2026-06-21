---
name: project-w1-right-command
description: W1.0+W1.1 — Right-Command default binding, modifierMask helper, FnDebouncer, display helpers
metadata:
  type: project
---

## W1.0 — Event model verification

Right-Command fires `CGEventType.flagsChanged` (NOT keyDown/keyUp) — confirmed
via `swiftc -typecheck` against macOS 26 SDK [verified: 2026-06-21].

- `kVK_RightCommand = 54` (0x36) [verified]
- `kVK_Command = 55` (0x37) left ⌘ [verified]
- `kVK_Function = 63` (0x3F) Fn [verified]
- Both left and right ⌘ set `.maskCommand` (rawValue 1048576) in CGEventFlags
- Left vs right is disambiguated ONLY by the keyCode field on flagsChanged
- Runtime behavior tagged `[inferred]` by symmetry with verified Fn model

**Why:** The plan's "corrected event model" claim was unverified; confirmed first before touching code.

## W1.1 — Implementation

**Default binding changed**: `HotkeyBinding.defaultBinding` now uses `kVK_RightCommand` (54) instead of `kVK_Function` (63). Rationale: avoids macOS system-dictation Fn conflict; right ⌘ rarely used in chords.

**Critical landmine fixed**: `handle()` in `HotkeyMonitor` previously computed `isFnDown = flags.contains(.maskSecondaryFn)` — always false for a Command binding. Fix: `modifierMask(forKeyCode:)` pure helper in `HotkeyDetection.swift` returns the correct flag for each keyCode.

**State tracking split**: `lastBoundKeyDown` tracks the trigger key; `lastFnDown` tracks physical Fn for the Fn+Ctrl chord detector. Renaming `lastFnDown` blindly would break the chord.

**FnDebouncer**: 40 ms debounce on Fn path only (keyCode == 63). Applied BEFORE edge-state update so dropped events don't advance `lastBoundKeyDown`. Named constant `FnDebouncer.debounceWindow = 0.04`.

**Display helpers**: `HotkeyBinding.keySymbol` ("Fn", "⌘") + `.displayString` ("⌘⌘ Right Command", "Fn ×2", etc.). `DictationController.currentHotkeyCombo()` now reads `binding.keySymbol` instead of hardcoded "Fn".

**Fn selectable binding**: `HotkeyBinding.fnBinding` (static, keyCode 63) added as the named selectable Fn option.

**Files changed**:
- `SpeakCore/Hotkey/HotkeyDetection.swift` — `modifierMask(forKeyCode:)` + `FnDebouncer`
- `SpeakCore/Hotkey/HotkeyBinding.swift` — new default, `fnBinding`, `keySymbol`, `displayString`
- `SpeakCore/Hotkey/HotkeyMonitor.swift` — `lastBoundKeyDown`, `fnDebouncer`, `handle()` rewrite
- `App/DictationController.swift` — `currentHotkeyCombo()` uses `keySymbol`
- `SpeakTests/HotkeyMonitorTests.swift` — new `ModifierMaskTests`, `FnDebouncerTests`, `HotkeyBindingDisplayTests`

**Gates**: build ✅ · tests ✅ · lint 0 serious ✅ · moat 7/7 ✅

**How to apply:** When editing the hotkey trigger path, always derive "is key down" from `modifierMask(forKeyCode:)` — never assume `.maskSecondaryFn` for anything except Fn. Keep chord path (`lastFnDown`) separate from trigger path (`lastBoundKeyDown`).
