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

public enum SpeakError: Error, Sendable {
    case microphoneDenied
    case accessibilityDenied
    case inputMonitoringDenied
    case transcriberUnavailable(String)
    case pasteboardBusy
    case llmCleanupFailed(String)
    case sessionCancelled
    case microphoneMuted
    case unknown(String)

    public var recoverySuggestion: String {
        switch self {
        case .microphoneDenied:
            return "Open System Settings → Privacy → Microphone and enable speak."
        case .accessibilityDenied:
            return "Open System Settings → Privacy → Accessibility and enable speak."
        case .inputMonitoringDenied:
            return "Open System Settings → Privacy → Input Monitoring and enable speak."
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
        case .unknown(let detail):
            return "Unknown error: \(detail)."
        }
    }
}
