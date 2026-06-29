// SpeakTests/ProfileEngineTests.swift
//
// PE-0 (task #39) unit coverage for the Profile Engine data model + pure builder
// + shipped defaults (specs/profile-engine.md §2, specs/profile-system-prompts.md).
// Everything here is autonomously verifiable WITHOUT a live Foundation Models pass:
// it proves the schema round-trips, the PromptBuilder assembles deterministically,
// and the built-ins match the locked spec. Prompt *quality* on-device is the eval
// harness's job (#40), not this suite's.

@testable import SpeakCore
import XCTest

final class ProfileEngineTests: XCTestCase {

    // MARK: - Codable round-trip

    func testProfileCodableRoundTrip() throws {
        let original = Profile(
            name: "Custom",
            icon: "star",
            isBuiltIn: false,
            systemPrompt: "Do the thing.",
            examples: [Example(spoken: "hi there", written: "Hi there.")],
            format: .numbered,
            tone: .terse,
            length: .condense,
            contextInputs: [.selection, .appName],
            targetApps: ["com.example.app"],
            autoSubmit: true,
            model: .pluggable(engineID: "mlx-local")
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Profile.self, from: data)
        XCTAssertEqual(decoded, original, "Profile must survive an encode→decode round-trip unchanged.")
    }

    func testModelChoicePluggableRoundTrip() throws {
        for choice: ModelChoice in [.raw, .foundationModels, .pluggable(engineID: "openai-compat")] {
            let data = try JSONEncoder().encode(choice)
            let decoded = try JSONDecoder().decode(ModelChoice.self, from: data)
            XCTAssertEqual(decoded, choice, "ModelChoice \(choice) must round-trip via Codable.")
        }
    }

    // MARK: - PromptBuilder: assembly

    func testBuildPreservesSystemPromptAndAppendsTranscriptLast() {
        let profile = Profile(name: "P", icon: "x", systemPrompt: "SYSTEM_PROMPT_MARKER")
        let out = PromptBuilder.build(profile: profile, rawTranscript: "RAW_MARKER")
        XCTAssertTrue(out.contains("SYSTEM_PROMPT_MARKER"), "The system prompt must appear in the built prompt.")
        XCTAssertTrue(out.contains("Dictated speech:\nRAW_MARKER"),
                      "The raw transcript must be appended under the 'Dictated speech:' label.")
        XCTAssertTrue(out.hasSuffix("RAW_MARKER"), "The dictated speech must be the LAST section.")
    }

    func testDefaultKnobsAddNoClauses() {
        // asIs / neutral / preserve are the defaults — they must contribute nothing,
        // so a small model never sees a no-op instruction (profile-engine.md §6).
        let profile = Profile(name: "P", icon: "x", systemPrompt: "SP")
        let out = PromptBuilder.build(profile: profile, rawTranscript: "hello")
        XCTAssertNil(PromptBuilder.formatClause(.asIs))
        XCTAssertNil(PromptBuilder.toneClause(.neutral))
        XCTAssertNil(PromptBuilder.lengthClause(.preserve))
        // Built prompt is just system prompt + dictated speech.
        XCTAssertEqual(out, "SP\n\nDictated speech:\nhello",
                       "With default knobs and no examples, the prompt is system prompt + transcript only.")
    }

    func testNonDefaultKnobsAppendClauses() {
        let profile = Profile(
            name: "P", icon: "x", systemPrompt: "SP",
            format: .numbered, tone: .terse, length: .condense
        )
        let out = PromptBuilder.build(profile: profile, rawTranscript: "hello")
        XCTAssertTrue(out.contains("numbered list"), "format=.numbered must add its clause.")
        XCTAssertTrue(out.contains("terse"), "tone=.terse must add its clause.")
        XCTAssertTrue(out.contains("concise"), "length=.condense must add its clause.")
    }

    func testFewShotExamplesIncluded() {
        let profile = Profile(
            name: "P", icon: "x", systemPrompt: "SP",
            examples: [Example(spoken: "SPOKEN_A", written: "WRITTEN_A")]
        )
        let out = PromptBuilder.build(profile: profile, rawTranscript: "hi")
        XCTAssertTrue(out.contains("SPOKEN_A"), "Example input must appear in the prompt.")
        XCTAssertTrue(out.contains("WRITTEN_A"), "Example output must appear in the prompt.")
    }

    func testContextInjectedOnlyWhenRequestedAndProvided() {
        let profile = Profile(
            name: "P", icon: "x", systemPrompt: "SP",
            contextInputs: [.selection]
        )
        // Provided + requested → injected.
        let withCtx = PromptBuilder.build(
            profile: profile, rawTranscript: "hi", context: [.selection: "SELECTED_TEXT"]
        )
        XCTAssertTrue(withCtx.contains("SELECTED_TEXT"), "Requested+provided context must be injected.")
        // Requested but not provided → nothing.
        let noCtx = PromptBuilder.build(profile: profile, rawTranscript: "hi")
        XCTAssertFalse(noCtx.contains("Selected text"), "No value provided → no context block.")
        // Provided but not requested → ignored.
        let plain = Profile(name: "P", icon: "x", systemPrompt: "SP")
        let unrequested = PromptBuilder.build(
            profile: plain, rawTranscript: "hi", context: [.clipboard: "CLIP"]
        )
        XCTAssertFalse(unrequested.contains("CLIP"), "Context not in the profile's set must be ignored.")
    }

    // MARK: - PromptBuilder: Raw bypass

    func testRawModelReturnsTranscriptUnchanged() {
        let raw = DefaultProfiles.raw
        let transcript = "the raw words, untouched"
        XCTAssertEqual(PromptBuilder.build(profile: raw, rawTranscript: transcript), transcript,
                       "A .raw profile must return the transcript verbatim (base-core passthrough).")
    }

    // MARK: - DefaultProfiles

    func testFourBuiltInsPresent() {
        XCTAssertEqual(DefaultProfiles.all.count, 4,
                       "Ships Raw + Agent + Write + Note.")
        let names = Set(DefaultProfiles.all.map(\.name))
        XCTAssertEqual(names, ["Raw", "Agent", "Write", "Note"])
    }

    func testAllBuiltInsAreFlaggedBuiltIn() {
        for profile in DefaultProfiles.all {
            XCTAssertTrue(profile.isBuiltIn, "\(profile.name) must be isBuiltIn (resettable, not deletable).")
        }
    }

    func testRawIsBypass() {
        let raw = DefaultProfiles.raw
        XCTAssertEqual(raw.model, .raw, "Raw must use the .raw model.")
        XCTAssertTrue(raw.systemPrompt.isEmpty, "Raw must have an empty system prompt.")
    }

    func testWriteIsTheDefaultProfile() {
        XCTAssertEqual(DefaultProfiles.defaultProfile.name, "Write",
                       "The global default profile ships as Write (profile-taxonomy.md §1).")
        XCTAssertEqual(DefaultProfiles.write.model, .foundationModels)
    }

    func testBuiltInIdsAreStableAcrossConstruction() {
        // Reset-to-default + persisted overrides depend on stable built-in identity.
        let first = DefaultProfiles.all.map(\.id)
        let second = DefaultProfiles.all.map(\.id)
        XCTAssertEqual(first, second, "Built-in profile ids must be identical across constructions.")
        XCTAssertEqual(Set(first).count, first.count, "Built-in ids must be unique.")
    }

    func testDestinationsCarryTargetApps() {
        // Agent destination includes IDE/terminal/agent UIs.
        XCTAssertTrue(DefaultProfiles.agent.targetApps.contains("com.apple.dt.Xcode"))
        XCTAssertTrue(DefaultProfiles.agent.targetApps.contains("com.apple.Terminal"))
        // Write destination includes email/messaging/browsers.
        XCTAssertTrue(DefaultProfiles.write.targetApps.contains("com.apple.mail"))
        // Note destination includes personal notes apps.
        XCTAssertTrue(DefaultProfiles.note.targetApps.contains("com.apple.Notes"))
        // Raw has no auto-targets.
        XCTAssertTrue(DefaultProfiles.raw.targetApps.isEmpty, "Raw has no auto-targets.")
    }

    // MARK: - AgentCategory

    func testAgentCategoryFragmentsAppendedForAgentOnly() {
        // Category fragment should appear in Agent profile.
        let agentWithTask = PromptBuilder.instructions(
            profile: DefaultProfiles.agent, category: .task
        )
        let agentWithFix = PromptBuilder.instructions(
            profile: DefaultProfiles.agent, category: .fix
        )
        let agentWithCommit = PromptBuilder.instructions(
            profile: DefaultProfiles.agent, category: .commit
        )

        // Task fragment is default-ish but distinguishable.
        XCTAssertTrue(agentWithTask.contains("implementation task or refactoring"))
        // Fix fragment is distinctive.
        XCTAssertTrue(agentWithFix.contains("bug report"))
        // Commit fragment is distinctive.
        XCTAssertTrue(agentWithCommit.contains("Conventional Commits"))

        // Categories should NOT appear in non-Agent profiles.
        let writeWithCommit = PromptBuilder.instructions(
            profile: DefaultProfiles.write, category: .commit
        )
        XCTAssertFalse(writeWithCommit.contains("Conventional Commits"),
                       "Write profile must NOT include the commit category fragment.")

        let noteWithCode = PromptBuilder.instructions(
            profile: DefaultProfiles.note, category: .code
        )
        XCTAssertFalse(noteWithCode.contains("Convert spoken code notation"),
                       "Note profile must NOT include the code category fragment.")
    }

    func testAllCategoryFragmentsExist() {
        for category in AgentCategory.allCases {
            let fragment = PromptBuilder.categoryFragment(category)
            XCTAssertNotNil(fragment, "All AgentCategory cases must have a prompt fragment.")
        }
    }
}
