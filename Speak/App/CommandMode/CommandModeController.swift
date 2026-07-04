// App/CommandMode/CommandModeController.swift
//
// Drives Command Mode (Wave D) from the Fn+Ctrl chord:
//   chord .begin → start capturing the spoken instruction (a transcriber-only session)
//   chord .end   → stop, take the instruction transcript, then run CommandModeService
//                  (read selection → on-device transform → replace selection via AX).
//
// The instruction capture reuses the same `AppleSpeechTranscriber` + `CaptureSession`
// as normal dictation (no cleaner, no inserter — we only want the instruction text).
// The transform + AX replace is the (unit-tested) `CommandModeService`.
//
// HONESTY BOUNDARY [deferred — human verification]: the live chord gesture, mic capture
// of the instruction, and AX read/replace in another app all require a real run with
// permissions. The pure pieces (chord detector, service orchestration, prompt) are tested.
//
// THREADING: @MainActor — owns the session reference and the run Task.

import AppKit
import Foundation
import SpeakCore

// MARK: - CommandModeController

@MainActor
final class CommandModeController {

    private let settings: SettingsStore
    private let cleaner: (any LLMCleaning)?
    private let selection: any SelectionAccessing

    /// The in-flight instruction-capture session (nil when not in a command gesture).
    private var instructionSession: CaptureSession?
    private var runTask: Task<Void, Never>?

    init(settings: SettingsStore,
         cleaner: (any LLMCleaning)?,
         selection: any SelectionAccessing = AccessibilitySelection()) {
        self.settings = settings
        self.cleaner = cleaner
        self.selection = selection
    }

    // MARK: - Chord handling

    /// Begin Command Mode: start capturing the spoken instruction.
    func begin() {
        guard cleaner != nil else {
            SpeakLog.engine.info("CommandMode: no cleaner available — ignoring chord.")
            return
        }
        // A transcriber-only session: we want the instruction text, not cleanup or paste.
        let transcriber = defaultTranscriber(for: settings)
        let session = CaptureSession(
            transcriber: transcriber,
            cleaner: nil,
            inserter: nil,
            locale: settings.language
        )
        instructionSession = session
        SpeakLog.engine.info("CommandMode: chord begin — capturing instruction.")
        Task {
            do { try await session.start() } catch { SpeakLog.engine.error("CommandMode: instruction capture failed to start — \(error.localizedDescription, privacy: .public)") }
        }
    }

    /// End Command Mode: stop capture, take the instruction, and run the transform.
    func end() {
        guard let session = instructionSession, let cleaner else {
            instructionSession = nil
            return
        }
        instructionSession = nil
        SpeakLog.engine.info("CommandMode: chord end — running transform.")
        runTask = Task { [weak self] in
            guard let self else { return }
            do {
                let result = try await session.stop()
                let instruction = result.rawText.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !instruction.isEmpty else {
                    SpeakLog.engine.info("CommandMode: empty instruction — no-op.")
                    return
                }
                let service = CommandModeService(selection: self.selection, cleaner: cleaner)
                let outcome = try await service.run(instruction: instruction)
                SpeakLog.engine.info("CommandMode: \(String(describing: outcome), privacy: .public)")
            } catch {
                SpeakLog.engine.error("CommandMode: transform failed — \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}
