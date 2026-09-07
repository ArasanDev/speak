---
name: im-removal
description: Input Monitoring removed from speak v0 — CGEventTap .defaultTap needs AX only, not IM
metadata:
  type: project
---

Input Monitoring was removed from v0 entirely (2026-06-22). The CGEventTap uses `.defaultTap` and is gated on Accessibility alone — IM was vestigial scaffolding from an earlier listen-only-tap design.

**Why:** Verified empirically on live machine: hotkey fires without IM granted. HotkeyMonitor.swift §84–86 explicitly documents this. The IM onboarding step was falsely telling users "Input Monitoring lets speak detect your hotkey."

**How to apply:** v0 now has exactly TWO required permissions: Microphone + Accessibility. Any future builder work should not re-add IM. The rule is: `.defaultTap` → AX only; `.listenOnlyTap` → IM needed.

**Key changes made:**
- `PermissionKind` enum: 2 cases only (`.microphone`, `.accessibility`)
- `PermissionManaging` protocol: no `requestInputMonitoring()`
- `PermissionManager`: no `import IOKit.hid`, no IOHIDCheckAccess/IOHIDRequestAccess
- `OnboardingStep`: no `.inputMonitoring` — 4-step flow: welcome→mic→ax→hotkey→done
- `OnboardingStateMachine.evaluate()`: 2-param signature (no inputMonitoring param)
- `SpeakError`: no `.inputMonitoringDenied`
- MoatAuditTests allowedImports: `IOKit.hid` removed

**Docs still needing orchestrator update (out of builder-input scope):**
- `AGENTS.md §2.2` — still says "exactly three permissions"
- `.claude/skills/swift-code-review/SKILL.md` — same
- `docs/architecture.md §6/§7.2` — may still list IM
- `docs/product.md §7.3` — 5-step onboarding order
- `specs/verification-ledger.md` line 39 — row mentions "Accessibility implicitly satisfies Input Monitoring"; needs update to say IM is not requested at all in v0
