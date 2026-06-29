// SpeakTests/EvalHarnessTests.swift
//
// Small-models eval harness for the Profile Engine (roadmap SM-0). Runs golden
// `spoken → expected` fixtures through each profile's cleanup and reports
// pass/score + p50/p95 latency per profile.
//
// DESIGN:
//   - Fixtures live in Fixtures/eval-fixtures.json (2 per profile).
//   - Normal `make test` uses MockCleaner → zero latency, fast CI.
//   - `make eval` (SPEAK_EVAL=1) runs against live Foundation Models → real latencies.
//   - A regression test verifies that a deliberate output corruption fails the suite.

@testable import SpeakCore
import Foundation
import XCTest

@available(macOS 26.0, *)
final class EvalHarnessTests: XCTestCase {

    // MARK: - Fixture model

    /// A single fixture loaded from eval-fixtures.json.
    private struct Fixture: Decodable {
        let profileId: String
        let spoken: String
        let expected: String
        let formatChecks: [String]?
    }

    // MARK: - Mock cleaner

    /// A mock cleaner that returns the expected text for known fixtures, or
    /// echoes input for unknown ones. Can be configured to return a wrong
    /// output on demand (for regression testing).
    private actor MockCleaner: @preconcurrency LLMCleaning {
        var id: String { "mock" }

        /// If set, return this wrong output for all clean() calls. Used to test
        /// regression detection. `nil` → normal expected/echo behavior.
        private var forceWrongOutput: String? = nil

        var isAvailable: Bool { get async { true } }

        func clean(_ text: String, mode: CleanupMode) async throws -> String {
            // If wrong output is forced, return it (for regression testing).
            if let wrong = forceWrongOutput {
                return wrong
            }

            // Mock behavior: for profile mode, return the input as-is (passthrough).
            // The real scoring happens with the SpeakCore.evaluateFixture function
            // comparing against expected text. The mock cleaner just echoes input
            // when no wrong output is forced.
            return text
        }

        /// Force the next clean() call to return this wrong output.
        /// Used by the regression test.
        func injectWrongOutput(_ output: String) async {
            forceWrongOutput = output
        }

        /// Clear the forced wrong output.
        func clearWrongOutput() async {
            forceWrongOutput = nil
        }
    }

    // MARK: - Fixture loading

    /// Load all fixtures from eval-fixtures.json, resolved relative to this test file.
    private func loadFixtures() throws -> [Fixture] {
        let testFile = URL(fileURLWithPath: #filePath)
        let fixturesPath = testFile
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/eval-fixtures.json")

        guard FileManager.default.fileExists(atPath: fixturesPath.path) else {
            throw XCTSkip("eval-fixtures.json not found at \(fixturesPath.path). Run `make test` from repo root.")
        }

        let data = try Data(contentsOf: fixturesPath)
        let decoder = JSONDecoder()
        let fixtures = try decoder.decode([Fixture].self, from: data)
        return fixtures
    }

    /// Resolve a profileId string to a Profile object from DefaultProfiles.
    /// Throws XCTFail if the profileId is unknown.
    private func profileForId(_ id: String) throws -> Profile {
        switch id.lowercased() {
        case "raw":
            return DefaultProfiles.raw

        case "clean":
            return DefaultProfiles.clean

        case "chat":
            return DefaultProfiles.chat

        case "code":
            return DefaultProfiles.code

        case "cli":
            return DefaultProfiles.cli

        case "prompt":
            return DefaultProfiles.prompt

        case "commit":
            return DefaultProfiles.commit

        default:
            XCTFail("Unknown profileId: '\(id)'")
            throw NSError(domain: "EvalHarness", code: -1, userInfo: ["profileId": id])
        }
    }

    // MARK: - Core evaluation

    /// Evaluate a single fixture against a cleaner.
    private func evaluateSingleFixture(
        _ fixture: Fixture,
        profile: Profile,
        cleaner: LLMCleaning,
        level: CleanupLevel = .medium
    ) async throws -> FixtureResult {
        let startTime = Date()

        // For Raw profile, short-circuit: no cleaner call, just identity.
        if case .raw = profile.model {
            let elapsed = Date().timeIntervalSince(startTime)
            let checks = fixture.formatChecks ?? []
            let result = SpeakCore.evaluateFixture(
                output: fixture.spoken,
                expected: fixture.expected,
                formatCheckDescriptors: checks,
                correctnessThreshold: 1.0,  // Raw must be exact identity
                latencySeconds: elapsed
            )
            return result
        }

        // Normal path: call cleaner with the profile mode.
        let cleaned = try await cleaner.clean(
            fixture.spoken,
            mode: .profile(profile, level: level, customVocabulary: [])
        )
        let elapsed = Date().timeIntervalSince(startTime)

        let checks = fixture.formatChecks ?? []
        let result = SpeakCore.evaluateFixture(
            output: cleaned,
            expected: fixture.expected,
            formatCheckDescriptors: checks,
            correctnessThreshold: 0.80,  // [decision] Jaccard >= 80% for prose
            latencySeconds: elapsed
        )
        return result
    }

    /// Group fixtures and results by profile, compute stats (pass rate, mean score, p50, p95).
    private struct ProfileStats {
        let profileId: String
        let profileName: String
        let passCount: Int
        let totalCount: Int
        let meanCorrectness: Double
        let p50Latency: Double
        let p95Latency: Double
    }

    private func computeStats(
        from fixtureResults: [(Fixture, Profile, FixtureResult)]
    ) -> [ProfileStats] {
        let grouped = Dictionary(grouping: fixtureResults) { $0.1.name.lowercased() }

        return grouped.sorted(by: { $0.key < $1.key }).compactMap { profileKey, group in
            let profile = group.first?.1
            let profileName = profile?.name ?? "Unknown"
            let passCount = group.filter { $0.2.passed }.count
            let totalCount = group.count
            let meanCorrectness = group.map { $0.2.correctnessScore }.reduce(0, +) / Double(group.count)
            let latencies = group.map { $0.2.latencySeconds }
            let p50 = percentile50(latencies)
            let p95 = percentile95(latencies)

            return ProfileStats(
                profileId: profileKey,
                profileName: profileName,
                passCount: passCount,
                totalCount: totalCount,
                meanCorrectness: meanCorrectness,
                p50Latency: p50,
                p95Latency: p95
            )
        }
    }

    /// Format and print the results table. This is the ONE place where stdout
    /// is used directly (via FileHandle.standardOutput) instead of os.Logger.
    /// Justification: human-readable pass/fail table for CI and local runs;
    /// XCTest's logging is not suitable for tabular data. The table is also
    /// attached as an XCTAttachment for capture in test reports.
    private func printResultsTable(_ stats: [ProfileStats], allPassed: Bool) {
        // Right-pad to a fixed column width. We pad manually rather than via
        // String(format:): the `%s` specifier misreads a Swift String CVarArg as
        // a C char* (garbage/crash), and Foundation's `%@` does not honor field
        // width — so neither is usable for tabular string columns.
        func pad(_ value: String, _ width: Int) -> String {
            value.count >= width ? value : value + String(repeating: " ", count: width - value.count)
        }

        let header = """
            ╔═══════════╦════════╦══════════╦════════╦════════╗
            ║ Profile   ║ Status ║ Score    ║ p50    ║ p95    ║
            ╠═══════════╬════════╬══════════╬════════╬════════╣
            """

        let rows = stats.map { stat -> String in
            let status = stat.passCount == stat.totalCount ? "✓ PASS" : "✗ FAIL"
            let score = String(format: "%.2f%%", stat.meanCorrectness * 100.0)
            let p50 = String(format: "%.3fs", stat.p50Latency)
            let p95 = String(format: "%.3fs", stat.p95Latency)
            return "║ \(pad(stat.profileName, 9)) ║ \(pad(status, 6)) ║ \(pad(score, 8)) ║ \(pad(p50, 6)) ║ \(pad(p95, 6)) ║"
        }

        let footer = "╚═══════════╩════════╩══════════╩════════╩════════╝"
        let allStatus = allPassed ? "✓ ALL PASS" : "✗ SOME FAILED"

        let table = ([header] + rows + [footer] + ["", allStatus]).joined(separator: "\n")

        // Write to stdout for CI visibility.
        if let data = (table + "\n").data(using: .utf8) {
            FileHandle.standardOutput.write(data)
        }

        // Attach to the test report for capture in CI artifacts.
        let attachment = XCTAttachment(string: table)
        attachment.name = "eval-results.txt"
        add(attachment)
    }

    // MARK: - Test cases

    /// Unit tests on EvalScoring functions. These run in normal `make test` (no FM).
    func testScoringCorrectnessMetric() throws {
        // Perfect match
        XCTAssertEqual(correctness(output: "hello world", expected: "hello world"), 1.0)

        // No overlap
        XCTAssertEqual(correctness(output: "foo bar", expected: "baz qux"), 0.0)

        // Partial overlap (Jaccard: 2 common (one, two), 5 total unique → 2/5 = 0.4)
        let score = correctness(output: "one two three", expected: "one two four five")
        XCTAssertEqual(score, 0.4)

        // Case insensitive
        let scoreCase = correctness(output: "HELLO WORLD", expected: "hello world")
        XCTAssertEqual(scoreCase, 1.0)

        // Both empty
        XCTAssertEqual(correctness(output: "", expected: ""), 1.0)
    }

    func testScoringFormatChecks() throws {
        // startsWithCapital
        let startsCheck = try XCTUnwrap(BuiltInFormatChecks.parse("startsWithCapital"))
        XCTAssertTrue(startsCheck.predicate("Hello"))
        XCTAssertFalse(startsCheck.predicate("hello"))

        // noTrailingPeriod
        let periodCheck = try XCTUnwrap(BuiltInFormatChecks.parse("noTrailingPeriod"))
        XCTAssertTrue(periodCheck.predicate("hello"))
        XCTAssertFalse(periodCheck.predicate("hello."))

        // maxWords:N
        let maxCheck = try XCTUnwrap(BuiltInFormatChecks.parse("maxWords:2"))
        XCTAssertTrue(maxCheck.predicate("one two"))
        XCTAssertFalse(maxCheck.predicate("one two three"))

        // evaluateAll
        let (allPass, _) = BuiltInFormatChecks.evaluateAll(
            ["startsWithCapital", "noTrailingPeriod"],
            against: "Hello world"
        )
        XCTAssertTrue(allPass)

        let (someFail, failed) = BuiltInFormatChecks.evaluateAll(
            ["startsWithCapital", "noTrailingPeriod"],
            against: "hello world."
        )
        XCTAssertFalse(someFail)
        XCTAssertTrue(failed.contains("startsWithCapital"))
        XCTAssertTrue(failed.contains("noTrailingPeriod"))
    }

    func testScoringPercentiles() throws {
        // Single value
        XCTAssertEqual(percentile50([1.0]), 1.0)
        XCTAssertEqual(percentile95([1.0]), 1.0)

        // Two values
        XCTAssertEqual(percentile50([1.0, 2.0]), 1.0)  // Nearest-rank: lower
        XCTAssertEqual(percentile95([1.0, 2.0]), 2.0)

        // Multiple values
        let latencies = [1.0, 2.0, 3.0, 4.0, 5.0]
        let p50 = percentile50(latencies)
        let p95 = percentile95(latencies)
        XCTAssertGreaterThanOrEqual(p50, 1.0)
        XCTAssertLessThanOrEqual(p50, 5.0)
        XCTAssertGreaterThanOrEqual(p95, 1.0)
        XCTAssertLessThanOrEqual(p95, 5.0)
    }

    func testScoringFixtureEvaluation() throws {
        // Fixture passes: high correctness + all format checks pass
        let result1 = SpeakCore.evaluateFixture(
            output: "Hello world",
            expected: "Hello world",
            formatCheckDescriptors: ["startsWithCapital"],
            correctnessThreshold: 0.80
        )
        XCTAssertTrue(result1.passed)
        XCTAssertEqual(result1.correctnessScore, 1.0)

        // Fixture fails: equalsExpected requires exact match
        let result2 = SpeakCore.evaluateFixture(
            output: "hello world",
            expected: "Hello World",
            formatCheckDescriptors: ["equalsExpected"]
        )
        XCTAssertFalse(result2.passed)
        XCTAssertEqual(result2.correctnessScore, 0.0)
        XCTAssertTrue(result2.formatChecksFailed.contains("equalsExpected"))

        // Fixture fails: low correctness
        let result3 = SpeakCore.evaluateFixture(
            output: "foo bar",
            expected: "baz qux",
            correctnessThreshold: 0.80
        )
        XCTAssertFalse(result3.passed)
        XCTAssertEqual(result3.correctnessScore, 0.0)
    }

    /// Mock cleaner plumbing test: all fixtures run through MockCleaner
    /// and produce deterministic results (no actual model calls).
    func testMockPlumbing() async throws {
        let fixtures = try loadFixtures()
        XCTAssertFalse(fixtures.isEmpty, "No fixtures loaded — check eval-fixtures.json")

        let mockCleaner = MockCleaner()
        var fixtureResults: [(Fixture, Profile, FixtureResult)] = []

        for fixture in fixtures {
            let profile = try profileForId(fixture.profileId)
            let result = try await evaluateSingleFixture(fixture, profile: profile, cleaner: mockCleaner)
            fixtureResults.append((fixture, profile, result))
        }

        // All fixtures should produce zero latency (mock is instant).
        for (_, _, result) in fixtureResults {
            XCTAssertEqual(result.latencySeconds, 0.0, accuracy: 0.01)
        }

        let stats = computeStats(from: fixtureResults)
        XCTAssertEqual(stats.count, 7, "Expected 7 profiles")  // raw, clean, chat, code, cli, prompt, commit
    }

    /// Regression test: verify that a wrong output fails the evaluation.
    /// This proves that done-when #2 (prompt regression detection) is executable.
    func testRegressionDetection() async throws {
        let fixtures = try loadFixtures()
        let mockCleaner = MockCleaner()

        // Find a non-Raw fixture so we can test the cleaner path.
        let fixture = try XCTUnwrap(
            fixtures.first(where: { $0.profileId.lowercased() != "raw" }),
            "No non-Raw fixtures found"
        )
        let profile = try profileForId(fixture.profileId)

        // Inject a completely wrong output and verify the evaluation fails —
        // this is the executable proof of done-when #2 (a regressed prompt fails).
        await mockCleaner.injectWrongOutput("completely wrong output that has no tokens in common")
        let resultBad = try await evaluateSingleFixture(fixture, profile: profile, cleaner: mockCleaner)
        await mockCleaner.clearWrongOutput()

        // The bad result must fail: wrong output should not match expected.
        XCTAssertFalse(resultBad.passed, "Injected wrong output should fail the fixture")
        // The correctness score should be very low (no common tokens in "completely wrong...")
        XCTAssert(resultBad.correctnessScore <= 0.1, "Correctness should be near zero for injected wrong output, got \(resultBad.correctnessScore)")
    }

    /// Live Foundation Models evaluation (SPEAK_EVAL=1 only).
    /// This test is skipped in normal `make test` and only runs with `make eval`.
    func testLiveFoundationModelsEvaluation() async throws {
        guard ProcessInfo.processInfo.environment["SPEAK_EVAL"] == "1" else {
            throw XCTSkip("Set SPEAK_EVAL=1 (make eval) to run live Foundation Models scoring. Skip ≠ pass.")
        }

        let fixtures = try loadFixtures()
        XCTAssertFalse(fixtures.isEmpty)

        let cleaner = FoundationModelsCleaner()

        // Guard that Foundation Models is available on this machine.
        guard await cleaner.isAvailable else {
            throw XCTSkip("Foundation Models not available on this device. Skip ≠ pass.")
        }

        var fixtureResults: [(Fixture, Profile, FixtureResult)] = []

        for fixture in fixtures {
            let profile = try profileForId(fixture.profileId)
            let result = try await evaluateSingleFixture(fixture, profile: profile, cleaner: cleaner)
            fixtureResults.append((fixture, profile, result))
        }

        let stats = computeStats(from: fixtureResults)
        let allPassed = stats.allSatisfy { $0.passCount == $0.totalCount }

        printResultsTable(stats, allPassed: allPassed)

        // The eval harness does not enforce a hard pass/fail — it reports results.
        // SM-0 done-when #1 is satisfied by "runs and prints the table"; #2 is
        // satisfied by the regression test above. SM-1/SM-2 will tune prompts
        // to pass all fixtures.
        let statsText = stats.map { stat in
            "\(stat.profileName): \(stat.passCount)/\(stat.totalCount) " +
                "(\(String(format: "%.1f%%", stat.meanCorrectness * 100.0)) correctness)"
        }.joined(separator: "\n")
        let attachment = XCTAttachment(string: statsText)
        attachment.name = "profile-stats"
        add(attachment)
    }
}
