// SpeakCore/Storage/SettingsStore+TTS.swift
//
// TTS Voice Settings extension for SettingsStore. Extracted from SettingsStore.swift
// to satisfy SwiftLint's file_length rule (<1000 lines).

import AVFoundation
import Foundation

extension SettingsStore {

    // MARK: - TTS Voice Settings

    /// Selected TTS voice identifier (e.g. `com.apple.speech.synthesis.voice.samantha`). Empty string = system default.
    public var ttsVoiceIdentifier: String {
        get {
            access(keyPath: \.ttsVoiceIdentifier)
            return defaults.string(forKey: Keys.ttsVoiceIdentifier) ?? ""
        }
        set {
            withMutation(keyPath: \.ttsVoiceIdentifier) {
                defaults.set(newValue, forKey: Keys.ttsVoiceIdentifier)
            }
        }
    }

    /// TTS speech rate multiplier (0.1 to 1.0, default: `AVSpeechUtteranceDefaultSpeechRate` ~0.5).
    public var ttsSpeechRate: Float {
        get {
            access(keyPath: \.ttsSpeechRate)
            let val = defaults.float(forKey: Keys.ttsSpeechRate)
            return val > 0 ? val : AVSpeechUtteranceDefaultSpeechRate
        }
        set {
            withMutation(keyPath: \.ttsSpeechRate) {
                defaults.set(newValue, forKey: Keys.ttsSpeechRate)
            }
        }
    }

    /// TTS pitch multiplier (0.5 to 2.0, default: 1.0).
    public var ttsPitchMultiplier: Float {
        get {
            access(keyPath: \.ttsPitchMultiplier)
            let val = defaults.float(forKey: Keys.ttsPitchMultiplier)
            return val > 0 ? val : 1.0
        }
        set {
            withMutation(keyPath: \.ttsPitchMultiplier) {
                defaults.set(newValue, forKey: Keys.ttsPitchMultiplier)
            }
        }
    }

    /// TTS volume (0.0 to 1.0, default: 1.0).
    public var ttsVolume: Float {
        get {
            access(keyPath: \.ttsVolume)
            if defaults.object(forKey: Keys.ttsVolume) == nil {
                return 1.0
            }
            return defaults.float(forKey: Keys.ttsVolume)
        }
        set {
            withMutation(keyPath: \.ttsVolume) {
                defaults.set(newValue, forKey: Keys.ttsVolume)
            }
        }
    }
}
