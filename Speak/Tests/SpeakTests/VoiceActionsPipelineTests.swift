// SpeakTests/VoiceActionsPipelineTests.swift
//
// H-1 (specs/horizon-voice-os.md, Pillar 1) — pipeline-level tests for the LIVE
// wiring of Voice Actions into `CaptureSession.stop()`. The pure router/coordinator
// units are covered by VoiceActionsRoutingTests / VoiceActionsCoordinatorTests; this
// file verifies the SEAM: that a routed transcript actually suppresses or preserves
// the dictation paste through the real `stop()` delivery path.
//
// Contract under test (task brief):
//   • Feature OFF (nil handler) → delivery is byte-identical to pre-H-1 (paste runs).
//   • Feature ON, action route → executor runs, paste is SUPPRESSED.
//   • Feature ON, command route → CommandModeService runs, paste is SUPPRESSED.
//   • Feature ON, ambiguous/error → degrades to dictation, the ORIGINAL transcript
//     is pasted (never lose the user's words).
//
// Drives `CaptureSession` directly (no `beginDictation`) so no mic authorization is
// needed — same pattern as CaptureSessionTests. The integration tests assemble the
// SAME handler closure `SpeakEngine.newSession()` builds (real `VoiceActionsCoordinator`
// + `PrefixActionRouter`), so the routing logic is exercised end-to-end, not stubbed.

@testable import SpeakCore
import XCTest

final class VoiceActionsPipelineTests: XCTestCase {

    // MARK: - Mocks

    /// Scripted STT: yields each chunk then finishes on its own (no stop-gating),
    /// so `stop()` proceeds deterministically. Mirrors CaptureSessionTests.MockTranscriber.
    private final class ScriptedTranscriber: Transcribing, @unchecked Sendable {
        let id = "scripted-stt"
        private let script: [TranscriptChunk]
        init(finalText: String) {
            self.script = [TranscriptChunk(text: finalText, isFinal: true, timestamp: Date())]
        }
        func startStream(locale: Locale) -> AsyncThrowingStream<TranscriptChunk, Error> {
            let script = self.script
            return AsyncThrowingStream { continuation in
                Task {
                    for chunk in script {
                        continuation.yield(chunk)
                        try? await Task.sleep(nanoseconds: 1_000_000)
                    }
                    continuation.finish()
                }
            }
        }
        func stop() async {}
    }

    /// Records every text handed to the paste step. Empty `calls` ⇒ paste suppressed.
    private actor RecordingInserter: TextInserting {
        private(set) var calls: [String] = []
        func insert(_ text: String) async throws { calls.append(text) }
        func snapshot() -> [String] { calls }
    }

    /// A controllable action executor (records `run` names, returns a fixed result).
    private final class MockExecutor: ActionExecuting, @unchecked Sendable {
        let catalog: [String]
        let result: ActionExecutionResult
        private let lock = NSLock()
        private var _ranNames: [String] = []
        init(catalog: [String], result: ActionExecutionResult) {
            self.catalog = catalog
            self.result = result
        }
        func listActionNames() async -> [String] { catalog }
        func run(named name: String) async -> ActionExecutionResult {
            lock.withLock { _ranNames.append(name) }
            return result
        }
        var ranNames: [String] { lock.withLock { _ranNames } }
    }

    private final class MockSelection: SelectionAccessing, @unchecked Sendable {
        var selected: String?
        private(set) var replacedWith: String?
        init(selected: String?) { self.selected = selected }
        func readSelectedText() throws -> String? { selected }
        func replaceSelectedText(with text: String) throws { replacedWith = text }
    }

    fileprivate final class MockCleaner: LLMCleaning, @unchecked Sendable {
        let id = "mock-cleaner"
        var isAvailable: Bool { get async { true } }
        func clean(_ text: String, mode: CleanupMode) async throws -> String { "\(text) [cleaned]" }
    }

    // MARK: - Helper: assemble the newSession() handler closure with a real coordinator

    private func makeHandler(
        prefix: String,
        executor: (any ActionExecuting)?,
        commandService: CommandModeService?
    ) -> CaptureSession.VoiceActionsHandler {
        let coordinator = VoiceActionsCoordinator(
            router: PrefixActionRouter(prefix: prefix),
            executor: executor,
            commandService: commandService,
            enabled: true
        )
        return { rawText in
            let names = await executor?.listActionNames() ?? []
            return await coordinator.handle(transcript: rawText, knownActionNames: names)
        }
    }

    private func makeSession(
        finalText: String,
        inserter: RecordingInserter,
        handler: CaptureSession.VoiceActionsHandler?
    ) -> CaptureSession {
        CaptureSession(
            transcriber: ScriptedTranscriber(finalText: finalText),
            cleaner: nil,  // raw passthrough — paste delivers rawText
            inserter: inserter,
            voiceActionsHandler: handler
        )
    }

    private func drive(_ session: CaptureSession) async throws -> TranscriptionResult {
        try await session.start()
        try await Task.sleep(nanoseconds: 30_000_000)  // let the scripted chunk emit
        return try await session.stop()
    }

    // MARK: - Feature OFF: nil handler ⇒ byte-identical dictation (paste runs)

    func testFeatureOff_nilHandler_pastesTranscriptUnchanged() async throws {
        let inserter = RecordingInserter()
        let session = makeSession(finalText: "hey speak good morning", inserter: inserter, handler: nil)
        let result = try await drive(session)

        XCTAssertEqual(result.rawText, "hey speak good morning")
        let pasted = await inserter.snapshot()
        XCTAssertEqual(pasted, ["hey speak good morning"],
                       "Feature off must paste the transcript exactly as pre-H-1 dictation.")
    }

    // MARK: - Feature ON, action route ⇒ executor runs, paste suppressed

    func testActionRoute_executesAndSuppressesPaste() async throws {
        let executor = MockExecutor(catalog: ["Good Morning"], result: .success(output: nil))
        let inserter = RecordingInserter()
        let handler = makeHandler(prefix: "hey speak", executor: executor, commandService: nil)
        let session = makeSession(finalText: "hey speak good morning", inserter: inserter, handler: handler)

        let result = try await drive(session)

        XCTAssertEqual(executor.ranNames, ["Good Morning"], "The canonical action name must be executed.")
        let pasted = await inserter.snapshot()
        XCTAssertTrue(pasted.isEmpty, "An executed action must SUPPRESS the dictation paste.")
        XCTAssertEqual(result.rawText, "hey speak good morning", "Result still carries the original utterance.")
        XCTAssertNil(result.cleanedText)
    }

    // MARK: - Feature ON, command route ⇒ CommandModeService runs, paste suppressed

    func testCommandRoute_usesCommandServiceAndSuppressesPaste() async throws {
        // Remainder "make it formal" is not in the (empty) action catalog ⇒ .command.
        let selection = MockSelection(selected: "hello there")
        let commandService = CommandModeService(selection: selection, cleaner: MockCleaner())
        let inserter = RecordingInserter()
        let handler = makeHandler(prefix: "hey speak", executor: nil, commandService: commandService)
        let session = makeSession(finalText: "hey speak make it formal", inserter: inserter, handler: handler)

        let result = try await drive(session)

        XCTAssertEqual(selection.replacedWith, "hello there [cleaned]",
                       "The command route must run CommandModeService against the selection.")
        let pasted = await inserter.snapshot()
        XCTAssertTrue(pasted.isEmpty, "An executed command must SUPPRESS the dictation paste.")
        XCTAssertEqual(result.rawText, "hey speak make it formal")
    }

    // MARK: - Feature ON, degrade ⇒ ORIGINAL transcript is pasted (never lose words)

    func testCommandRoute_noSelection_degradesAndPastesOriginalTranscript() async throws {
        // No selection ⇒ CommandModeService returns .noSelection ⇒ coordinator degrades
        // to dictation carrying the ORIGINAL transcript. The pipeline must paste it.
        let selection = MockSelection(selected: nil)
        let commandService = CommandModeService(selection: selection, cleaner: MockCleaner())
        let inserter = RecordingInserter()
        let handler = makeHandler(prefix: "hey speak", executor: nil, commandService: commandService)
        let session = makeSession(finalText: "hey speak summarize this", inserter: inserter, handler: handler)

        let result = try await drive(session)

        let pasted = await inserter.snapshot()
        XCTAssertEqual(pasted, ["hey speak summarize this"],
                       "A degrade must paste the ORIGINAL transcript — the user's words are never lost.")
        XCTAssertEqual(result.rawText, "hey speak summarize this")
    }

    func testActionRoute_executorFailure_degradesAndPastesOriginalTranscript() async throws {
        let executor = MockExecutor(catalog: ["Good Morning"], result: .failed("boom"))
        let inserter = RecordingInserter()
        let handler = makeHandler(prefix: "hey speak", executor: executor, commandService: nil)
        let session = makeSession(finalText: "hey speak good morning", inserter: inserter, handler: handler)

        let result = try await drive(session)

        XCTAssertEqual(executor.ranNames, ["Good Morning"], "The action was attempted before degrading.")
        let pasted = await inserter.snapshot()
        XCTAssertEqual(pasted, ["hey speak good morning"],
                       "A failed action must degrade to dictation and paste the original transcript.")
        XCTAssertEqual(result.rawText, "hey speak good morning")
    }

    // MARK: - SpeakEngine-level wiring (H-1 gap closure)
    //
    // The tests above drive `CaptureSession` with a hand-assembled handler closure
    // that mirrors what `SpeakEngine.newSession()` builds. This section instead
    // drives `SpeakEngine` itself — proving `SpeakEngine.init(voiceActionsCommandService:)`
    // is actually threaded into the `VoiceActionsCoordinator` it constructs internally
    // (SpeakEngine.swift ~line 321), the same DI seam `DictationController.init()` now
    // wires with `AccessibilitySelection()` in production. No AX/Process here — a mock
    // `SelectionAccessing` stands in, same pattern as VoiceActionsCoordinatorTests.

    /// A no-op history store so the engine can be constructed headlessly.
    private final class NullHistory: HistoryStoring, @unchecked Sendable {
        func save(_ entry: HistoryEntry) async throws {}
        func recent(limit: Int) async throws -> [HistoryEntry] { [] }
        func search(_ substring: String) async throws -> [HistoryEntry] { [] }
        func clear() async throws {}
        func export() async throws -> String { "[]" }
    }

    /// Isolated `SettingsStore` (never touches `.standard`), with Voice Actions on.
    private func makeSettings(voiceActionsEnabled: Bool = true) throws -> SettingsStore {
        let suiteName = "VoiceActionsPipelineTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        addTeardownBlock { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
        let settings = SettingsStore(defaults: defaults)
        settings.voiceActionsEnabled = voiceActionsEnabled
        settings.voiceActionsPrefix = "hey speak"
        return settings
    }

    /// Transcript matches the command prefix but not the (empty) action catalog ⇒
    /// SpeakEngine must route it through the injected `voiceActionsCommandService`,
    /// not through dictation delivery.
    func testSpeakEngine_commandRoute_routesThroughInjectedCommandService() async throws {
        let selection = MockSelection(selected: "hello there")
        let commandService = CommandModeService(selection: selection, cleaner: MockCleaner())
        let inserter = RecordingInserter()
        let settings = try makeSettings()

        let engine = SpeakEngine(
            transcriber: ScriptedTranscriber(finalText: "hey speak make it formal"),
            cleaner: nil,
            inserter: inserter,
            history: NullHistory(),
            settings: settings,
            voiceActionsExecutor: nil,
            voiceActionsCommandService: commandService
        )

        // `newSession()` builds the real `CaptureSession` (and the internal
        // `VoiceActionsCoordinator` wired to `voiceActionsCommandService`) without the
        // `beginDictation()` microphone-authorization gate, which this sandbox cannot
        // grant. This still exercises SpeakEngine's own session-assembly code.
        let session = await engine.newSession()
        try await session.start()
        try await Task.sleep(nanoseconds: 30_000_000)
        let result = try await session.stop()

        XCTAssertEqual(selection.replacedWith, "hello there [cleaned]",
                       "SpeakEngine must route a matched, non-catalog command through the injected CommandModeService.")
        let pasted = await inserter.snapshot()
        XCTAssertTrue(pasted.isEmpty, "A routed command must suppress the dictation paste.")
        XCTAssertEqual(result.rawText, "hey speak make it formal")
    }

    /// With `voiceActionsCommandService == nil` (e.g. cleanup disabled at launch, per
    /// `DictationController.init`'s `defaultCleaner(for:).map { ... }`), the same
    /// transcript must degrade to plain dictation — never silently drop the utterance.
    func testSpeakEngine_commandRoute_nilCommandService_degradesToDictation() async throws {
        let inserter = RecordingInserter()
        let settings = try makeSettings()

        let engine = SpeakEngine(
            transcriber: ScriptedTranscriber(finalText: "hey speak make it formal"),
            cleaner: nil,
            inserter: inserter,
            history: NullHistory(),
            settings: settings,
            voiceActionsExecutor: nil,
            voiceActionsCommandService: nil
        )

        let session = await engine.newSession()
        try await session.start()
        try await Task.sleep(nanoseconds: 30_000_000)
        let result = try await session.stop()

        let pasted = await inserter.snapshot()
        XCTAssertEqual(pasted, ["hey speak make it formal"],
                       "Without a command service, the route must degrade to dictation and paste the original transcript.")
        XCTAssertEqual(result.rawText, "hey speak make it formal")
    }

    // MARK: - Feature ON, no prefix ⇒ plain dictation (paste runs)

    func testNoPrefix_plainDictation_pastesTranscript() async throws {
        let executor = MockExecutor(catalog: ["Good Morning"], result: .success(output: nil))
        let inserter = RecordingInserter()
        let handler = makeHandler(prefix: "hey speak", executor: executor, commandService: nil)
        let session = makeSession(finalText: "just some ordinary dictation", inserter: inserter, handler: handler)

        let result = try await drive(session)

        XCTAssertTrue(executor.ranNames.isEmpty, "No prefix ⇒ no action executed.")
        let pasted = await inserter.snapshot()
        XCTAssertEqual(pasted, ["just some ordinary dictation"],
                       "A non-prefixed utterance is plain dictation — pasted unchanged.")
        XCTAssertEqual(result.rawText, "just some ordinary dictation")
    }
}
