// App/CommandMode/AccessibilitySelection.swift
//
// Live `SelectionAccessing` implementation for Command Mode: reads and replaces the
// highlighted text in the frontmost application via the Accessibility API (AXUIElement).
//
// MOAT NOTE: this reads the *selection*, NOT the pasteboard — the "never read the
// pasteboard" rule (AGENTS.md §2.8) is about NSPasteboard, which this never touches.
// Reading the focused element's selected text via AX is a different, allowed mechanism
// and is how Command Mode edits in place without a copy/paste round-trip.
//
// HONESTY BOUNDARY: AX behavior depends on the target app's AX support + a granted
// Accessibility permission. This cannot be autonomously verified — it is
// [deferred — human verification]: grant Accessibility, select text in TextEdit/Slack,
// and confirm read + replace. The orchestration (CommandModeService) IS unit-tested.
//
// No force-casts (`as!`): CFTypeRef → AXUIElement uses a checked `as?` downcast, so a
// non-AXUIElement value yields nil rather than a crash (swiftlint force_cast is an error).

import Foundation
import ApplicationServices
import SpeakCore

// MARK: - AccessibilitySelection

struct AccessibilitySelection: SelectionAccessing {

    /// The focused UI element system-wide, or nil when none/not permitted.
    private func focusedElement() -> AXUIElement? {
        let systemWide = AXUIElementCreateSystemWide()
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            systemWide, kAXFocusedUIElementAttribute as CFString, &value
        )
        guard result == .success, let element = value, CFGetTypeID(element) == AXUIElementGetTypeID() else {
            return nil
        }
        // Type verified via CFGetTypeID above → unsafeDowncast is safe and avoids both a
        // force-cast (`as!`, a swiftlint error) and the "always succeeds" `as?` warning.
        return unsafeDowncast(element, to: AXUIElement.self)
    }

    func readSelectedText() throws -> String? {
        guard let element = focusedElement() else { return nil }
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            element, kAXSelectedTextAttribute as CFString, &value
        )
        guard result == .success else { return nil }
        return value as? String
    }

    func replaceSelectedText(with text: String) throws {
        guard let element = focusedElement() else {
            throw SpeakError.pasteRequiresAccessibility(text: text)
        }
        let result = AXUIElementSetAttributeValue(
            element, kAXSelectedTextAttribute as CFString, text as CFString
        )
        guard result == .success else {
            throw SpeakError.unknown("Command Mode: AX set selected text failed (AXError \(result.rawValue)).")
        }
    }
}
