// SpeakTests/DebugHarnessRegressionTests.swift
//
// Regression coverage for two defects found during live runtime validation:
//
// 1. FixtureAudioProducer.helloSpeechFixture() resolved to a stale path
//    (`<root>/SpeakTests/Fixtures/` — pre-restructure layout), so the
//    `--debug-open simulate-dictation` harness silently aborted with
//    "hello_speech.caf not found". The resolver is `#filePath`-anchored, so
//    a source-tree move breaks it without any compile error — this test
//    fails loudly instead.
//
// 2. LocalAPIKeyStore regenerated the API key on EVERY currentKey() call
//    when the stored Keychain item was unreadable-but-present (dev rebuilds
//    change the binary cdhash → the item's ACL rejects reads while
//    SecItemAdd still reports errSecDuplicateItem). Since validate() calls
//    currentKey(), every Bearer check compared against a fresh random key —
//    the inference server 401'd every request in that state. The fix caches
//    the key in memory for the launch; these tests pin the contract.

@testable import SpeakCore
@testable import SpeakLLM
import XCTest

// MARK: - Fixture resolution

final class FixtureAudioProducerResolutionTests: XCTestCase {

    /// The simulate-dictation harness depends on this resolving to a real
    /// file whenever tests run from a source checkout.
    func testHelloSpeechFixtureResolvesToExistingFile() throws {
        #if DEBUG
        let url = try XCTUnwrap(
            FixtureAudioProducer.helloSpeechFixture(),
            "helloSpeechFixture() returned nil — the #filePath-anchored walk no "
                + "longer lands on Speak/Tests/SpeakTests/Fixtures/hello_speech.caf."
        )
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: url.path),
            "Resolved fixture path does not exist: \(url.path)"
        )
        XCTAssertEqual(url.lastPathComponent, "hello_speech.caf")
        #else
        throw XCTSkip("FixtureAudioProducer is DEBUG-only")
        #endif
    }
}

// MARK: - Inference API key stability

final class LocalAPIKeyStoreStabilityTests: XCTestCase {

    /// Once issued, the key must be stable for the life of the store —
    /// validate() must not be able to rotate it out from under a client.
    func testCurrentKeyIsStableAcrossCalls() async {
        let store = LocalAPIKeyStore()
        let first = await store.currentKey()
        let second = await store.currentKey()
        XCTAssertEqual(first, second, "currentKey() must not regenerate once issued")
        XCTAssertTrue(first.hasPrefix("sk-speak-"))
    }

    /// The exact failure mode observed live: a key issued to a client must
    /// pass validate() on subsequent requests even if Keychain persistence
    /// is degraded.
    func testValidateAcceptsIssuedKey() async {
        let store = LocalAPIKeyStore()
        let key = await store.currentKey()
        let accepted = await store.validate(authorizationHeader: "Bearer \(key)")
        XCTAssertTrue(accepted, "validate() must accept the key currentKey() issued")
    }

    func testValidateRejectsBogusKey() async {
        let store = LocalAPIKeyStore()
        _ = await store.currentKey()
        let rejected = await store.validate(authorizationHeader: "Bearer sk-speak-not-a-real-key")
        XCTAssertFalse(rejected)
    }
}
