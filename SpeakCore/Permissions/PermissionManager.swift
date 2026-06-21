// SpeakCore/Permissions/PermissionManager.swift
//
// Tracks and requests the OS permissions speak needs (AGENTS.md §2.2):
// Microphone (P2) and Accessibility (P5/P7). v0 requires exactly these two.
//
// State/kind enums are verbatim from architecture.md §6.
//
// Input Monitoring was removed: the CGEventTap uses .defaultTap and is gated
// on Accessibility alone — IOHIDCheckAccess/IOHIDRequestAccess are no longer
// called. [verified: HotkeyMonitor.swift §84–86, 2026-06-22]

import AVFoundation
import ApplicationServices
import os

@MainActor
public final class PermissionManager: PermissionManaging {

    public init() {}

    /// Current authorization state for a permission, without prompting.
    public func status(_ kind: PermissionKind) -> PermissionState {
        switch kind {
        case .microphone:
            return Self.map(AVCaptureDevice.authorizationStatus(for: .audio))
        case .accessibility:
            return AXIsProcessTrusted() ? .granted : .denied
        }
    }

    /// Requests microphone access, triggering the system prompt on first run.
    /// Returns the resulting state. Safe to call repeatedly (no re-prompt once set).
    @discardableResult
    public func requestMicrophone() async -> PermissionState {
        let current = AVCaptureDevice.authorizationStatus(for: .audio)
        guard current == .notDetermined else { return Self.map(current) }
        let granted = await AVCaptureDevice.requestAccess(for: .audio)
        let state: PermissionState = granted ? .granted : .denied
        SpeakLog.permissions.info("microphone request → \(String(describing: state), privacy: .public)")
        return state
    }

    /// Requests Accessibility access. Unlike `status(.accessibility)` (a silent
    /// check), this **registers the app in the Accessibility list** and shows the
    /// system prompt when not yet trusted — the only way `speak` appears in
    /// System Settings → Privacy → Accessibility for the user to toggle on.
    /// Returns whether the process is already trusted.
    /// [verified: swiftc -typecheck against macOS 26 SDK, 2026-06-21]
    @discardableResult
    public func requestAccessibility() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        let trusted = AXIsProcessTrustedWithOptions(options)
        SpeakLog.permissions.info("accessibility prompt → trusted=\(trusted, privacy: .public)")
        return trusted
    }

    private static func map(_ status: AVAuthorizationStatus) -> PermissionState {
        switch status {
        case .notDetermined: return .notDetermined
        case .authorized:    return .granted
        case .denied:        return .denied
        case .restricted:    return .restricted
        @unknown default:    return .denied
        }
    }
}
