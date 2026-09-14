// SpeakCore/Storage/SettingsStore+Overlay.swift
//
// Recording-HUD accessors — moved out of SettingsStore.swift to hold the file
// under SwiftLint's 1000-line file_length cap (same pattern as +Reset and
// +InputDevice). Everything Settings → Overlay and both HUD views read lives
// here: HUD style, voice-animation style/color, border style/speed/count,
// panel size/position, element visibility, and border tint.

import Foundation

extension SettingsStore {

    // MARK: - HUD style (overlay visual style, H-UI)

    /// Visual style for the floating recording HUD. Default: `.classic`.
    public var hudStyle: HUDStyle {
        get {
            access(keyPath: \.hudStyle)
            let raw = defaults.string(forKey: Keys.hudStyle) ?? HUDStyle.classic.rawValue
            return HUDStyle(rawValue: raw) ?? .classic
        }
        set {
            withMutation(keyPath: \.hudStyle) {
                defaults.set(newValue.rawValue, forKey: Keys.hudStyle)
            }
        }
    }

    /// Left-zone voice animation for the recording HUD. Default: `.sonar`.
    public var voiceAnimationStyle: VoiceAnimationStyle {
        get {
            access(keyPath: \.voiceAnimationStyle)
            let raw = defaults.string(forKey: Keys.voiceAnimationStyle)
                ?? VoiceAnimationStyle.sonar.rawValue
            return VoiceAnimationStyle(rawValue: raw) ?? .sonar
        }
        set {
            withMutation(keyPath: \.voiceAnimationStyle) {
                defaults.set(newValue.rawValue, forKey: Keys.voiceAnimationStyle)
            }
        }
    }

    /// Color the left-zone voice animation draws with. Default: `.blue`.
    public var voiceAnimationColor: VoiceAnimationColor {
        get {
            access(keyPath: \.voiceAnimationColor)
            let raw = defaults.string(forKey: Keys.voiceAnimationColor)
                ?? VoiceAnimationColor.blue.rawValue
            return VoiceAnimationColor(rawValue: raw) ?? .blue
        }
        set {
            withMutation(keyPath: \.voiceAnimationColor) {
                defaults.set(newValue.rawValue, forKey: Keys.voiceAnimationColor)
            }
        }
    }

    // MARK: - Border animation settings

    /// Border animation style for the overlay panel. Default: `.none`.
    public var borderAnimationStyle: BorderAnimationStyle {
        get {
            access(keyPath: \.borderAnimationStyle)
            let raw = defaults.string(forKey: Keys.borderAnimationStyle) ?? BorderAnimationStyle.none.rawValue
            return BorderAnimationStyle(rawValue: raw) ?? .none
        }
        set {
            withMutation(keyPath: \.borderAnimationStyle) {
                defaults.set(newValue.rawValue, forKey: Keys.borderAnimationStyle)
            }
        }
    }

    /// Speed of the EdgeFlow border animation. Default: `.medium`.
    public var borderFlowSpeed: BorderFlowSpeed {
        get {
            access(keyPath: \.borderFlowSpeed)
            let raw = defaults.string(forKey: Keys.borderFlowSpeed) ?? BorderFlowSpeed.medium.rawValue
            return BorderFlowSpeed(rawValue: raw) ?? .medium
        }
        set {
            withMutation(keyPath: \.borderFlowSpeed) {
                defaults.set(newValue.rawValue, forKey: Keys.borderFlowSpeed)
            }
        }
    }

    /// Number of flowing light blobs in EdgeFlow animation (1...6). Default: `1`.
    public var borderFlowCount: Int {
        get {
            access(keyPath: \.borderFlowCount)
            let val = defaults.integer(forKey: Keys.borderFlowCount)
            return (1...6).contains(val) ? val : 1
        }
        set {
            withMutation(keyPath: \.borderFlowCount) {
                let clamped = min(max(newValue, 1), 6)
                defaults.set(clamped, forKey: Keys.borderFlowCount)
            }
        }
    }

    // MARK: - Overlay panel layout & elements (Settings → Overlay)

    /// Panel size preset for the recording HUD. Default: `.standard`.
    public var overlaySize: OverlayPanelSize {
        get {
            access(keyPath: \.overlaySize)
            let raw = defaults.string(forKey: Keys.overlaySize)
                ?? OverlayPanelSize.standard.rawValue
            return OverlayPanelSize(rawValue: raw) ?? .standard
        }
        set {
            withMutation(keyPath: \.overlaySize) {
                defaults.set(newValue.rawValue, forKey: Keys.overlaySize)
            }
        }
    }

    /// Vertical anchor for the recording HUD. Default: `.bottom`.
    public var overlayPosition: OverlayPanelPosition {
        get {
            access(keyPath: \.overlayPosition)
            let raw = defaults.string(forKey: Keys.overlayPosition)
                ?? OverlayPanelPosition.bottom.rawValue
            return OverlayPanelPosition(rawValue: raw) ?? .bottom
        }
        set {
            withMutation(keyPath: \.overlayPosition) {
                defaults.set(newValue.rawValue, forKey: Keys.overlayPosition)
            }
        }
    }

    /// Whether the HUD's right zone shows the running/result timer.
    /// Default: `true`. Off collapses the right zone — the text lane runs
    /// to the panel's right edge.
    public var overlayShowTimer: Bool {
        get {
            access(keyPath: \.overlayShowTimer)
            return defaults.bool(forKey: Keys.overlayShowTimer)
        }
        set {
            withMutation(keyPath: \.overlayShowTimer) {
                defaults.set(newValue, forKey: Keys.overlayShowTimer)
            }
        }
    }

    /// Whether the text lane shows the phase header (LISTENING / POLISHING …).
    /// Default: `true`.
    public var overlayShowPhaseHeader: Bool {
        get {
            access(keyPath: \.overlayShowPhaseHeader)
            return defaults.bool(forKey: Keys.overlayShowPhaseHeader)
        }
        set {
            withMutation(keyPath: \.overlayShowPhaseHeader) {
                defaults.set(newValue, forKey: Keys.overlayShowPhaseHeader)
            }
        }
    }

    /// Whether the voice animation dims when not actively listening.
    /// Default: `true`. Off = always full strength (still level-reactive).
    public var overlayIdleDim: Bool {
        get {
            access(keyPath: \.overlayIdleDim)
            return defaults.bool(forKey: Keys.overlayIdleDim)
        }
        set {
            withMutation(keyPath: \.overlayIdleDim) {
                defaults.set(newValue, forKey: Keys.overlayIdleDim)
            }
        }
    }

    /// Border color mode — `.adaptive` (state palettes) or a fixed hue.
    /// Default: `.adaptive`.
    public var overlayBorderTint: OverlayBorderTint {
        get {
            access(keyPath: \.overlayBorderTint)
            let raw = defaults.string(forKey: Keys.overlayBorderTint)
                ?? OverlayBorderTint.adaptive.rawValue
            return OverlayBorderTint(rawValue: raw) ?? .adaptive
        }
        set {
            withMutation(keyPath: \.overlayBorderTint) {
                defaults.set(newValue.rawValue, forKey: Keys.overlayBorderTint)
            }
        }
    }
}
