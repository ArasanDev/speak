---
name: project-phase-b-trigger
description: Phase B push-to-talk + trigger mode UI — dual-mode hotkey, HoldEdge, SettingsStore.triggerMode, Codable migration from synthesized to String raw value
metadata:
  type: project
---

Phase B of `specs/dictation-flow.md` complete (loop #19, 2026-06-21).

**What changed:**
- `HotkeyBinding.Trigger`: removed `.singleTapToggle` (never implemented); changed from synthesized `Codable` to `String, Codable` RawValue — persists as `"doubleTap"` / `"hold"`. OLD format (`{"doubleTap":{}}`) fails `try?` in `UserDefaultsBindingStore.load()` → nil → default binding. Clean migration.
- `holdEdge(isFnDown:wasDown:)`: pure free function in `HotkeyMonitor.swift` — maps Fn state transitions to `HotkeyEvent?`. Tested in `HoldEdgeTests` (5 tests).
- `HotkeyMonitor.handle()`: branches on `binding.trigger`; `.doubleTap` branch unchanged (press leading edge only → `DoubleTapDetector`); `.hold` branch calls `holdEdge()` on both edges.
- `HotkeyBinding.with(trigger:)`: returns new binding with same keyCode/modifiers/window, different trigger. Used by `DictationController`.
- `SettingsStore.triggerMode`: `HotkeyBinding.Trigger` persisted as `rawValue` String. Default `.doubleTap`.
- `SettingsView`: "Activation" section with inline `Picker` + contextual hint.
- `DictationController`: applies trigger on init (`monitor.binding.with(trigger:)` → `updateBinding`); `AnyCancellable` subscription on `objectWillChange` + `DispatchQueue.main.async` hop for live updates.

**Synthetic-release safety:** `buildTap()` already resets `lastFnDown = false` on every teardown — hold cannot stick "on" after a mid-hold re-arm. No new variable needed.

**Codable encoding note:** Swift synthesizes `{"doubleTap":{}}` for enum-without-rawvalue. `String` RawValue produces `"doubleTap"`. These are incompatible — old persisted payloads fail decode → nil → fallback. Intentional (spec requirement).

**Why:** specs/dictation-flow.md §6-B design decision (no auto-detect timer, two explicit modes).
**How to apply:** future trigger-mode changes should go through `SettingsStore.triggerMode` as the authoritative value; `DictationController` keeps `UserDefaultsBindingStore` in sync.
