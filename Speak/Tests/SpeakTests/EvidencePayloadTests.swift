// SpeakTests/EvidencePayloadTests.swift
//
// Unit tests for EvidencePayload, TaskChecklistItem, and CodeDiffBlock.

@testable import SpeakCore
import XCTest

final class EvidencePayloadTests: XCTestCase {

    func testEvidencePayloadJSONRoundTrip() throws {
        let checklist = [
            TaskChecklistItem(id: "t1", title: "Inspect AudioCapture.swift", status: .done),
            TaskChecklistItem(id: "t2", title: "Run unit tests", status: TaskChecklistStatus.inProgress)
        ]
        let diffs = [
            CodeDiffBlock(file: "AudioCapture.swift", patch: "+ input.removeTap(onBus: bus)")
        ]
        let payload = EvidencePayload(
            summary: "Tap guard added successfully.",
            checklist: checklist,
            images: ["/tmp/test.png"],
            videos: ["/tmp/test.mp4"],
            diffs: diffs,
            audioPath: "/tmp/audio.caf"
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(payload)
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(EvidencePayload.self, from: data)

        XCTAssertEqual(decoded, payload)
        XCTAssertEqual(decoded.summary, "Tap guard added successfully.")
        XCTAssertEqual(decoded.checklist.count, 2)
        XCTAssertEqual(decoded.checklist[0].status, TaskChecklistStatus.done)
        XCTAssertEqual(decoded.checklist[1].status, TaskChecklistStatus.inProgress)
        XCTAssertEqual(decoded.diffs.count, 1)
        XCTAssertEqual(decoded.diffs[0].file, "AudioCapture.swift")
        XCTAssertEqual(decoded.audioPath, "/tmp/audio.caf")
    }
}
