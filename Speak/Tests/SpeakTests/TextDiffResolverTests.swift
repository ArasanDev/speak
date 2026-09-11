// SpeakTests/TextDiffResolverTests.swift
//
// Unit tests for `TextDiffResolver` (real-time stream self-correction resolution).

@testable import SpeakCore
import XCTest

final class TextDiffResolverTests: XCTestCase {

    private var resolver: TextDiffResolver!

    override func setUp() {
        super.setUp()
        resolver = TextDiffResolver()
    }

    override func tearDown() {
        resolver = nil
        super.tearDown()
    }

    func testIdenticalTextHasOnlyNormalTokens() {
        let raw = "hello world"
        let cleaned = "hello world"
        let tokens = resolver.resolve(raw: raw, cleaned: cleaned)

        XCTAssertEqual(tokens.count, 2)
        XCTAssertTrue(tokens.allSatisfy { $0.state == .normal })
    }

    func testSpeechCorrectionIdentifiesCanceledAndInsertedTokens() {
        let raw = "Let us set timeout to 5 seconds"
        let cleaned = "Let us set timeout to 15 seconds"
        let tokens = resolver.resolve(raw: raw, cleaned: cleaned)

        let canceled = tokens.filter { $0.state == .canceled }
        let inserted = tokens.filter { $0.state == .inserted }

        XCTAssertEqual(canceled.map(\.text), ["5"])
        XCTAssertEqual(inserted.map(\.text), ["15"])
    }

    func testEmptyTextResolvesToEmptyTokens() {
        let tokens = resolver.resolve(raw: "", cleaned: "")
        XCTAssertTrue(tokens.isEmpty)
    }
}
