// SpeakCore/Permissions/PermissionTypes.swift
//
// The permission state machine vocabulary (architecture.md §6, §7.2).
// `Equatable` added so callers can compare (e.g. `state == .granted`).
//
// v0 requires exactly two OS permissions: Microphone and Accessibility.
// Input Monitoring was removed — the CGEventTap uses .defaultTap and is
// gated on Accessibility alone (verified: HotkeyMonitor.swift §84–86).

public enum PermissionState: Sendable, Equatable {
    case notDetermined
    case requesting
    case granted
    case denied
    case restricted
}

public enum PermissionKind: Sendable, CaseIterable {
    case microphone
    case accessibility
}

// MARK: - PermissionManaging

/// The minimal interface that `OnboardingViewModel` (App target) requires from
/// the permission layer. Expressed as a protocol so the onboarding flow is
/// testable with a stub — the real `PermissionManager` conforms automatically
/// (all methods already exist). No new behaviour is added; this is a seam only.
///
/// `@MainActor` matches `PermissionManager`, which is itself `@MainActor`.
@MainActor
public protocol PermissionManaging: AnyObject {
    /// Returns the current permission state for `kind` without prompting.
    func status(_ kind: PermissionKind) -> PermissionState

    /// Requests microphone access (async; may show a system dialog on first call).
    @discardableResult
    func requestMicrophone() async -> PermissionState

    /// Registers the app in the Accessibility list and shows the TCC dialog.
    /// Returns whether the process is already trusted.
    @discardableResult
    func requestAccessibility() -> Bool
}
