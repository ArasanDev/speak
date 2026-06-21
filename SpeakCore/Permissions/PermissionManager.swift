// SpeakCore/Permissions/PermissionManager.swift
//
// Tracks and requests the OS permissions speak needs (AGENTS.md §2.2):
// Microphone (P2), Accessibility + Input Monitoring (P5/P7). v0 P2 implements
// the microphone path fully; accessibility is queryable now (used at P5), and
// input monitoring is wired here at P7 using IOHIDCheckAccess.
//
// State/kind enums are verbatim from architecture.md §6.
//
// IOKit/HID note (P7): IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) is the
// documented way to query Input Monitoring ("listen event") authorization without
// prompting. Returns IOHIDAccessType: kIOHIDAccessTypeGranted / kIOHIDAccessTypeDenied
// / kIOHIDAccessTypeUnknown. [verified: swiftc -typecheck against macOS 26 SDK, 2026-06-21]
// Grant can only be done via System Settings; no programmatic grant API exists.

import AVFoundation
import ApplicationServices
import IOKit.hid
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
        case .inputMonitoring:
            // IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) queries the Input
            // Monitoring TCC permission without prompting. This is the approved
            // IOKit/HID way to read the "listen event" (keyboard monitoring) gate.
            // [verified: swiftc -typecheck against macOS 26 SDK, 2026-06-21]
            // Live correctness (grant → granted, deny → denied) is
            // [deferred — needs human verification with TCC prompt in real app].
            let access = IOHIDCheckAccess(kIOHIDRequestTypeListenEvent)
            switch access {
            case kIOHIDAccessTypeGranted:
                return .granted
            case kIOHIDAccessTypeUnknown:
                // Not yet determined — user has never been asked.
                return .notDetermined
            default:
                // kIOHIDAccessTypeDenied and any future values map to denied.
                return .denied
            }
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

    /// Requests Input Monitoring ("listen event") access. Registers the app in
    /// the Input Monitoring list and shows the system prompt when not yet granted
    /// — the counterpart to the silent `IOHIDCheckAccess` read in `status(_:)`.
    /// Returns whether access is already granted.
    /// [verified: swiftc -typecheck against macOS 26 SDK, 2026-06-21]
    @discardableResult
    public func requestInputMonitoring() -> Bool {
        let granted = IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
        SpeakLog.permissions.info("inputMonitoring prompt → granted=\(granted, privacy: .public)")
        return granted
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
