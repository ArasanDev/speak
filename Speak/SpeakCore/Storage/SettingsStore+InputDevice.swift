// SpeakCore/Storage/SettingsStore+InputDevice.swift
//
// Mic-picker persistence — lives in an extension because SettingsStore.swift
// is at the SwiftLint 1000-line cap. Same `access`/`withMutation` observable
// pattern as the main file; keys extend the nested `Keys` enum.

import Foundation

extension SettingsStore.Keys {
    static let preferredInputDeviceUID  = "speak.settings.preferredInputDeviceUID"
    static let preferredInputDeviceName = "speak.settings.preferredInputDeviceName"
}

extension SettingsStore {

    // MARK: - Input device preference

    /// Hardware UID (`kAudioDevicePropertyDeviceUID`) of the mic the user
    /// pinned in Settings → Microphone. `nil`/"" = follow the system default.
    ///
    /// Resolution lives in `CoreAudioDeviceMonitor.resolvedInputDevice` —
    /// a stored UID whose device is unplugged transparently falls back to the
    /// system default (the "Jabra removed mid-day" case) rather than failing.
    public var preferredInputDeviceUID: String? {
        get {
            access(keyPath: \.preferredInputDeviceUID)
            let stored = defaults.string(forKey: Keys.preferredInputDeviceUID)
            return (stored?.isEmpty == false) ? stored : nil
        }
        set {
            withMutation(keyPath: \.preferredInputDeviceUID) {
                defaults.set(newValue ?? "", forKey: Keys.preferredInputDeviceUID)
            }
        }
    }

    /// Display name captured at pin time — UIDs are opaque ("AppleUSBAudioEngine:…"),
    /// so the Settings picker's "not connected" state needs the friendly name
    /// persisted alongside.
    public var preferredInputDeviceName: String? {
        get {
            access(keyPath: \.preferredInputDeviceName)
            let stored = defaults.string(forKey: Keys.preferredInputDeviceName)
            return (stored?.isEmpty == false) ? stored : nil
        }
        set {
            withMutation(keyPath: \.preferredInputDeviceName) {
                defaults.set(newValue ?? "", forKey: Keys.preferredInputDeviceName)
            }
        }
    }
}
