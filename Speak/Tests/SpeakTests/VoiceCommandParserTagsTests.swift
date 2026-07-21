// SpeakTests/VoiceCommandParserTagsTests.swift
//
// Unit tests for spoken and typed @tag mention extraction in VoiceCommandParser.

@testable import SpeakCore
import XCTest

final class VoiceCommandParserTagsTests: XCTestCase {

    func testExtractLiteralTags() {
        let text = "Hey @Claude please inspect AudioCapture.swift and report back to @channel"
        let tags = VoiceCommandParser.extractTags(from: text)

        XCTAssertEqual(tags.count, 2)
        XCTAssertEqual(tags[0].tag, "@claude")
        XCTAssertEqual(tags[0].kind, TagKind.agent)
        XCTAssertEqual(tags[1].tag, "@channel")
        XCTAssertEqual(tags[1].kind, TagKind.scope)
    }

    func testExtractSpokenTags() {
        let text = "tag claude check the latency and tag terminal run make test"
        let tags = VoiceCommandParser.extractTags(from: text)

        XCTAssertEqual(tags.count, 2)
        XCTAssertEqual(tags[0].tag, "@claude")
        XCTAssertEqual(tags[0].kind, TagKind.agent)
        XCTAssertEqual(tags[1].tag, "@terminal")
        XCTAssertEqual(tags[1].kind, TagKind.plugin)
    }

    func testExtractTeamTags() {
        let text = "Tag qa team to audit the moat privacy rules"
        let tags = VoiceCommandParser.extractTags(from: text)

        XCTAssertEqual(tags.count, 1)
        XCTAssertEqual(tags[0].tag, "@qa-team")
        XCTAssertEqual(tags[0].kind, TagKind.team)
    }
}
