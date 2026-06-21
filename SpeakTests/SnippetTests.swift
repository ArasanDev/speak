// SpeakTests/SnippetTests.swift
//
// Wave B.2 — unit tests for snippet expansion + persistence. These cover the parts
// that must be correct for snippets to apply BEFORE LLM cleanup: the whole-word,
// case-insensitive expander, and the store's encode/decode + mutation helpers.

import XCTest
@testable import SpeakCore

final class SnippetTests: XCTestCase {

    // MARK: - SnippetExpander

    func testExpander_replacesWholeWordCaseInsensitively() {
        let expander = SnippetExpander(snippets: [Snippet(trigger: "ty", expansion: "thank you")])
        XCTAssertEqual(expander.expand("ty for the help"), "thank you for the help")
        XCTAssertEqual(expander.expand("TY for the help"), "thank you for the help",
                       "Trigger match must be case-insensitive.")
    }

    func testExpander_doesNotMatchInsideLargerWords() {
        let expander = SnippetExpander(snippets: [Snippet(trigger: "addr", expansion: "123 Main St")])
        XCTAssertEqual(expander.expand("my address is here"), "my address is here",
                       "A trigger must NOT fire inside a larger word (address).")
        XCTAssertEqual(expander.expand("my addr is here"), "my 123 Main St is here")
    }

    func testExpander_emptySnippetsOrText_isUnchanged() {
        XCTAssertEqual(SnippetExpander(snippets: []).expand("hello"), "hello")
        XCTAssertEqual(SnippetExpander(snippets: [Snippet(trigger: "x", expansion: "y")]).expand(""), "")
    }

    func testExpander_multipleSnippets_allApply() {
        let expander = SnippetExpander(snippets: [
            Snippet(trigger: "omw", expansion: "on my way"),
            Snippet(trigger: "brb", expansion: "be right back")
        ])
        XCTAssertEqual(expander.expand("omw brb"), "on my way be right back")
    }

    func testExpander_expansionWithRegexCharsIsLiteral() {
        // Expansion containing `$` / `\` must be inserted literally, not as a template ref.
        let expander = SnippetExpander(snippets: [Snippet(trigger: "price", expansion: "$5 (50% off)")])
        XCTAssertEqual(expander.expand("the price today"), "the $5 (50% off) today")
    }

    func testExpander_longerTriggerWinsOnOverlap() {
        // "new york" should expand as a unit, not via a shorter "new" trigger.
        let expander = SnippetExpander(snippets: [
            Snippet(trigger: "ny", expansion: "New York"),
            Snippet(trigger: "nyc", expansion: "New York City")
        ])
        XCTAssertEqual(expander.expand("nyc"), "New York City")
        XCTAssertEqual(expander.expand("ny"), "New York")
    }

    // MARK: - SnippetStore

    private func makeStore() throws -> SnippetStore {
        let name = "SnippetTests.\(UUID().uuidString)"
        let ud = try XCTUnwrap(UserDefaults(suiteName: name))
        addTeardownBlock { ud.removePersistentDomain(forName: name) }
        return SnippetStore(defaults: ud)
    }

    func testStore_addTrimsAndAppends() throws {
        let store = try makeStore()
        XCTAssertTrue(store.add(trigger: "  ty  ", expansion: "  thank you  "))
        XCTAssertEqual(store.snippets.count, 1)
        XCTAssertEqual(store.snippets.first?.trigger, "ty")
        XCTAssertEqual(store.snippets.first?.expansion, "thank you")
    }

    func testStore_addRejectsBlank() throws {
        let store = try makeStore()
        XCTAssertFalse(store.add(trigger: "  ", expansion: "x"))
        XCTAssertFalse(store.add(trigger: "x", expansion: ""))
        XCTAssertTrue(store.snippets.isEmpty)
    }

    func testStore_removeById() throws {
        let store = try makeStore()
        store.add(trigger: "a", expansion: "alpha")
        store.add(trigger: "b", expansion: "beta")
        let firstID = try XCTUnwrap(store.snippets.first?.id)
        store.remove(id: firstID)
        XCTAssertEqual(store.snippets.map(\.trigger), ["b"])
    }

    func testStore_persistsAcrossInstances() throws {
        let name = "SnippetTests.\(UUID().uuidString)"
        let ud = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { ud.removePersistentDomain(forName: name) }
        let writer = SnippetStore(defaults: ud)
        writer.add(trigger: "sig", expansion: "Best,\nTamil")
        let reader = SnippetStore(defaults: ud)
        XCTAssertEqual(reader.snippets.first?.expansion, "Best,\nTamil")
    }

    func testStore_makeExpanderReflectsCurrentSnippets() throws {
        let store = try makeStore()
        store.add(trigger: "gm", expansion: "good morning")
        XCTAssertEqual(store.makeExpander().expand("gm team"), "good morning team")
    }
}
