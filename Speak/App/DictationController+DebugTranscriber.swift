// App/DictationController+DebugTranscriber.swift
//
// Transcriber resolution seam for the `simulate-dictation-scripted` debug target.
// Extracted to its own file to keep DictationController.swift under the
// file-length gate.

import Foundation
import SpeakCore

extension DictationController {

    /// Picks the real STT engine, unless a debug launch argument requests the
    /// scripted fake — in which case the controller's *own* production `SpeakEngine`
    /// is built with `ScriptedTranscriber` instead. This is what lets
    /// `--debug-open simulate-dictation-scripted:<text>` drive the actual overlay,
    /// menubar icon, and caret overlay (all of which observe `self.engine`, not a
    /// throwaway one) — `SpeakEngine.transcriber` is fixed at construction, so the
    /// swap must happen here, before `engine` exists, not later in a dispatcher.
    /// `#if DEBUG`-gated so zero bytes/behavior reach the release binary.
    static func resolveTranscriber(for settings: SettingsStore) -> any Transcribing {
        #if DEBUG
        if let text = DebugLaunchDispatcher.scriptedDictationText(in: CommandLine.arguments) {
            return ScriptedTranscriber(revealingWordsIn: text)
        }
        #endif
        return defaultTranscriber(for: settings)
    }
}
