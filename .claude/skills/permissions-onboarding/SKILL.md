---
name: permissions-onboarding
description: Use when implementing or modifying OS permission handling or the onboarding flow in speak — specifically PermissionManager, PermissionKind/PermissionState, the two required permissions (microphone, accessibility), or the onboarding UI in App/Onboarding/.
---

# Permissions Onboarding — Implementation Pointer

## Architectural Seam

Type: `PermissionManager` — lives at `SpeakCore/Permissions/PermissionManager.swift`

```swift
enum PermissionKind {
    case microphone
    case accessibility
}

enum PermissionState {
    case notDetermined
    case requesting
    case granted
    case denied
    case restricted
}
```

Onboarding UI lives at `App/Onboarding/`. It is a SwiftUI flow that walks the user through granting both permissions before first use.

## Hard Constraints

- **Exactly two permissions — no more, no fewer:** microphone, accessibility. Do not request Input Monitoring (`.defaultTap` → Accessibility-gated; IM is not used in v0).
- **Each permission screen must explain WHY** it is needed in plain language before requesting it. Do not show a system prompt cold.
- **Deep-link to System Settings** for manual-grant permissions using `x-apple.systempreferences:com.apple.preference.security`. Do not instruct users to navigate there manually.
- **Permission acquisition is asymmetric:**
  - Microphone: runtime prompt via `AVCaptureDevice` — the OS shows the dialog. (`AVAudioSession` is unavailable on macOS; `PermissionManager.swift` uses `AVCaptureDevice.requestAccess(for: .audio)`.)
  - Accessibility: cannot be granted programmatically — show the deep-link button and poll/observe for the grant.
- **Mid-session revocation must be detected.** If the user revokes a permission while the app is active, transition to error state immediately; do not crash or silently continue.
- Use `os.Logger`. No `print`. No force-unwrap. No `try!`.
- v0: Apple frameworks only. No third-party permission libraries.

## Roadmap P7 Done-When

- `PermissionManager` tracks `PermissionState` for both kinds and publishes state changes.
- Onboarding flow presents each permission step with a clear WHY explanation and the appropriate action (runtime prompt for mic; deep-link button for accessibility).
- Deep-link `x-apple.systempreferences:com.apple.preference.security` (with pane anchors such as `Privacy_Microphone`, `Privacy_Accessibility` on macOS 13+) is used for manual-grant permissions — **verify at implementation time** that the routing opens the correct pane on macOS 26 (runtime behavior, not statically verifiable).
- App does not proceed past onboarding until both permissions are `granted`.
- Mid-session revocation of any permission is detected and transitions the app to error state with a recoverable prompt (re-open settings).
- Unit tests cover all `PermissionState` transitions for each `PermissionKind`.

## Verify at Implementation Time

**Do not recall the exact APIs for checking accessibility permission state from training data.** The APIs for `AXIsProcessTrusted` or equivalent macOS 26 replacements, and how to observe changes without polling, must be confirmed against current Apple documentation before coding.

Use `apple-docs-mcp` (if available) to look up `AXIsProcessTrusted`. Otherwise, fetch from `https://developer.apple.com/documentation/applicationservices`. Tag every API claim `[verified]`, `[inferred]`, or `[unverified]`. Document the exact observation mechanism (notification, timer poll, or delegate) in `specs/verification-ledger.md` once confirmed.
