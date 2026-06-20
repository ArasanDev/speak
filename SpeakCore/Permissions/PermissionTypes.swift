// SpeakCore/Permissions/PermissionTypes.swift
//
// The permission state machine vocabulary (architecture.md §6, §7.2).
// `Equatable` added so callers can compare (e.g. `state == .granted`).

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
    case inputMonitoring
}
