// SpeakTests/HistoryCleaningEvalTests.swift
//
// Reference-free scoring of the AI cleaning pass, split into two tiers:
//
//   1. Deterministic unit tests for `CleaningQualityScorer` — run in normal
//      `make test`, no database, no live model.
//   2. A gated history eval (`SPEAK_HISTORY_EVAL=1`) that reads the production
//      `history.sqlite` raw→cleaned pairs and reports content-retention stats.
//      This is the "use history to evaluate model performance" gate.
//
// The gated test mirrors `EvalHarnessTests.testLiveFoundationModelsEvaluation`:
// stdout is written directly (via FileHandle.standardOutput) because XCTest's
// logging is unsuitable for tabular data; results are also attached as XCTAttachments.

@testable import SpeakCore
import Foundation
import XCTest

@available(macOS 26.0, *)
final class HistoryCleaningEvalTests: XCTestCase {

    // MARK: - Deterministic unit tests (run in `make test`)

    func testFillerStrippedTokensRemovesOnlyUnambiguousFillers() {
        let raw = "um so I think we should uh meet on Tuesday"
        let stripped = SpeakCore.fillerStrippedTokens(raw)
        XCTAssertTrue(stripped.contains("so"), "Real words must be retained.")
        XCTAssertTrue(stripped.contains("think"), "Real words must be retained.")
        XCTAssertFalse(stripped.contains("um"), "Single-token filler must be stripped.")
        XCTAssertFalse(stripped.contains("uh"), "Single-token filler must be stripped.")
    }

    func testContentRetentionHighWhenCleanupPreservesWords() {
        // Only fillers and punctuation change; every meaningful word survives.
        let raw = "um I think we should meet on tuesday maybe to go over the budget"
        let cleaned = "I think we should meet on Tuesday to go over the budget."
        let report = SpeakCore.scoreCleaning(raw: raw, cleaned: cleaned)
        XCTAssertGreaterThanOrEqual(report.contentRetention, 0.80, "Over-editing should not be flagged.")
    }

    func testContentRetentionLowWhenCleanupOverEdits() {
        // The model condensed and dropped words — the over-editing failure mode.
        let raw = "I think we should meet on tuesday maybe to go over the budget"
        let cleaned = "Let's meet Tuesday."
        let report = SpeakCore.scoreCleaning(raw: raw, cleaned: cleaned)
        XCTAssertLessThan(report.contentRetention, 0.80, "Over-editing must reduce content retention.")
    }

    func testPreambleDetectionRejectsChatter() {
        let raw = "send the file"
        let cleaned = "Here is your cleaned text: Send the file."
        let report = SpeakCore.scoreCleaning(raw: raw, cleaned: cleaned)
        XCTAssertFalse(report.noPreamble, "Assistant chatter must be flagged.")
        XCTAssertTrue(report.failedChecks.contains("noPreamble"))
    }

    func testWholeOutputQuotesRejected() {
        let raw = "hello world"
        let cleaned = "\"hello world\""
        let report = SpeakCore.scoreCleaning(raw: raw, cleaned: cleaned)
        XCTAssertFalse(report.noPreamble, "Whole-output wrapping quotes must be flagged.")
    }

    func testHallucinatedIdentifierDetected() {
        let raw = "capture session"
        let cleaned = "AuthService.swift handles capture session"
        let report = SpeakCore.scoreCleaning(raw: raw, cleaned: cleaned)
        XCTAssertFalse(report.noHallucinatedIdentifiers, "Ungrounded identifier must be flagged.")
    }

    func testLengthRatioGuardsAgainstCondensation() {
        let raw = "we need to add a login button and wire it to the auth service and write a test"
        let cleaned = "Add login button."
        let report = SpeakCore.scoreCleaning(raw: raw, cleaned: cleaned)
        XCTAssertLessThan(report.lengthRatio, 0.60, "A large token drop must be flagged.")
        XCTAssertTrue(report.failedChecks.contains("lengthRatio"))
    }

    func testCleanPairPassesAllGates() {
        let raw = "um send her the file and like let her know it is done"
        let cleaned = "Send her the file and let her know it is done."
        let report = SpeakCore.scoreCleaning(raw: raw, cleaned: cleaned)
        XCTAssertTrue(report.passed, "Expected a clean, faithful edit to pass; failed: \(report.failedChecks)")
    }

    // MARK: - Gated history eval (SPEAK_HISTORY_EVAL=1)

    func testHistoryCleaningQuality() async throws {
        guard ProcessInfo.processInfo.environment["SPEAK_HISTORY_EVAL"] == "1" else {
            throw XCTSkip("Set SPEAK_HISTORY_EVAL=1 (make history-eval) to score real history. Skip ≠ pass.")
        }

        let store = try HistoryStore.makeProductionStore()
        let entries = try await store.recent(limit: 5000)

        let cleanupEntries = entries.filter {
            $0.cleanedText != nil
                && $0.cleanupSeconds > 0
                && $0.engineId.contains("foundation-models")
        }

        guard !cleanupEntries.isEmpty else {
            throw XCTSkip("No Foundation Models cleanup rows found in history. Skip ≠ pass.")
        }

        var reports: [(entry: HistoryEntry, report: CleaningQualityReport)] = []
        for entry in cleanupEntries {
            let report = SpeakCore.scoreCleaning(raw: entry.rawText, cleaned: entry.cleanedText ?? "")
            reports.append((entry, report))
        }

        let total = reports.count
        let passCount = reports.filter { $0.report.passed }.count
        let passRate = Double(passCount) / Double(total)

        let retentions = reports.map { $0.report.contentRetention }
        let lengthRatios = reports.map { $0.report.lengthRatio }
        let meanRetention = retentions.reduce(0, +) / Double(total)
        let p50Retention = percentile50(retentions)
        let p95Retention = percentile95(retentions)

        let retentionFails = reports.filter { $0.report.contentRetention < 0.80 }.count
        let preambleFails = reports.filter { !$0.report.noPreamble }.count
        let hallucinationFails = reports.filter { !$0.report.noHallucinatedIdentifiers }.count
        let fillerFails = reports.filter { !$0.report.fillerRemoved }.count
        let lengthFails = reports.filter { $0.report.lengthRatio < 0.60 }.count

        let summary = """
        History cleaning quality (n=\(total))
          pass rate:            \(String(format: "%.1f%%", passRate * 100))
          mean retention:       \(String(format: "%.3f", meanRetention))
          retention p50 / p95:  \(String(format: "%.3f", p50Retention)) / \(String(format: "%.3f", p95Retention))
          mean length ratio:    \(String(format: "%.3f", lengthRatios.reduce(0, +) / Double(total)))
          failures:
            contentRetention:       \(retentionFails)
            fillerRemoved:          \(fillerFails)
            hallucinatedIdentifier: \(hallucinationFails)
            noPreamble:             \(preambleFails)
            lengthRatio:            \(lengthFails)
        """

        writeStdout(summary + "\n")
        let summaryAttachment = XCTAttachment(string: summary)
        summaryAttachment.name = "history-cleaning-summary"
        add(summaryAttachment)

        // Per-row table for eyeballing the worst over-editing cases first.
        var lines: [String] = ["at\tretention\tlength\tpass\tfailed"]
        let sorted = reports.sorted { $0.report.contentRetention < $1.report.contentRetention }
        for (entry, report) in sorted {
            let at = ISO8601DateFormatter().string(from: entry.createdAt)
            let status = report.passed ? "PASS" : "FAIL"
            let failed = report.failedChecks.joined(separator: ",")
            lines.append("\(at)\t\(String(format: "%.3f", report.contentRetention))\t\(String(format: "%.2f", report.lengthRatio))\t\(status)\t\(failed)")
        }
        let table = lines.joined(separator: "\n")
        writeStdout(table + "\n")
        let tableAttachment = XCTAttachment(string: table)
        tableAttachment.name = "history-cleaning-table"
        add(tableAttachment)

        // The eval reports rather than enforces a hard pass threshold; the
        // regression signal is the deterministic unit tests above. This mirrors
        // EvalHarnessTests, which also reports rather than asserts a pass rate.
    }

    // MARK: - stdout helper

    private func writeStdout(_ text: String) {
        if let data = (text + "\n").data(using: .utf8) {
            FileHandle.standardOutput.write(data)
        }
    }
}
