// SpeakTests/TagRegistryTests.swift
//
// Unit tests for TagRegistry actor and PluginTagAdapter lookup.

@testable import SpeakCore
import XCTest

private final class MockTagAdapter: PluginTagAdapter, @unchecked Sendable {
    let tagName: String
    let tagKind: TagKind
    let description: String
    let capabilities: [TagCapability]

    init(tagName: String, tagKind: TagKind, description: String, capabilities: [TagCapability]) {
        self.tagName = tagName
        self.tagKind = tagKind
        self.description = description
        self.capabilities = capabilities
    }

    func handleTurn(prompt: String, sessionId: String?) async throws -> TagTurnOutcome {
        return .completed(summary: "Handled: \(prompt)", evidence: nil)
    }
}

final class TagRegistryTests: XCTestCase {

    func testTagRegistryRegisterAndLookup() async throws {
        let registry = TagRegistry()
        let mock = MockTagAdapter(
            tagName: "@builder-audio",
            tagKind: .agent,
            description: "Audio engine specialist",
            capabilities: [.read, .execute]
        )

        await registry.register(mock)

        // Lookup with exact name
        let found = await registry.lookup(tagName: "@builder-audio")
        XCTAssertNotNil(found)
        XCTAssertEqual(found?.tagName, "@builder-audio")

        // Case-insensitive lookup without @ prefix
        let foundNoPrefix = await registry.lookup(tagName: "BUILDER-AUDIO")
        XCTAssertNotNil(foundNoPrefix)
        XCTAssertEqual(foundNoPrefix?.tagName, "@builder-audio")

        // Unregister
        await registry.unregister(tagName: "@builder-audio")
        let missing = await registry.lookup(tagName: "@builder-audio")
        XCTAssertNil(missing)
    }

    func testTagRegistryListAll() async throws {
        let registry = TagRegistry()
        let t1 = MockTagAdapter(tagName: "@terminal", tagKind: .plugin, description: "Local terminal", capabilities: [.execute])
        let t2 = MockTagAdapter(tagName: "@Claude", tagKind: .agent, description: "Claude Code Agent", capabilities: [.read, .execute])

        await registry.register(t1)
        await registry.register(t2)

        let tags = await registry.allTags()
        XCTAssertEqual(tags.count, 2)
        XCTAssertEqual(tags[0].tagName, "@Claude")
        XCTAssertEqual(tags[1].tagName, "@terminal")
    }
}
