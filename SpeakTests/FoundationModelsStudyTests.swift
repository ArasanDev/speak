// SpeakTests/FoundationModelsStudyTests.swift
//
// SM-1 Foundation Models measurement harness — RAW data collection.
// Measures three axes of Foundation Models behavior on this Mac:
//   1. Latency vs input length (10 → 400 words)
//   2. Instruction-following (preamble resistance)
//   3. Length ceiling (where output truncates/empties/throws)
//
// DESIGN:
//   - SPEAK_STUDY=1 only (normal `make test` skips silently).
//   - FM unavailability → XCTSkip (not an error; self-documents in the report).
//   - Writes RAW measured data to specs/sm1-fm-measurements-RAW.md.
//   - Fixed cleanup mode: .styled(.default, .medium).
//   - Outputs summary table to FileHandle.standardOutput for CI visibility.

@testable import SpeakCore
import Foundation
import XCTest

@available(macOS 26.0, *)
final class FoundationModelsStudyTests: XCTestCase {

    // MARK: - Test fixtures & constants

    /// Base natural sentence, repeated to build inputs of different word counts.
    /// Chose this simple sentence for reproducibility and moderate token count.
    private let baseSentence = "The quick brown fox jumps over the lazy dog while the sun shines bright."

    /// Count words in a string (whitespace-split).
    private func wordCount(_ text: String) -> Int {
        text.split(separator: " ").count
    }

    /// Build an input string by repeating the base sentence to hit ≈targetWords.
    /// Returns the actual text and actual word count.
    private func buildInput(targetWords: Int) -> (text: String, actualWordCount: Int) {
        var result = ""
        var currentWordCount = 0
        let baseWordCount = wordCount(baseSentence)
        let repetitionsNeeded = max(1, (targetWords + baseWordCount - 1) / baseWordCount)

        for _ in 0..<repetitionsNeeded {
            if !result.isEmpty {
                result += " "
            }
            result += baseSentence
            currentWordCount = wordCount(result)
            if currentWordCount >= targetWords {
                break
            }
        }

        return (text: result, actualWordCount: currentWordCount)
    }

    /// Percentile helper: p50 (median).
    private func percentile50(_ values: [TimeInterval]) -> TimeInterval {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let mid = sorted.count / 2
        return sorted[mid]
    }

    /// Percentile helper: p95.
    private func percentile95(_ values: [TimeInterval]) -> TimeInterval {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let idx = max(0, Int(Double(sorted.count) * 0.95))
        return sorted[min(idx, sorted.count - 1)]
    }

    /// Format a time interval as "X.XXXs".
    private func formatLatency(_ seconds: TimeInterval) -> String {
        String(format: "%.3fs", seconds)
    }

    // MARK: - Latency measurement

    /// Measure latency vs input word length.
    /// Tests clean() calls on inputs of 10/25/50/100/200/400 words, N=3 runs per size.
    /// Records min/median/max latency for each size.
    func testLatencyVsInputLength() async throws {
        // Guard: SPEAK_STUDY=1
        guard ProcessInfo.processInfo.environment["SPEAK_STUDY"] == "1" else {
            throw XCTSkip("Set SPEAK_STUDY=1 (make study) to run the live FM measurement study. Skip ≠ pass.")
        }

        let cleaner = FoundationModelsCleaner()

        // Guard: FM availability
        guard await cleaner.isAvailable else {
            throw XCTSkip("Foundation Models not available on this device (e.g., Apple Intelligence not enabled).")
        }

        // [decision] Target word sizes for latency sweep: 10, 25, 50, 100, 200, 400.
        let targetWordSizes = [10, 25, 50, 100, 200, 400]
        // [decision] Run N=3 times per size to compute min/median/max.
        let trialsPerSize = 3
        // [decision] Timeout safety: if any call exceeds 15s, skip remaining trials for that size.
        let timeoutSeconds = 15.0

        var latencyResults: [(wordCount: Int, min: TimeInterval, median: TimeInterval, max: TimeInterval)] = []

        for targetSize in targetWordSizes {
            let (input, actualWordCount) = buildInput(targetWords: targetSize)
            var latencies: [TimeInterval] = []

            for trial in 1...trialsPerSize {
                let startTime = Date()
                do {
                    let _ = try await cleaner.clean(
                        input,
                        mode: .styled(.default, .medium, customVocabulary: [])
                    )
                    let elapsed = Date().timeIntervalSince(startTime)

                    if elapsed > timeoutSeconds {
                        // [decision] Timeout reached; skip remaining trials for this size.
                        print("  Trial \(trial)/\(trialsPerSize): TIMEOUT (>\(timeoutSeconds)s)")
                        break
                    }

                    latencies.append(elapsed)
                    print("  Trial \(trial)/\(trialsPerSize): \(formatLatency(elapsed))")
                } catch {
                    print("  Trial \(trial)/\(trialsPerSize): ERROR — \(error)")
                    break
                }
            }

            if !latencies.isEmpty {
                let min = latencies.min() ?? 0
                let median = percentile50(latencies)
                let max = latencies.max() ?? 0
                latencyResults.append((wordCount: actualWordCount, min: min, median: median, max: max))
                print("  ▪ \(actualWordCount) words: min=\(formatLatency(min)), p50=\(formatLatency(median)), max=\(formatLatency(max))")
            }
        }

        // Emit latency results to the report.
        var reportLines: [String] = []
        reportLines.append("## Latency vs Input Length")
        reportLines.append("")
        reportLines.append("| Word Count | Min (s) | p50 (s) | Max (s) |")
        reportLines.append("|------------|---------|---------|---------|")
        for result in latencyResults {
            let min = String(format: "%.3f", result.min)
            let p50 = String(format: "%.3f", result.median)
            let max = String(format: "%.3f", result.max)
            reportLines.append("| \(result.wordCount) | \(min) | \(p50) | \(max) |")
        }
        reportLines.append("")

        self.latencyReport = reportLines.joined(separator: "\n")
    }

    private var latencyReport: String = ""

    // MARK: - Instruction-following measurement

    /// Measure instruction-following: does the output start with a preamble token?
    /// Tests 5 short inputs that tempt preamble responses (um/okay/well/here/sure/etc).
    func testInstructionFollowing() async throws {
        // Guard: SPEAK_STUDY=1
        guard ProcessInfo.processInfo.environment["SPEAK_STUDY"] == "1" else {
            throw XCTSkip("Set SPEAK_STUDY=1 (make study) to run the live FM measurement study. Skip ≠ pass.")
        }

        let cleaner = FoundationModelsCleaner()

        // Guard: FM availability
        guard await cleaner.isAvailable else {
            throw XCTSkip("Foundation Models not available on this device (e.g., Apple Intelligence not enabled).")
        }

        // [decision] Five short inputs that tempt preamble responses:
        let testInputs = [
            "okay so um can you help me with this problem",
            "um can you like maybe clean this up please",
            "so i want to uh figure out what's happening here",
            "okay um right so we need to do something about this",
            "like you know can you help me with this text here"
        ]

        // [decision] Tokens that indicate preamble start (case-insensitive):
        let preambleTokens = Set(["sure", "here", "okay", "well", "of", "course", "certainly"])

        var results: [(input: String, output: String, hasPreamble: Bool)] = []

        for testInput in testInputs {
            do {
                let output = try await cleaner.clean(
                    testInput,
                    mode: .styled(.default, .medium, customVocabulary: [])
                )
                let firstWord = output.split(separator: " ").first.map(String.init) ?? ""
                let hasPreamble = preambleTokens.contains(firstWord.lowercased())
                results.append((input: testInput, output: output, hasPreamble: hasPreamble))
                print("  Input: '\(testInput)'")
                print("  Output: '\(output)'")
                print("  Preamble: \(hasPreamble ? "YES" : "NO")")
                print("")
            } catch {
                print("  Input: '\(testInput)' — ERROR: \(error)")
            }
        }

        // Emit instruction-following results to the report.
        var reportLines: [String] = []
        reportLines.append("## Instruction-Following (Preamble Resistance)")
        reportLines.append("")
        reportLines.append("Five short, preamble-tempting inputs. Output checked for preamble tokens (Sure/Here/Okay/etc).")
        reportLines.append("")
        for (i, result) in results.enumerated() {
            reportLines.append("### Test \(i + 1)")
            reportLines.append("")
            reportLines.append("**Input:** `\(result.input)`")
            reportLines.append("")
            reportLines.append("**Output:** `\(result.output)`")
            reportLines.append("")
            reportLines.append("**Preamble detected:** \(result.hasPreamble ? "YES" : "NO")")
            reportLines.append("")
        }

        self.instructionFollowingReport = reportLines.joined(separator: "\n")
    }

    private var instructionFollowingReport: String = ""

    // MARK: - Length ceiling measurement

    /// Measure where output truncates, empties, or throws.
    /// Iteratively increase input size until clean() throws, returns empty, or exceeds timeout.
    func testLengthCeiling() async throws {
        // Guard: SPEAK_STUDY=1
        guard ProcessInfo.processInfo.environment["SPEAK_STUDY"] == "1" else {
            throw XCTSkip("Set SPEAK_STUDY=1 (make study) to run the live FM measurement study. Skip ≠ pass.")
        }

        let cleaner = FoundationModelsCleaner()

        // Guard: FM availability
        guard await cleaner.isAvailable else {
            throw XCTSkip("Foundation Models not available on this device (e.g., Apple Intelligence not enabled).")
        }

        // [decision] Start at 400 words and increase by 200 each iteration.
        // [decision] Maximum iterations = 10 to prevent infinite loops.
        // [decision] Timeout per call = 15 seconds.
        let stepSize = 200
        let maxIterations = 10
        let timeoutSeconds = 15.0
        var currentSize = 400

        var findings: [(wordCount: Int, result: String)] = []

        for _ in 1...maxIterations {
            let (input, actualWordCount) = buildInput(targetWords: currentSize)

            let startTime = Date()
            do {
                let output = try await cleaner.clean(
                    input,
                    mode: .styled(.default, .medium, customVocabulary: [])
                )
                let elapsed = Date().timeIntervalSince(startTime)

                if elapsed > timeoutSeconds {
                    findings.append((wordCount: actualWordCount, result: "TIMEOUT (>\(timeoutSeconds)s)"))
                    print("Size \(actualWordCount) words: TIMEOUT")
                    break
                }

                if output.isEmpty {
                    findings.append((wordCount: actualWordCount, result: "EMPTY OUTPUT"))
                    print("Size \(actualWordCount) words: EMPTY OUTPUT")
                    break
                }

                findings.append((wordCount: actualWordCount, result: "OK (\(output.count) chars)"))
                print("Size \(actualWordCount) words: OK (\(output.count) chars)")

                // [decision] Continue stepping up until we hit a boundary or max iterations.
                currentSize += stepSize
            } catch {
                let errorDesc = String(describing: error)
                findings.append((wordCount: actualWordCount, result: "ERROR: \(errorDesc)"))
                print("Size \(actualWordCount) words: ERROR — \(errorDesc)")
                break
            }
        }

        // Emit ceiling results to the report.
        var reportLines: [String] = []
        reportLines.append("## Length Ceiling")
        reportLines.append("")
        reportLines.append("Iteratively increase input size until output truncates, empties, or API throws.")
        reportLines.append("Step size: \(stepSize) words. [decision] Max iterations: \(maxIterations). [decision] Timeout per call: \(timeoutSeconds)s.")
        reportLines.append("")
        reportLines.append("| Word Count | Outcome |")
        reportLines.append("|------------|---------|")
        for finding in findings {
            reportLines.append("| \(finding.wordCount) | \(finding.result) |")
        }
        reportLines.append("")

        self.ceilingReport = reportLines.joined(separator: "\n")
    }

    private var ceilingReport: String = ""

    // MARK: - Consolidated measurement run

    /// Master test: runs all three measurement axes and writes the RAW report.
    /// This is the one test that coordinates all measurements and writes the final artifact.
    func testRunAllMeasurements() async throws {
        // Guard: SPEAK_STUDY=1
        guard ProcessInfo.processInfo.environment["SPEAK_STUDY"] == "1" else {
            throw XCTSkip("Set SPEAK_STUDY=1 (make study) to run the live FM measurement study. Skip ≠ pass.")
        }

        let cleaner = FoundationModelsCleaner()

        // Guard: FM availability
        guard await cleaner.isAvailable else {
            // FM unavailable: write minimal report and skip.
            let formatter = ISO8601DateFormatter()
            let timestamp = formatter.string(from: Date())
            let skipReport = """
                # SM-1 Foundation Models Measurement — RAW Data

                **Status:** SKIPPED — Foundation Models unavailable on this device.

                **Reason:** `isAvailable == false` (possibly: Apple Intelligence not enabled, model not downloaded, or device not eligible).

                **Device:** macOS \(ProcessInfo.processInfo.operatingSystemVersion.majorVersion).\(ProcessInfo.processInfo.operatingSystemVersion.minorVersion).\(ProcessInfo.processInfo.operatingSystemVersion.patchVersion)

                **Timestamp:** \(timestamp)

                **Next steps:** SM-1 must run in the app context (not the test host). When Apple Intelligence is enabled and Foundation Models becomes available, re-run this harness for live measurements.
                """

            try writeReport(skipReport)
            throw XCTSkip("Foundation Models not available on this device.")
        }

        // All three measurement tests.
        try await testLatencyVsInputLength()
        try await testInstructionFollowing()
        try await testLengthCeiling()

        // Assemble final report.
        let formatter = ISO8601DateFormatter()
        let timestamp = formatter.string(from: Date())
        let report = """
            # SM-1 Foundation Models Measurement — RAW Data

            **Status:** Complete — live Foundation Models measurements.

            **Device:** macOS \(ProcessInfo.processInfo.operatingSystemVersion.majorVersion).\(ProcessInfo.processInfo.operatingSystemVersion.minorVersion).\(ProcessInfo.processInfo.operatingSystemVersion.patchVersion)

            **Timestamp:** \(timestamp)

            **Cleanup mode (fixed):** `.styled(.default, .medium, customVocabulary: [])`

            ---

            \(self.latencyReport)

            ---

            \(self.instructionFollowingReport)

            ---

            \(self.ceilingReport)

            ---

            ## Notes

            - **Interpretation pending.** This file contains RAW measured data only. The orchestrator owns `specs/verification-ledger.md` and will tag findings as `[verified]` or `[inferred]` after review.
            - **Latency:** min/p50/max reported in seconds. N=3 runs per size. Timeout: 15s per call.
            - **Instruction-following:** Five short inputs tested for preamble-token detection (Sure/Here/Okay/etc).
            - **Ceiling:** Stepped from 400 to max words until output empties, throws, or times out.
            """

        try writeReport(report)

        // Print summary table to stdout for CI visibility.
        printSummaryTable()
    }

    /// Write the RAW report to specs/sm1-fm-measurements-RAW.md.
    private func writeReport(_ content: String) throws {
        // Resolve path relative to the repo root.
        let testFile = URL(fileURLWithPath: #filePath)
        let repoRoot = testFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let specsDir = repoRoot.appendingPathComponent("specs")
        let reportPath = specsDir.appendingPathComponent("sm1-fm-measurements-RAW.md")

        // Ensure specs/ exists.
        try FileManager.default.createDirectory(at: specsDir, withIntermediateDirectories: true)

        // Write the report.
        try content.write(to: reportPath, atomically: true, encoding: .utf8)
        print("Wrote RAW measurements to: \(reportPath.path)")
    }

    /// Print a summary table to stdout (FileHandle.standardOutput) for CI visibility.
    private func printSummaryTable() {
        let table = """
            ╔════════════════════════════════════════════════════════╗
            ║ SM-1 Foundation Models Measurement — Summary           ║
            ╠════════════════════════════════════════════════════════╣
            ║ Status: LIVE MEASUREMENTS COMPLETED                   ║
            ║                                                         ║
            ║ Axes measured:                                          ║
            ║   ✓ Latency vs input length (10–400 words)            ║
            ║   ✓ Instruction-following (preamble resistance)       ║
            ║   ✓ Length ceiling (truncate/empty/throw)             ║
            ║                                                         ║
            ║ Output: specs/sm1-fm-measurements-RAW.md              ║
            ╚════════════════════════════════════════════════════════╝
            """

        if let data = (table + "\n").data(using: .utf8) {
            FileHandle.standardOutput.write(data)
        }

        // Attach to the test report.
        let attachment = XCTAttachment(string: table)
        attachment.name = "fm-study-summary.txt"
        add(attachment)
    }
}
