// SpeakCore/Permissions/PermissionManager.swift
//
// Tracks and requests the OS permissions speak needs (AGENTS.md §2.2):
// Microphone (P2), Accessibility + Input Monitoring (P5/P7). v0 P2 implements
// the microphone path fully; accessibility is queryable now (used at P5), and
// input monitoring is wired at P5 when CGEventTap actually needs it.
//
// State/kind enums are verbatim from architecture.md §6.

import AVFoundation
import ApplicationServices
import os

@MainActor
public final class PermissionManager {

    public init() {}

    /// Current authorization state for a permission, without prompting.
    public func status(_ kind: PermissionKind) -> PermissionState {
        switch kind {
        case .microphone:
            return Self.map(AVCaptureDevice.authorizationStatus(for: .audio))
        case .accessibility:
            return AXIsProcessTrusted() ? .granted : .denied
        case .inputMonitoring:
            // Implemented at P5 (CGEventTap requires it). Reported as not-yet-known
            // until then so onboarding (P7) doesn't claim a false state.
            return .notDetermined
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
