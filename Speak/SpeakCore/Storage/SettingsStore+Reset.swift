// SpeakCore/Storage/SettingsStore+Reset.swift
//
// "Reset All Settings" — moved out of SettingsStore.swift to hold the file under
// SwiftLint's 1000-line file_length cap (same pattern as +InputDevice). The
// helpers are file-private to this extension; `access`/`withMutation` from the
// @Observable macro and `defaults` are internal, so they resolve here.

import AVFoundation
import Foundation

extension SettingsStore {

    // MARK: - Reset to defaults

    /// Resets all user settings to their default values. All preferences are wiped;
    /// history is NOT cleared (separate operation). [decision: reset != clear history]
    public func resetToDefaults() {
        resetDictationDefaults()
        resetVocabularyDefaults()
        resetAppearanceDefaults()
        resetInteractionDefaults()
        resetVoiceOutDefaults()

        SpeakLog.storage.info("SettingsStore reset to defaults")
    }

    private func resetDictationDefaults() {
        access(keyPath: \.cleanupEnabled)
        access(keyPath: \.cleanupEngine)
        access(keyPath: \.sttEngine)
        access(keyPath: \.language)
        access(keyPath: \.pasteMode)
        access(keyPath: \.triggerMode)
        access(keyPath: \.cleanupStyle)
        access(keyPath: \.cleanupLevel)
        access(keyPath: \.streamingRawTextEnabled)
        access(keyPath: \.streamingMode)
        access(keyPath: \.agentPrefixStyle)
        access(keyPath: \.agentPrefixIncludeState)

        withMutation(keyPath: \.cleanupEnabled) {
            defaults.set(true, forKey: Keys.cleanupEnabled)
        }
        withMutation(keyPath: \.sttEngine) {
            defaults.removeObject(forKey: Keys.sttEngine)
        }
        // Restores the default local cleanup engine (.foundationModels).
        withMutation(keyPath: \.cleanupEngine) {
            defaults.removeObject(forKey: Keys.cleanupEngine)
        }
        withMutation(keyPath: \.language) {
            defaults.set("en-US", forKey: Keys.language)
        }
        withMutation(keyPath: \.pasteMode) {
            defaults.set(PasteMode.cmdV.rawValue, forKey: Keys.pasteMode)
        }
        withMutation(keyPath: \.triggerMode) {
            defaults.removeObject(forKey: Keys.triggerMode)
        }
        withMutation(keyPath: \.cleanupStyle) {
            defaults.set(CleanupStyle.default.rawValue, forKey: Keys.cleanupStyle)
        }
        withMutation(keyPath: \.cleanupLevel) {
            defaults.set(CleanupLevel.medium.rawValue, forKey: Keys.cleanupLevel)
        }
        withMutation(keyPath: \.streamingRawTextEnabled) {
            defaults.set(true, forKey: Keys.streamingRawTextEnabled)
        }
        withMutation(keyPath: \.streamingMode) {
            defaults.set(StreamingMode.keystrokeInjection.rawValue, forKey: Keys.streamingMode)
        }
        withMutation(keyPath: \.agentPrefixStyle) {
            defaults.set(AgentPrefixStyle.speakSTT.rawValue, forKey: Keys.agentPrefixStyle)
        }
        withMutation(keyPath: \.agentPrefixIncludeState) {
            defaults.set(false, forKey: Keys.agentPrefixIncludeState)
        }
        // Pinned mic → back to following the system default.
        withMutation(keyPath: \.preferredInputDeviceUID) {
            defaults.removeObject(forKey: Keys.preferredInputDeviceUID)
            defaults.removeObject(forKey: Keys.preferredInputDeviceName)
        }
    }

    private func resetVocabularyDefaults() {
        access(keyPath: \.customVocabulary)
        access(keyPath: \.acousticCorrections)

        withMutation(keyPath: \.customVocabulary) {
            defaults.removeObject(forKey: Keys.customVocabulary)
        }
        withMutation(keyPath: \.acousticCorrections) {
            defaults.removeObject(forKey: Keys.acousticCorrections)
        }
    }

    private func resetAppearanceDefaults() {
        access(keyPath: \.appTheme)
        access(keyPath: \.themeID)
        access(keyPath: \.perAppContextEnabled)
        access(keyPath: \.hudStyle)
        access(keyPath: \.borderAnimationStyle)
        access(keyPath: \.borderFlowSpeed)
        access(keyPath: \.borderFlowCount)

        withMutation(keyPath: \.appTheme) {
            defaults.set(AppTheme.system.rawValue, forKey: Keys.appTheme)
        }
        // Theme selection → the built-in `speak` theme. Custom theme
        // definitions (`customThemesJSON`) are user-authored content — kept,
        // like dictation history and snippets.
        withMutation(keyPath: \.themeID) {
            defaults.set("speak", forKey: Keys.themeID)
        }
        withMutation(keyPath: \.perAppContextEnabled) {
            defaults.set(true, forKey: Keys.perAppContextEnabled)
        }
        withMutation(keyPath: \.hudStyle) {
            defaults.set(HUDStyle.classic.rawValue, forKey: Keys.hudStyle)
        }
        withMutation(keyPath: \.borderAnimationStyle) {
            defaults.set(BorderAnimationStyle.none.rawValue, forKey: Keys.borderAnimationStyle)
        }
        withMutation(keyPath: \.borderFlowSpeed) {
            defaults.set(BorderFlowSpeed.medium.rawValue, forKey: Keys.borderFlowSpeed)
        }
        withMutation(keyPath: \.borderFlowCount) {
            defaults.set(1, forKey: Keys.borderFlowCount)
        }
    }

    private func resetInteractionDefaults() {
        access(keyPath: \.voiceActionsEnabled)
        access(keyPath: \.voiceActionsPrefix)
        access(keyPath: \.readbackEnabled)
        access(keyPath: \.extraBindings)
        access(keyPath: \.revealTextWhileProcessing)
        access(keyPath: \.dictationFeedbackSounds)
        access(keyPath: \.dictationFeedbackHaptics)

        withMutation(keyPath: \.voiceActionsEnabled) {
            defaults.set(false, forKey: Keys.voiceActionsEnabled)
        }
        withMutation(keyPath: \.voiceActionsPrefix) {
            defaults.set("hey speak", forKey: Keys.voiceActionsPrefix)
        }
        withMutation(keyPath: \.readbackEnabled) {
            defaults.set(true, forKey: Keys.readbackEnabled)
        }
        // Reset extra hotkey bindings back to default empty.
        withMutation(keyPath: \.extraBindings) {
            defaults.removeObject(forKey: Keys.extraBindings)
        }
        // Reset revealTextWhileProcessing back to default (true).
        withMutation(keyPath: \.revealTextWhileProcessing) {
            defaults.set(true, forKey: Keys.revealTextWhileProcessing)
        }
        withMutation(keyPath: \.dictationFeedbackSounds) {
            defaults.set(true, forKey: Keys.dictationFeedbackSounds)
        }
        withMutation(keyPath: \.dictationFeedbackHaptics) {
            defaults.set(false, forKey: Keys.dictationFeedbackHaptics)
        }
    }

    private func resetVoiceOutDefaults() {
        withMutation(keyPath: \.ttsVoiceIdentifier) {
            defaults.set("", forKey: Keys.ttsVoiceIdentifier)
        }
        withMutation(keyPath: \.ttsSpeechRate) {
            defaults.set(AVSpeechUtteranceDefaultSpeechRate, forKey: Keys.ttsSpeechRate)
        }
        withMutation(keyPath: \.ttsPitchMultiplier) {
            defaults.set(Float(1.0), forKey: Keys.ttsPitchMultiplier)
        }
        withMutation(keyPath: \.ttsVolume) {
            defaults.set(Float(1.0), forKey: Keys.ttsVolume)
        }
    }
}
