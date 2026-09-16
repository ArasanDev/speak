// App/Settings/LaunchAtLoginManager.swift
//
// Native macOS Launch at Login manager using ServiceManagement.SMAppService.
// Zero third-party dependencies, Apple frameworks only.

import Foundation
import os
import ServiceManagement
import SpeakCore

@Observable
@MainActor
public final class LaunchAtLoginManager {
    public static let shared = LaunchAtLoginManager()

    public private(set) var isEnabled: Bool = false

    private init() {
        refresh()
    }

    public func refresh() {
        isEnabled = (SMAppService.mainApp.status == .enabled)
    }

    public func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else {
                if SMAppService.mainApp.status == .enabled {
                    try SMAppService.mainApp.unregister()
                }
            }
        } catch {
            SpeakLog.app.error("LaunchAtLoginManager error toggling state: \(error.localizedDescription, privacy: .public)")
        }
        refresh()
    }
}
