// SpeakCore/Paste/SecureFieldDetector.swift
//
// A small, testable function that queries the Accessibility API to detect
// whether the currently focused UI element in the frontmost application is
// a secure text field (password input). Used by `PasteboardWriter.insert(_:)`
// to refuse pasting dictated text into credential fields.
//
// AX signal: the focused element's subrole is `kAXSecureTextFieldSubrole`.
//   • Role: AXTextField  (all text inputs share this)
//   • Subrole: AXSecureTextField  (only secure/password fields)
//   [verified: HIServices/AXRoleConstants.h:408 — `kAXSecureTextFieldSubrole = CFSTR("AXSecureTextField")`]
//
// Query path (architecture §11 permits AX reads — only pasteboard reads are banned):
//   AXUIElementCreateSystemWide() → kAXFocusedUIElementAttribute → kAXSubroleAttribute
//
// Fail-safe: any query failure (permission denied, no focused element, attribute
// absent, unexpected CFTypeID, unexpected subrole format) returns `false` so the
// caller pastes normally. Blocking legitimate pastes on ambiguous query failures
// would be a worse footgun than the one we are guarding against.
//
// CF bridging: `AXUIElementCopyAttributeValue` returns `CFTypeRef?`. Swift's
// conditional downcast to CoreFoundation types (`as? AXUIElement`) always succeeds
// (emits a compiler warning), so we use `CFGetTypeID` + `unsafeBitCast` instead —
// the same pattern used in `HistoryStore.swift` for SQLite destructor bridging.
// `unsafeBitCast` is safe here because we verify the CFTypeID before casting.
//   [decision: unsafeBitCast over as! to satisfy force_cast swiftlint rule;
//              CFGetTypeID guard makes this a safe operation, not a blind cast]
//
// Threading: this function runs synchronously in the caller's Task context, which
// is an `async throws` context (`PasteboardWriter.insert`). The AX queries are
// fast (<1 ms) so no background dispatch is needed; blocking the caller for a
// single AX round-trip is acceptable and consistent with `AXIsProcessTrusted()`.
//
// This is NOT a class/struct — it is a module-level free function so it can be
// extracted as a pure closure and injected into `PasteboardWriter` for testing
// without needing to stub a whole type.

import ApplicationServices
import os

// MARK: - Public detection function

/// Returns `true` when the currently focused UI element is a secure text field.
///
/// Uses the Accessibility API to inspect the focus element's subrole.
/// Reads an AX attribute — NOT the pasteboard — which is explicitly permitted
/// (the hard rule is "never read the pasteboard"; AX reads are fine).
///
/// **Fail-safe**: any query failure → returns `false` (permit paste).
/// This ensures a broken AX stack or a focused element with no subrole never
/// silently swallows dictated text.
///
/// - Returns: `true` iff the subrole is `kAXSecureTextFieldSubrole`
///   (`"AXSecureTextField"`). `false` on any error, absent attribute, or
///   non-secure element.
public func focusedElementIsSecureField() -> Bool {
    let log = SpeakLog.paste

    // Build a system-wide AX element to query the current input focus.
    let systemWide = AXUIElementCreateSystemWide()

    // Query the globally focused UI element.
    var focusedRef: CFTypeRef?
    let focusResult = AXUIElementCopyAttributeValue(
        systemWide,
        kAXFocusedUIElementAttribute as CFString,
        &focusedRef
    )
    guard focusResult == .success, let focusedRef else {
        // AX not trusted, no focused element, or query failed → fail-safe: not secure.
        log.debug(
            // swiftlint:disable:next line_length
            "SecureFieldDetector: kAXFocusedUIElementAttribute failed (\(focusResult.rawValue, privacy: .public)) — treating as not secure"
        )
        return false
    }

    // Verify the returned CFTypeRef is actually an AXUIElement before bridging.
    // Using CFGetTypeID avoids a force-cast (lint rule) while being semantically
    // safe. `unsafeBitCast` is correct here: both types are opaque CF pointers
    // with the same memory layout; the CFTypeID guard makes this a proven cast.
    guard CFGetTypeID(focusedRef) == AXUIElementGetTypeID() else {
        log.debug(
            "SecureFieldDetector: focused attribute is not an AXUIElement (CFTypeID mismatch) — treating as not secure"
        )
        return false
    }
    // Safe: CFTypeID verified above.
    // [decision: unsafeBitCast over as! to satisfy force_cast swiftlint rule]
    let focused: AXUIElement = unsafeBitCast(focusedRef, to: AXUIElement.self)

    // Query the subrole attribute of the focused element.
    var subroleRef: CFTypeRef?
    let subroleResult = AXUIElementCopyAttributeValue(
        focused,
        kAXSubroleAttribute as CFString,
        &subroleRef
    )
    guard subroleResult == .success, let subroleRef else {
        // Element has no subrole (e.g. plain text field, button) → not secure.
        log.debug(
            // swiftlint:disable:next line_length
            "SecureFieldDetector: kAXSubroleAttribute absent or failed (\(subroleResult.rawValue, privacy: .public)) — treating as not secure"
        )
        return false
    }

    // The subrole value is a CFString; bridge to Swift String via as?.
    // CFString → String is a toll-free-bridged conditional downcast that succeeds
    // reliably (the AX API always returns CFString for string attributes).
    guard let subrole = subroleRef as? String else {
        log.debug(
            "SecureFieldDetector: subrole value is not a String — treating as not secure"
        )
        return false
    }

    // kAXSecureTextFieldSubrole == "AXSecureTextField"
    // [verified: HIServices/AXRoleConstants.h:408]
    let isSecure = subrole == (kAXSecureTextFieldSubrole as String)
    if isSecure {
        log.info(
            "SecureFieldDetector: focused element subrole='\(subrole, privacy: .public)' — paste refused"
        )
    }
    return isSecure
}
