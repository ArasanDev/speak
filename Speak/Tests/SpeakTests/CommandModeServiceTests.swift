// SpeakTests/CommandModeServiceTests.swift
//
// Wave D — unit tests for the Command Mode orchestration core. The live AX selection
// read/replace is [deferred — human verification]; here we inject mocks to verify the
// read → transform → replace flow and the no-op contracts.

@testable import SpeakCore
import XCTest

final class CommandModeServiceTests: XCTestCase {

    // MARK: - Mocks

    private final class MockSelection: SelectionAccessing, @unchecked Sendable {
        var selected: String?
        private(set) var replacedWith: String?
        var readError: Error?
        init(selected: String?) { self.selected = selected }
        func readSelectedText() throws -> String? {
            if let readError { throw readError }
            return selected
        }
        func replaceSelectedText(with text: String) throws { replacedWith = text }
    }

    private final class MockCleaner: LLMCleaning, @unchecked Sendable {
        let id = "mock"
        let available: Bool
        let transform: @Sendable (String) -> String
        private(set) var receivedMode: CleanupMode?
        init(available: Bool, transform: @escaping @Sendable (String) -> String) {
            self.available = available
            self.transform = transform
        }
        var isAvailable: Bool { get async { available } }
        func clean(_ text: String, mode: CleanupMode) async throws -> String {
            receivedMode = mode
            return transform(text)
        }
    }

    // MARK: - Tests

    func testRun_replacesSelectionWithTransformedResult() async throws {
        let selection = MockSelection(selected: "i think we should ship it")
        let cleaner = MockCleaner(available: true) { _ in "We should ship it." }
        let service = CommandModeService(selection: selection, cleaner: cleaner)

        let outcome = try await service.run(instruction: "make this a proper sentence")

        XCTAssertEqual(outcome, .replaced("We should ship it."))
        XCTAssertEqual(selection.replacedWith, "We should ship it.")
    }

    func testRun_passesCommandModeWithInstruction() async throws {
        let selection = MockSelection(selected: "hola")
        let cleaner = MockCleaner(available: true) { $0 + "!" }
        let service = CommandModeService(selection: selection, cleaner: cleaner)

        _ = try await service.run(instruction: "translate to English")

        guard case .command(let instruction)? = cleaner.receivedMode else {
            return XCTFail("Cleaner must receive a .command mode, got \(String(describing: cleaner.receivedMode))")
        }
        XCTAssertEqual(instruction, "translate to English")
    }

    func testRun_noSelection_isNoOp() async throws {
        let selection = MockSelection(selected: "   ")   // blank
        let cleaner = MockCleaner(available: true) { _ in "should not run" }
        let service = CommandModeService(selection: selection, cleaner: cleaner)

        let outcome = try await service.run(instruction: "do something")

        XCTAssertEqual(outcome, .noSelection)
        XCTAssertNil(selection.replacedWith, "Nothing must be written when there is no selection.")
    }

    func testRun_modelUnavailable_leavesSelectionIntact() async throws {
        let selection = MockSelection(selected: "important text")
        let cleaner = MockCleaner(available: false) { _ in "" }
        let service = CommandModeService(selection: selection, cleaner: cleaner)

        let outcome = try await service.run(instruction: "summarize")

        XCTAssertEqual(outcome, .modelUnavailable)
        XCTAssertNil(selection.replacedWith,
                     "The selection must NOT be overwritten when the model is unavailable.")
    }
}
