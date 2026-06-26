// SpeakCore/Engine/SpeakError.swift
//
// The single error type for the dictation engine. Each case carries a
// user-facing `recoverySuggestion` so the UI never has to map errors to copy.
// Signatures are verbatim from `docs/architecture.md` §6.
//
// ADDITIVE CASE (surfaced, not papered over): `.microphoneMuted` is NOT in the
// §6 verbatim list. It was added for the hardware-mute privacy guarantee
// (SPEC §7.4 / product.md §8 #4): when capture is muted, `SpeakEngine.beginDictation`
// refuses to start a session and throws this — the bypass-proof enforcement point
// (no `CaptureSession`/audio is ever constructed). It is a *refusal*, not a fault:
// the app shell catches it specifically and stays idle rather than entering `.error`.
//
// ADDITIVE CASE (graceful degradation): `.pasteRequiresAccessibility` is thrown by
// `PasteboardWriter.insert(_:)` when `AXIsProcessTrusted()` returns false. The text
// has already been written to the clipboard (the clipboard floor runs first, always),
// so this is a *degraded delivery*, not a data-loss fault. The app shell catches it
// specifically: sets `permissionsNeeded = true` and leaves the icon `.idle` (text on
// clipboard), not `.error`. Per spec dictation-flow.md §5 + §6-D.
//
// ADDITIVE CASE (secure-field guard): `.pasteIntoSecureField` is thrown by
// `PasteboardWriter.insert(_:)` when the AX query detects that the frontmost
// focused element is a secure text field (subrole == kAXSecureTextFieldSubrole).
// Pasting dictated speech into a password field is a privacy/safety footgun and
// password fields often reject synthetic paste anyway. Outcome: deliberate refusal,
// NOT a data-loss fault — text is routed to the Scratchpad and the clipboard floor
// still runs. The app shell catches it specifically and stays `.idle`, identical to
// the `.pasteRequiresAccessibility` soft-catch pattern. `permissionsNeeded` is NOT
// set (no permission is missing; this is a safety decision, not a permission gap).

public enum SpeakError: Error, Sendable {
    case microphoneDenied
    case accessibilityDenied
    case transcriberUnavailable(String)
    case pasteboardBusy
    // [Engine-L4] Thrown by individual cleaner stubs (OllamaCleaner, MLXCleaner) and
    // FoundationModelsCleaner on genuine API error. CaptureSession.runCleanup() catches
    // all throws from clean() and converts them to raw-fallback — so this error never
    // propagates beyond runCleanup. Kept for protocol conformance and test verifiability.
    case llmCleanupFailed(String)
    case sessionCancelled
    case microphoneMuted
    /// AX not granted at paste time. Carries the `text` it was delivering so the app
    /// shell can route it to the Scratchpad (it is also already on the clipboard).
    case pasteRequiresAccessibility(text: String)
    /// The focused element is a secure text field. Dictated text must not be pasted
    /// into a credential field. Carries the `text` so the app shell can route it to
    /// the Scratchpad (it is also already on the clipboard from the clipboard floor).
    case pasteIntoSecureField(text: String)
    case unknown(String)

    public var recoverySuggestion: String {
        switch self {
        case .microphoneDenied:
            return "Open System Settings → Privacy → Microphone and enable speak."
        case .accessibilityDenied:
            return "Open System Settings → Privacy → Accessibility and enable speak."
        case .transcriberUnavailable(let detail):
            return "Speech engine unavailable: \(detail). Try a fallback engine in Settings."
        case .pasteboardBusy:
            return "Pasteboard busy. Retry in a moment."
        case .llmCleanupFailed(let detail):
            return "LLM cleanup failed: \(detail). Showing raw transcript."
        case .sessionCancelled:
            return "Session cancelled."
        case .microphoneMuted:
            return "Microphone is muted. Unmute speak to dictate."
        case .pasteRequiresAccessibility:
            return "Text copied to clipboard. Enable speak in System Settings → Privacy → Accessibility to paste automatically."
        case .pasteIntoSecureField:
            return "Won't paste into a password field — text saved to history."
        case .unknown(let detail):
            return "Unknown error: \(detail)."
        }
    }
}
