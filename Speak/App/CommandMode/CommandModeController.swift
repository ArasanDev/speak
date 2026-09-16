// App/CommandMode/CommandModeController.swift
//
// Drives Command Mode (Wave D) from the Fn+Ctrl chord:
//   chord .begin → start capturing the spoken instruction (a transcriber-only session)
//   chord .end   → stop, take the instruction transcript, then run CommandModeService
//                  (read selection → on-device transform → replace selection via AX).
//
// The instruction capture reuses the engine's `AppleSpeechTranscriber` through
// `SpeakEngine.beginAuxiliarySession(includeCleanup: false)` — an engine-minted
// session so the mute / mic-permission / single-capture gates apply to command
// capture exactly as they do to dictation [fix: audit — C1 gate bypass].
// The transform + AX replace is the (unit-tested) `CommandModeService`.
//
// HONESTY BOUNDARY [deferred — human verification]: the live chord gesture, mic capture
// of the instruction, and AX read/replace in another app all require a real run with
// permissions. The pure pieces (chord detector, service orchestration, prompt) are tested.
//
// THREADING: @MainActor — owns the begin task reference and the run Task.

import AppKit
import Foundation
import SpeakCore

// MARK: - CommandModeController

@MainActor
final class CommandModeController {

    private let engine: SpeakEngine
    private let cleaner: (any LLMCleaning)?
    private let selection: any SelectionAccessing

    /// In-flight (or resolved) mint+start for the instruction session. Held as a
    /// `Task` — not the session itself — so `end()` can await a still-minting
    /// begin instead of racing it: a quick chord tap can fire `.end` before
    /// `beginAuxiliarySession` returns. `nil` outside a command gesture.
    private var beginTask: Task<CaptureSession, Error>?
    private var runTask: Task<Void, Never>?

    /// Max duration an instruction capture may hold the mic. A lost chord `.end`
    /// (tap death, dropped event) would otherwise leave an aux session listening
    /// indefinitely. Mirrors the sandbox's `maxRecordingSeconds` safety cap.
    /// [decision: 60 s — an instruction is a short utterance; far above any
    /// legitimate command, far below "mic open forever".]
    private static let maxInstructionSeconds: TimeInterval = 60

    init(engine: SpeakEngine,
         cleaner: (any LLMCleaning)?,
         selection: any SelectionAccessing = AccessibilitySelection()) {
        self.engine = engine
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
        // Debounce: a second chord-begin while a capture is minting/live is ignored.
        guard beginTask == nil else { return }
        SpeakLog.engine.info("CommandMode: chord begin — capturing instruction.")
        // Engine-minted aux session — the mute/TCC/single-capture gates run
        // inside `beginAuxiliarySession`; includeCleanup: false (we only want
        // the instruction text, not neat-writing or paste).
        let engine = self.engine
        let task = Task<CaptureSession, Error> {
            try await engine.beginAuxiliarySession(includeCleanup: false)
        }
        beginTask = task
        // If the mint fails and no `end()` ever arrives, clear the stale task so
        // the next chord press isn't permanently debounced away. If it succeeded,
        // leave `beginTask` in place — `end()` still needs `task.value`.
        Task { [weak self] in
            do {
                _ = try await task.value
            } catch {
                SpeakLog.engine.error(
                    "CommandMode: instruction capture failed to start — \(error.localizedDescription, privacy: .public)"
                )
                self?.clearFailedBegin(task)
            }
        }
        // Max-duration cap: if the chord's `.end` never arrives, abandon the
        // capture rather than hold the mic open. Self-cleaning — `end()` nils
        // `beginTask` first, so a fired cap after a normal end is a no-op.
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.maxInstructionSeconds))
            guard let self, self.beginTask == task else { return }
            guard let session = try? await task.value else { return }
            SpeakLog.engine.warning(
                "CommandMode: instruction capture hit \(Self.maxInstructionSeconds, privacy: .public)s cap — abandoning."
            )
            self.beginTask = nil
            await engine.cancelAuxiliarySession(session)
        }
    }

    /// End Command Mode: stop capture, take the instruction, and run the transform.
    func end() {
        guard let beginTask, let cleaner else {
            self.beginTask = nil
            return
        }
        self.beginTask = nil
        let engine = self.engine
        SpeakLog.engine.info("CommandMode: chord end — running transform.")
        runTask = Task { [weak self] in
            guard let self else { return }
            do {
                // Await the mint if it's still in flight — a quick tap can fire
                // .end before beginAuxiliarySession returns.
                let session = try await beginTask.value
                // Engine-side stop under the [C2] watchdog; also releases the
                // aux slot so the next dictation isn't refused.
                let result = try await engine.endAuxiliarySession(session)
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

    /// Clear `beginTask` only if it is still the failed task — a newer gesture's
    /// task must never be clobbered. (Task is Equatable; identity compare.)
    private func clearFailedBegin(_ task: Task<CaptureSession, Error>) {
        if beginTask == task {
            beginTask = nil
        }
    }
}
