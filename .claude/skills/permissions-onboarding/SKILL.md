---
name: permissions-onboarding
description: Use when implementing or modifying OS permission handling or the onboarding flow in speak — specifically PermissionManager, PermissionKind/PermissionState, the three required permissions (microphone, accessibility, inputMonitoring), or the onboarding UI in App/Onboarding/.
---

# Permissions Onboarding — Implementation Pointer

## Architectural Seam

Type: `PermissionManager` — lives at `SpeakCore/Permissions/PermissionManager.swift`

```swift
enum PermissionKind {
    case microphone
    case accessibility
    case inputMonitoring
}

enum PermissionState {
    case notDetermined
    case requesting
    case granted
    case denied
    case restricted
}
```

Onboarding UI lives at `App/Onboarding/`. It is a SwiftUI flow that walks the user through granting all three permissions before first use.

## Hard Constraints

- **Exactly three permissions — no more, no fewer:** microphone, accessibility, inputMonitoring. Do not request any other entitlement in v0.
- **Each permission screen must explain WHY** it is needed in plain language before requesting it. Do not show a system prompt cold.
- **Deep-link to System Settings** for manual-grant permissions using `x-apple.systempreferences:com.apple.preference.security`. Do not instruct users to navigate there manually.
- **Permission acquisition is asymmetric:**
  - Microphone: runtime prompt via `AVAudioSession` / `AVCaptureDevice` — the OS shows the dialog.
  - Accessibility + Input Monitoring: cannot be granted programmatically — show the deep-link button and poll/observe for the grant.
- **Mid-session revocation must be detected.** If the user revokes a permission while the app is active, transition to error state immediately; do not crash or silently continue.
- Use `os.Logger`. No `print`. No force-unwrap. No `try!`.
- v0: Apple frameworks only. No third-party permission libraries.

## Roadmap P7 Done-When

- `PermissionManager` tracks `PermissionState` for all three kinds and publishes state changes.
- Onboarding flow presents each permission step with a clear WHY explanation and the appropriate action (runtime prompt for mic; deep-link button for accessibility + input monitoring).
- Deep-link `x-apple.systempreferences:com.apple.preference.security` opens System Settings to the correct pane.
- App does not proceed past onboarding until all three permissions are `granted`.
- Mid-session revocation of any permission is detected and transitions the app to error state with a recoverable prompt (re-open settings).
- Unit tests cover all `PermissionState` transitions for each `PermissionKind`.

## Verify at Implementation Time

**Do not recall the exact APIs for checking accessibility or input-monitoring permission state from training data.** The APIs for `AXIsProcessTrusted`, `IOHIDCheckAccess`, or equivalent macOS 26 replacements, and how to observe changes without polling, must be confirmed against current Apple documentation before coding.

Use `apple-docs-mcp` (if available) to look up `AXIsProcessTrusted` and input-monitoring privacy APIs. Otherwise, fetch from `https://developer.apple.com/documentation/applicationservices` and `https://developer.apple.com/documentation/iokit`. Tag every API claim `[verified]`, `[inferred]`, or `[unverified]`. Document the exact observation mechanism (notification, timer poll, or delegate) in `specs/verification-ledger.md` once confirmed.
