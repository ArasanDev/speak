// SpeakTests/VoiceActionsCoordinatorTests.swift
//
// H-1 (specs/horizon-voice-os.md, Pillar 1) — unit tests for `VoiceActionsCoordinator`,
// the seam that ties `ActionRouting` + `ActionExecuting` + `CommandModeService`
// together. Focus: the "never lose the user's words" contract — every non-success
// path must degrade to `.degradedToDictation` carrying the ORIGINAL transcript,
// never `.command`/`.action` failing silently.
//
// Mocks mirror CommandModeServiceTests.swift's pattern (mock SelectionAccessing +
// mock LLMCleaning) so CommandModeService itself runs for real, unmocked.

@testable import SpeakCore
import XCTest

final class VoiceActionsCoordinatorTests: XCTestCase {

    // MARK: - Mocks

    private final class MockSelection: SelectionAccessing, @unchecked Sendable {
        var selected: String?
        private(set) var replacedWith: String?
        init(selected: String?) { self.selected = selected }
        func readSelectedText() throws -> String? { selected }
        func replaceSelectedText(with text: String) throws { replacedWith = text }
    }

    private final class MockCleaner: LLMCleaning, @unchecked Sendable {
        let id = "mock"
        let available: Bool
        init(available: Bool) { self.available = available }
        var isAvailable: Bool { get async { available } }
        func clean(_ text: String, mode: CleanupMode) async throws -> String {
            "\(text) [cleaned]"
        }
    }

    private final class MockExecutor: ActionExecuting, @unchecked Sendable {
        var catalog: [String]
        var result: ActionExecutionResult
        private(set) var ranNames: [String] = []
        init(catalog: [String] = [], result: ActionExecutionResult = .success(output: nil)) {
            self.catalog = catalog
            self.result = result
        }
        func listActionNames() async -> [String] { catalog }
        func run(named name: String) async -> ActionExecutionResult {
            ranNames.append(name)
            return result
        }
    }

    private let router = PrefixActionRouter(prefix: "hey speak")

    // MARK: - Disabled: always dictation, router never routes anything else

    func testDisabled_alwaysReturnsDictationEvenWithMatchingPrefix() async {
        let coordinator = VoiceActionsCoordinator(
            router: router,
            executor: MockExecutor(catalog: ["Good Morning"], result: .success(output: nil)),
            commandService: nil,
            enabled: false
        )
        let outcome = await coordinator.handle(
            transcript: "hey speak good morning",
            knownActionNames: ["Good Morning"]
        )
        XCTAssertEqual(outcome, .dictation(text: "hey speak good morning"))
    }

    // MARK: - Plain dictation (no prefix)

    func testNoPrefixMatch_returnsDictation() async {
        let coordinator = VoiceActionsCoordinator(router: router, enabled: true)
        let outcome = await coordinator.handle(transcript: "just a normal dictation")
        XCTAssertEqual(outcome, .dictation(text: "just a normal dictation"))
    }

    // MARK: - Command route

    func testCommand_success_returnsCommandExecuted() async {
        let selection = MockSelection(selected: "i think we should ship it")
        let cleaner = MockCleaner(available: true)
        let commandService = CommandModeService(selection: selection, cleaner: cleaner)
        let coordinator = VoiceActionsCoordinator(router: router, commandService: commandService, enabled: true)

        let outcome = await coordinator.handle(transcript: "hey speak make this more formal")

        XCTAssertEqual(outcome, .commandExecuted(result: "i think we should ship it [cleaned]"))
    }

    func testCommand_noCommandServiceConfigured_degradesToDictationWithOriginalTranscript() async {
        let coordinator = VoiceActionsCoordinator(router: router, commandService: nil, enabled: true)
        let original = "hey speak make this more formal"

        let outcome = await coordinator.handle(transcript: original)

        guard case .degradedToDictation(let text, _) = outcome else {
            return XCTFail("Expected .degradedToDictation, got \(outcome)")
        }
        XCTAssertEqual(text, original, "The original, unstripped transcript must survive — never lose the user's words.")
    }

    func testCommand_noSelection_degradesToDictation_neverSilentlyDropsWords() async {
        let selection = MockSelection(selected: nil)   // no selection at all
        let cleaner = MockCleaner(available: true)
        let commandService = CommandModeService(selection: selection, cleaner: cleaner)
        let coordinator = VoiceActionsCoordinator(router: router, commandService: commandService, enabled: true)
        let original = "hey speak make this more formal"

        let outcome = await coordinator.handle(transcript: original)

        guard case .degradedToDictation(let text, _) = outcome else {
            return XCTFail("Expected .degradedToDictation (CommandModeOutcome.noSelection), got \(outcome)")
        }
        XCTAssertEqual(text, original)
    }

    func testCommand_modelUnavailable_degradesToDictation() async {
        let selection = MockSelection(selected: "some selected text")
        let cleaner = MockCleaner(available: false)
        let commandService = CommandModeService(selection: selection, cleaner: cleaner)
        let coordinator = VoiceActionsCoordinator(router: router, commandService: commandService, enabled: true)
        let original = "hey speak summarize this"

        let outcome = await coordinator.handle(transcript: original)

        guard case .degradedToDictation(let text, _) = outcome else {
            return XCTFail("Expected .degradedToDictation (CommandModeOutcome.modelUnavailable), got \(outcome)")
        }
        XCTAssertEqual(text, original)
        XCTAssertNil(selection.replacedWith, "Selection must not be touched when the model is unavailable.")
    }

    // MARK: - Action route

    func testAction_success_returnsActionExecuted() async {
        let executor = MockExecutor(result: .success(output: nil))
        let coordinator = VoiceActionsCoordinator(router: router, executor: executor, enabled: true)

        let outcome = await coordinator.handle(
            transcript: "hey speak good morning",
            knownActionNames: ["Good Morning"]
        )

        XCTAssertEqual(outcome, .actionExecuted(name: "Good Morning"))
        XCTAssertEqual(executor.ranNames, ["Good Morning"])
    }

    func testAction_noExecutorConfigured_degradesToDictationWithOriginalTranscript() async {
        let coordinator = VoiceActionsCoordinator(router: router, executor: nil, enabled: true)
        let original = "hey speak good morning"

        let outcome = await coordinator.handle(transcript: original, knownActionNames: ["Good Morning"])

        guard case .degradedToDictation(let text, _) = outcome else {
            return XCTFail("Expected .degradedToDictation, got \(outcome)")
        }
        XCTAssertEqual(text, original)
    }

    func testAction_executorFails_degradesToDictationWithOriginalTranscript() async {
        let executor = MockExecutor(result: .failed("shortcut errored"))
        let coordinator = VoiceActionsCoordinator(router: router, executor: executor, enabled: true)
        let original = "hey speak good morning"

        let outcome = await coordinator.handle(transcript: original, knownActionNames: ["Good Morning"])

        guard case .degradedToDictation(let text, _) = outcome else {
            return XCTFail("Expected .degradedToDictation, got \(outcome)")
        }
        XCTAssertEqual(text, original)
    }

    func testAction_notFound_degradesToDictation() async {
        let executor = MockExecutor(result: .notFound)
        let coordinator = VoiceActionsCoordinator(router: router, executor: executor, enabled: true)
        let original = "hey speak good morning"

        let outcome = await coordinator.handle(transcript: original, knownActionNames: ["Good Morning"])

        guard case .degradedToDictation = outcome else {
            return XCTFail("Expected .degradedToDictation, got \(outcome)")
        }
    }
}
