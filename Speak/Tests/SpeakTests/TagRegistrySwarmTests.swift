// SpeakTests/TagRegistrySwarmTests.swift
//
// Unit tests for TagRegistry swarm tag alias resolution (@team, @engineers, @qa)
// and dynamic custom agent registration/lookup.

@testable import SpeakCore
import XCTest

final class TagRegistrySwarmTests: XCTestCase {

    /// 1. Tests TagRegistry.resolveSwarmTags expanding @team and @engineers into ["@Claude", "@builder-qa", "@terminal"].
    func testResolveSwarmTagsTeamAndEngineers() async throws {
        let registry = TagRegistry()

        let teamExpanded = await registry.resolveSwarmTags(tagName: "@team")
        XCTAssertEqual(teamExpanded, ["@Claude", "@builder-qa", "@terminal"])

        let engineersExpanded = await registry.resolveSwarmTags(tagName: "@engineers")
        XCTAssertEqual(engineersExpanded, ["@Claude", "@builder-qa", "@terminal"])

        let allAgentsExpanded = await registry.resolveSwarmTags(tagName: "@all-agents")
        XCTAssertEqual(allAgentsExpanded, ["@Claude", "@builder-qa", "@terminal"])

        // Case-insensitivity & missing @ prefix variations
        let teamNoPrefix = await registry.resolveSwarmTags(tagName: "team")
        XCTAssertEqual(teamNoPrefix, ["@Claude", "@builder-qa", "@terminal"])

        let engineersUppercase = await registry.resolveSwarmTags(tagName: "@ENGINEERS")
        XCTAssertEqual(engineersUppercase, ["@Claude", "@builder-qa", "@terminal"])
    }

    /// 2. Tests TagRegistry.resolveSwarmTags expanding @qa into ["@builder-qa", "@terminal"].
    func testResolveSwarmTagsQA() async throws {
        let registry = TagRegistry()

        let qaExpanded = await registry.resolveSwarmTags(tagName: "@qa")
        XCTAssertEqual(qaExpanded, ["@builder-qa", "@terminal"])

        // Case-insensitivity & missing @ prefix variations
        let qaNoPrefix = await registry.resolveSwarmTags(tagName: "qa")
        XCTAssertEqual(qaNoPrefix, ["@builder-qa", "@terminal"])

        let qaUppercase = await registry.resolveSwarmTags(tagName: "@QA")
        XCTAssertEqual(qaUppercase, ["@builder-qa", "@terminal"])

        // Single / non-swarm tags fallback to returning [normalized]
        let singleTag = await registry.resolveSwarmTags(tagName: "@claude")
        XCTAssertEqual(singleTag, ["@claude"])

        let singleTagNoPrefix = await registry.resolveSwarmTags(tagName: "terminal")
        XCTAssertEqual(singleTagNoPrefix, ["@terminal"])
    }

    /// 3. Tests TagRegistry.registerCustomAgent dynamic registration and lookup.
    func testRegisterCustomAgentAndLookup() async throws {
        let registry = TagRegistry()

        let customDefinition = CustomAgentDefinition(
            tagName: "dev-assistant",
            displayName: "Dev Assistant",
            description: "Custom developer assistant agent",
            systemPrompt: "You are a specialized developer assistant.",
            shellCommand: "scripts/dev_helper.sh",
            isLocalMCP: true
        )

        await registry.registerCustomAgent(customDefinition)

        // Lookup exact canonical name
        let foundExact = await registry.lookup(tagName: "@dev-assistant")
        XCTAssertNotNil(foundExact)
        XCTAssertEqual(foundExact?.tagName, "@dev-assistant")
        XCTAssertEqual(foundExact?.description, "Custom developer assistant agent")
        XCTAssertEqual(foundExact?.tagKind, .agent)
        XCTAssertEqual(foundExact?.capabilities, [.read, .execute, .notify])

        // Lookup case-insensitive without @ prefix
        let foundNoPrefix = await registry.lookup(tagName: "DEV-ASSISTANT")
        XCTAssertNotNil(foundNoPrefix)
        XCTAssertEqual(foundNoPrefix?.tagName, "@dev-assistant")

        // Verify allTags includes custom agent metadata
        let allTags = await registry.allTags()
        XCTAssertEqual(allTags.count, 1)
        XCTAssertEqual(allTags.first?.tagName, "@dev-assistant")

        // Verify custom agent execution turn outcome
        if let adapter = foundExact {
            let outcome = try await adapter.handleTurn(prompt: "Build project", sessionId: "session-123")
            if case .completed(let summary, let evidence) = outcome {
                XCTAssertTrue(summary.contains("Dev Assistant"))
                XCTAssertNotNil(evidence)
            } else {
                XCTFail("Expected .completed turn outcome")
            }
        }

        // Unregister custom agent
        await registry.unregister(tagName: "@dev-assistant")
        let missing = await registry.lookup(tagName: "@dev-assistant")
        XCTAssertNil(missing)
    }
}
