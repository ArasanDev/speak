// SpeakTests/WorkspaceStoreTests.swift
//
// Unit tests for WorkspaceStore SQLite channel and message persistence.

@testable import SpeakCore
import XCTest

final class WorkspaceStoreTests: XCTestCase {

    private var tempDBURL: URL!

    override func setUp() {
        super.setUp()
        tempDBURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("test_workspace_\(UUID().uuidString).sqlite")
    }

    override func tearDown() {
        if let tempDBURL = tempDBURL {
            try? FileManager.default.removeItem(at: tempDBURL)
        }
        super.tearDown()
    }

    func testWorkspaceStoreChannelsAndMessages() async throws {
        let store = try WorkspaceStore(databaseURL: tempDBURL)

        // Default #general channel should be auto-created
        let initialChannels = try await store.fetchChannels()
        XCTAssertEqual(initialChannels.count, 1)
        XCTAssertEqual(initialChannels[0].id, "general")

        // Create new channel #core-engine
        let newChannel = Channel(id: "core-engine", name: "core-engine", topic: "Engine development")
        try await store.createChannel(newChannel)

        let allChannels = try await store.fetchChannels()
        XCTAssertEqual(allChannels.count, 2)

        // Post messages to #core-engine
        let m1 = WorkspaceMessage(channelId: "core-engine", senderTag: "@tamil", text: "Tag @builder-audio check AudioCapture")
        try await store.postMessage(m1)

        let threadId = UUID()
        let m2 = WorkspaceMessage(channelId: "core-engine", threadId: threadId, senderTag: "@builder-audio", text: "Tap guard installed cleanly.")
        try await store.postMessage(m2)

        // Fetch top-level channel messages
        let mainMsgs = try await store.fetchMessages(channelId: "core-engine", threadId: nil)
        XCTAssertEqual(mainMsgs.count, 1)
        XCTAssertEqual(mainMsgs[0].text, "Tag @builder-audio check AudioCapture")

        // Fetch thread messages
        let threadMsgs = try await store.fetchMessages(channelId: "core-engine", threadId: threadId)
        XCTAssertEqual(threadMsgs.count, 1)
        XCTAssertEqual(threadMsgs[0].text, "Tap guard installed cleanly.")
    }
}
