// SpeakCore/Input/CaretLocator.swift
//
// Best-effort query for the on-screen position of the text insertion cursor
// in the frontmost application using the Accessibility API.
//
// Returns the top-left corner of the cursor/selection bounds in Quartz
// screen coordinates (origin at top-left of primary display). Note: AppKit
// uses a flipped y-axis (origin bottom-left); P2.2 must flip y when
// converting to AppKit window coordinates.
//
// Fallback chain:
//   1. kAXSelectedTextRangeAttribute → kAXBoundsForRangeParameterizedAttribute
//      Most reliable for text fields (NSTextView, UIKit bridges, some Electron).
//   2. kAXInsertionPointLineNumberAttribute → kAXRangeForLineParameterizedAttribute
//      → kAXBoundsForRangeParameterizedAttribute
//      [decision P2.1: using RangeForLine→BoundsForRange chain; kAXBoundsForLine-
//      NumberParameterizedAttribute is not a standard AX constant. This path returns
//      the start-of-line bounds as a column approximation — sufficient for overlay
//      anchoring, but not pixel-exact column position.]
//   3. nil — expected for browsers, Electron, games, terminal emulators.
//
// CF bridging: AXValue is a CFTypeRef subtype. Swift's `as?` conditional cast
// always succeeds for CF types (emits a compiler warning), so we use
// CFGetTypeID + unsafeBitCast — the same pattern as SecureFieldDetector.swift.
// [verified: AXValueType cases .cgRect/.cfRange/.cgPoint, kAXSelected-
//  TextRangeAttribute, kAXBoundsForRangeParameterizedAttribute,
//  kAXInsertionPointLineNumberAttribute, kAXRangeForLineParameterizedAttribute
//  all typecheck against macOS 26 SDK, 2026-06-30]

import ApplicationServices
import os

// MARK: - CaretLocator

/// Best-effort query for the on-screen position of the text insertion cursor
/// in a given AX-accessible process.
///
/// Returns nil when the focused element doesn't expose cursor bounds (e.g. most
/// web inputs in sandboxed browsers, Electron apps, terminal emulators, games).
/// The caller must gracefully degrade — never crash on nil.
public enum CaretLocator {

    /// Query the frontmost app for its text cursor screen position.
    ///
    /// Returns the top-left origin of the cursor bounds in Quartz screen
    /// coordinates (top-left origin). Callers anchoring to AppKit geometry
    /// must flip the y-axis.
    ///
    /// Must be called from the main thread. AX APIs are not thread-safe.
    ///
    /// - Parameter pid: The frontmost application's process ID.
    /// - Returns: The cursor's screen origin in global Quartz coordinates,
    ///   or nil when unavailable.
    public static func caretScreenPosition(pid: pid_t) -> CGPoint? {
        guard pid > 0 else { return nil }

        let appElement = AXUIElementCreateApplication(pid)

        var focusedRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            appElement,
            kAXFocusedUIElementAttribute as CFString,
            &focusedRef
        ) == .success, let focusedRef else { return nil }

        guard CFGetTypeID(focusedRef) == AXUIElementGetTypeID() else { return nil }
        // Safe: CFTypeID verified above.
        // [decision P2.1: unsafeBitCast over as! to satisfy force_cast swiftlint rule]
        let focused: AXUIElement = unsafeBitCast(focusedRef, to: AXUIElement.self)

        if let point = boundsViaSelectedRange(focused) {
            SpeakLog.input.debug(
                "CaretLocator: found caret at (\(point.x, privacy: .public), \(point.y, privacy: .public)) via selectedTextRange"
            )
            return point
        }

        if let point = boundsViaLineNumber(focused) {
            SpeakLog.input.debug(
                "CaretLocator: found caret at (\(point.x, privacy: .public), \(point.y, privacy: .public)) via insertionPointLineNumber"
            )
            return point
        }

        return nil
    }

    // MARK: - Private query paths

    private static func boundsViaSelectedRange(_ element: AXUIElement) -> CGPoint? {
        var rangeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            kAXSelectedTextRangeAttribute as CFString,
            &rangeRef
        ) == .success, let rangeRef else { return nil }

        guard var cfRange = self.cfRange(from: rangeRef) else { return nil }
        guard let rangeValue = AXValueCreate(.cfRange, &cfRange) else { return nil }

        var boundsRef: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(
            element,
            kAXBoundsForRangeParameterizedAttribute as CFString,
            rangeValue,
            &boundsRef
        ) == .success, let boundsRef else { return nil }

        return rect(from: boundsRef).map { CGPoint(x: $0.minX, y: $0.minY) }
    }

    private static func boundsViaLineNumber(_ element: AXUIElement) -> CGPoint? {
        var lineRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            kAXInsertionPointLineNumberAttribute as CFString,
            &lineRef
        ) == .success, let lineRef else { return nil }

        // lineRef is a CFNumber (line index); pass directly to RangeForLine.
        var rangeRef: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(
            element,
            kAXRangeForLineParameterizedAttribute as CFString,
            lineRef,
            &rangeRef
        ) == .success, let rangeRef else { return nil }

        guard var lineRange = cfRange(from: rangeRef) else { return nil }

        // Use start of line with length 0 to get column-start bounds.
        // [decision P2.1: length=0 approximates caret position at line start;
        //  exact column is unavailable without the character index.]
        lineRange = CFRange(location: lineRange.location, length: 0)
        guard let rangeValue = AXValueCreate(.cfRange, &lineRange) else { return nil }

        var boundsRef: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(
            element,
            kAXBoundsForRangeParameterizedAttribute as CFString,
            rangeValue,
            &boundsRef
        ) == .success, let boundsRef else { return nil }

        return rect(from: boundsRef).map { CGPoint(x: $0.minX, y: $0.minY) }
    }

    // MARK: - AXValue extraction helpers (internal for testability)

    /// Unpacks a CGRect from an AXValue CFTypeRef. Returns nil on type mismatch.
    static func rect(from axValue: AnyObject) -> CGRect? {
        guard CFGetTypeID(axValue) == AXValueGetTypeID() else { return nil }
        let axVal: AXValue = unsafeBitCast(axValue, to: AXValue.self)
        var r = CGRect.zero
        guard AXValueGetValue(axVal, .cgRect, &r) else { return nil }
        return r
    }

    /// Unpacks a CGPoint from an AXValue CFTypeRef. Returns nil on type mismatch.
    static func point(from axValue: AnyObject) -> CGPoint? {
        guard CFGetTypeID(axValue) == AXValueGetTypeID() else { return nil }
        let axVal: AXValue = unsafeBitCast(axValue, to: AXValue.self)
        var p = CGPoint.zero
        guard AXValueGetValue(axVal, .cgPoint, &p) else { return nil }
        return p
    }

    /// Unpacks a CFRange from an AXValue CFTypeRef. Returns nil on type mismatch.
    static func cfRange(from axValue: AnyObject) -> CFRange? {
        guard CFGetTypeID(axValue) == AXValueGetTypeID() else { return nil }
        let axVal: AXValue = unsafeBitCast(axValue, to: AXValue.self)
        var range = CFRange(location: 0, length: 0)
        guard AXValueGetValue(axVal, .cfRange, &range) else { return nil }
        return range
    }
}
