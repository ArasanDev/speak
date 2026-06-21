// SpeakTests/ScratchpadTests.swift
//
// Wave D — unit test for the Scratchpad append helper (paste-failure fallback target).

import XCTest
@testable import Speak

final class ScratchpadTests: XCTestCase {

    private func makeDefaults() throws -> (UserDefaults, String) {
        let name = "ScratchpadTests.\(UUID().uuidString)"
        let ud = try XCTUnwrap(UserDefaults(suiteName: name))
        addTeardownBlock { ud.removePersistentDomain(forName: name) }
        return (ud, name)
    }

    func testAppend_writesToEmpty() throws {
        let (ud, _) = try makeDefaults()
        Scratchpad.append("hello", to: ud)
        XCTAssertEqual(ud.string(forKey: Scratchpad.defaultsKey), "hello")
    }

    func testAppend_separatesWithBlankLine() throws {
        let (ud, _) = try makeDefaults()
        Scratchpad.append("first", to: ud)
        Scratchpad.append("second", to: ud)
        XCTAssertEqual(ud.string(forKey: Scratchpad.defaultsKey), "first\n\nsecond")
    }

    func testAppend_trimsAndIgnoresBlank() throws {
        let (ud, _) = try makeDefaults()
        Scratchpad.append("   ", to: ud)
        XCTAssertNil(ud.string(forKey: Scratchpad.defaultsKey), "Blank input must not write.")
        Scratchpad.append("  kept  ", to: ud)
        XCTAssertEqual(ud.string(forKey: Scratchpad.defaultsKey), "kept")
    }
}
