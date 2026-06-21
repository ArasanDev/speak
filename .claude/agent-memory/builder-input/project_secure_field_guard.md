---
name: secure-field-paste-guard
description: Secure-field paste guard — AX subrole detection, injection pattern, UX, and fail-safe direction
metadata:
  type: project
---

Secure-field paste guard added to `PasteboardWriter.insert()` as step 3.

**Why:** Pasting dictated speech into a password field is a privacy/safety footgun; password fields also often reject synthetic paste. The guard proactively detects this and refuses with a clear message.

**How to apply:** When touching the paste pipeline (P6 seam), remember:
- The guard is in `PasteboardWriter.insert()` between AX-trust gate (step 2) and settle delay (step 4).
- The gate is injected as `isFocusedFieldSecure: @Sendable () -> Bool` (default = `focusedElementIsSecureField()`).
- Default implementation is in `SpeakCore/Paste/SecureFieldDetector.swift`.
- Fail-safe: any AX query failure → `false` → paste proceeds. Never block on ambiguity.
- Error type: `SpeakError.pasteIntoSecureField(text:)` — parallel to `.pasteRequiresAccessibility`.
- DictationController catches it: routes to Scratchpad + shows HUD error, stays `.idle`, does NOT set `permissionsNeeded`.

**AX signal verified:** `kAXSecureTextFieldSubrole == "AXSecureTextField"` [verified: HIServices/AXRoleConstants.h:408, local macOS 26 SDK].

**CF bridging pattern:** `CFGetTypeID(ref) == AXUIElementGetTypeID()` guard + `unsafeBitCast` — avoids `force_cast` lint error while being safe. Already used in `HistoryStore.swift`.

**StreamingTextInserting:** protocol-only in v0, not wired. Will need the same guard when H5 streaming paste lands.

**Gates (2026-06-22):** Build ✅ · 374 tests / 0 failures · Lint 0 serious · Moat 7/7.
