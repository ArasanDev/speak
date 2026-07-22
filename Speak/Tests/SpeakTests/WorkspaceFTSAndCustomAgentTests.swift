// Speak/Tests/SpeakTests/WorkspaceFTSAndCustomAgentTests.swift
//
// Unit tests for WorkspaceStore searchMessagesFTS and CustomAgentDefinition/DynamicCustomTagAdapter.

@testable import SpeakCore
import XCTest

final class WorkspaceFTSAndCustomAgentTests: XCTestCase {

    private var tempDBURL: URL!

    override func setUp() {
        super.setUp()
        tempDBURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("test_workspace_fts_\(UUID().uuidString).sqlite")
    }

    override func tearDown() {
        if let tempDBURL = tempDBURL {
            try? FileManager.default.removeItem(at: tempDBURL)
        }
        super.tearDown()
    }

    // MARK: - WorkspaceStore.searchMessagesFTS Tests

    func testWorkspaceStoreSearchMessagesFTSExactAndPartial() async throws {
        let store = try WorkspaceStore(databaseURL: tempDBURL)

        let msg1 = WorkspaceMessage(channelId: "general", senderTag: "@user1", text: "Voice dictation engine initialized successfully.")
        let msg2 = WorkspaceMessage(channelId: "general", senderTag: "@user2", text: "Testing SQLite search query for exact matching.")
        let msg3 = WorkspaceMessage(channelId: "core", senderTag: "@user3", text: "Partial matching substring search in core workspace.")
        let msg4 = WorkspaceMessage(channelId: "core", senderTag: "@user1", text: "Unrelated message about UI components.")

        try await store.postMessage(msg1)
        try await store.postMessage(msg2)
        try await store.postMessage(msg3)
        try await store.postMessage(msg4)

        // 1. Exact phrase / term search
        let exactResults = try await store.searchMessagesFTS(query: "Voice dictation")
        XCTAssertEqual(exactResults.count, 1)
        XCTAssertEqual(exactResults.first?.id, msg1.id)

        // 2. Partial term / substring search
        let partialResults = try await store.searchMessagesFTS(query: "search")
        XCTAssertEqual(partialResults.count, 2)
        let matchedIDs = Set(partialResults.map { $0.id })
        XCTAssertTrue(matchedIDs.contains(msg2.id))
        XCTAssertTrue(matchedIDs.contains(msg3.id))

        // 3. Case-insensitive substring search
        let caseResults = try await store.searchMessagesFTS(query: "ENGINE")
        XCTAssertEqual(caseResults.count, 1)
        XCTAssertEqual(caseResults.first?.id, msg1.id)

        // 4. Empty and whitespace queries
        let emptyResults = try await store.searchMessagesFTS(query: "")
        XCTAssertTrue(emptyResults.isEmpty)

        let whitespaceResults = try await store.searchMessagesFTS(query: "   \n\t  ")
        XCTAssertTrue(whitespaceResults.isEmpty)

        // 5. No match query
        let noMatchResults = try await store.searchMessagesFTS(query: "nonexistent_term_xyz")
        XCTAssertTrue(noMatchResults.isEmpty)
    }

    // MARK: - CustomAgentDefinition and DynamicCustomTagAdapter Tests

    func testCustomAgentDefinitionInitialization() {
        // Case 1: Without leading @ and uppercase characters
        let agent1 = CustomAgentDefinition(
            tagName: "AudioMaster",
            displayName: "Audio Master Agent",
            description: "Handles high quality audio processing",
            systemPrompt: "You are an audio expert.",
            shellCommand: "python3 process_audio.py",
            isLocalMCP: true
        )

        XCTAssertEqual(agent1.tagName, "@audiomaster")
        XCTAssertEqual(agent1.id, "@audiomaster")
        XCTAssertEqual(agent1.displayName, "Audio Master Agent")
        XCTAssertEqual(agent1.description, "Handles high quality audio processing")
        XCTAssertEqual(agent1.systemPrompt, "You are an audio expert.")
        XCTAssertEqual(agent1.shellCommand, "python3 process_audio.py")
        XCTAssertTrue(agent1.isLocalMCP)

        // Case 2: With leading @ already and lowercase
        let agent2 = CustomAgentDefinition(
            tagName: "@code_fixer",
            displayName: "Code Fixer",
            description: "Applies code patches"
        )

        XCTAssertEqual(agent2.tagName, "@code_fixer")
        XCTAssertEqual(agent2.id, "@code_fixer")
        XCTAssertNil(agent2.systemPrompt)
        XCTAssertNil(agent2.shellCommand)
        XCTAssertFalse(agent2.isLocalMCP)
    }

    func testDynamicCustomTagAdapterHandleTurnOutcome() async throws {
        let definition = CustomAgentDefinition(
            tagName: "summarizer",
            displayName: "Text Summarizer",
            description: "Summarizes long text transcripts",
            systemPrompt: "Summarize concisely",
            shellCommand: "./summarize.sh"
        )

        let adapter = DynamicCustomTagAdapter(definition: definition)

        // Test protocol properties
        XCTAssertEqual(adapter.tagName, "@summarizer")
        XCTAssertEqual(adapter.tagKind, .agent)
        XCTAssertEqual(adapter.description, "Summarizes long text transcripts")
        XCTAssertEqual(adapter.capabilities, [.read, .execute, .notify])

        // Test handleTurn
        let prompt = "Please summarize the audio session from this morning."
        let outcome = try await adapter.handleTurn(prompt: prompt, sessionId: "session_001")

        if case .completed(let summary, let evidence) = outcome {
            XCTAssertTrue(summary.contains("Custom Agent [Text Summarizer] processed turn"))
            XCTAssertTrue(summary.contains("Please summarize the audio session from this morning."))

            let unwrappedEvidence = try XCTUnwrap(evidence)
            XCTAssertEqual(unwrappedEvidence.summary, summary)
            XCTAssertEqual(unwrappedEvidence.checklist.count, 2)

            XCTAssertEqual(unwrappedEvidence.checklist[0].id, "c1")
            XCTAssertEqual(unwrappedEvidence.checklist[0].title, "Parsed prompt via custom agent handler")
            XCTAssertEqual(unwrappedEvidence.checklist[0].status, .done)

            XCTAssertEqual(unwrappedEvidence.checklist[1].id, "c2")
            XCTAssertEqual(unwrappedEvidence.checklist[1].title, "Executed shell command: ./summarize.sh")
            XCTAssertEqual(unwrappedEvidence.checklist[1].status, .done)
        } else {
            XCTFail("Expected .completed outcome from DynamicCustomTagAdapter.handleTurn, got \(outcome)")
        }
    }
}
