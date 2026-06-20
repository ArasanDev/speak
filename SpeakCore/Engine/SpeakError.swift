// SpeakCore/Engine/SpeakError.swift
//
// The single error type for the dictation engine. Each case carries a
// user-facing `recoverySuggestion` so the UI never has to map errors to copy.
// Signatures are verbatim from `docs/architecture.md` §6.

public enum SpeakError: Error, Sendable {
    case microphoneDenied
    case accessibilityDenied
    case inputMonitoringDenied
    case transcriberUnavailable(String)
    case pasteboardBusy
    case llmCleanupFailed(String)
    case sessionCancelled
    case unknown(String)

    public var recoverySuggestion: String {
        switch self {
        case .microphoneDenied:      return "Open System Settings → Privacy → Microphone and enable speak."
        case .accessibilityDenied:   return "Open System Settings → Privacy → Accessibility and enable speak."
        case .inputMonitoringDenied: return "Open System Settings → Privacy → Input Monitoring and enable speak."
        case .transcriberUnavailable(let m): return "Speech engine unavailable: \(m). Try a fallback engine in Settings."
        case .pasteboardBusy:        return "Pasteboard busy. Retry in a moment."
        case .llmCleanupFailed(let m): return "LLM cleanup failed: \(m). Showing raw transcript."
        case .sessionCancelled:      return "Session cancelled."
        case .unknown(let m):        return "Unknown error: \(m)."
        }
    }
}
