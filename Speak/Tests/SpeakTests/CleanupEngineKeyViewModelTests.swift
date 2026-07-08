// SpeakTests/CleanupEngineKeyViewModelTests.swift
//
// Unit tests for `CleanupEngineKeyViewModel` (App/Settings/CleanupEngineSheet.swift)
// — the Keychain-backed API key-entry state for the cloud OpenAI-compatible
// cleanup presets (V01-2 follow-up).
//
// ISOLATION CONTRACT: every test uses a unique `LLMKeychainStore(service:)`
// namespace (same pattern as `LLMKeychainStoreTests` in
// OpenAICompatibleCleanerTests.swift) so runs never collide with real user
// keys or each other.

@testable import Speak
import SpeakCore
import SpeakLLM
import XCTest

@available(macOS 26.0, *)
@MainActor
final class CleanupEngineKeyViewModelTests: XCTestCase {

    private func uniqueStore() -> LLMKeychainStore {
        LLMKeychainStore(service: "com.speak.tests.cleanupenginekeyvm.\(UUID().uuidString)")
    }

    func testInitialStateHasNoStoredKey() {
        let viewModel = CleanupEngineKeyViewModel(preset: .openAI, keychainStore: uniqueStore())
        viewModel.refresh()
        XCTAssertFalse(viewModel.hasStoredKey)
        XCTAssertEqual(viewModel.keyText, "")
    }

    func testCanSaveIsFalseForBlankOrWhitespaceOnlyText() {
        let viewModel = CleanupEngineKeyViewModel(preset: .openAI, keychainStore: uniqueStore())
        XCTAssertFalse(viewModel.canSave)
        viewModel.keyText = "   "
        XCTAssertFalse(viewModel.canSave)
        viewModel.keyText = "sk-test"
        XCTAssertTrue(viewModel.canSave)
    }

    func testSavePersistsKeyAndClearsFieldFromMemory() throws {
        let store = uniqueStore()
        let viewModel = CleanupEngineKeyViewModel(preset: .sarvamLLM, keychainStore: store)
        viewModel.keyText = "secret-key-123"

        viewModel.save()

        XCTAssertEqual(viewModel.keyText, "", "key text must not linger in memory after save")
        XCTAssertTrue(viewModel.hasStoredKey)
        XCTAssertEqual(try store.readKey(account: ProviderPreset.sarvamLLM.id), "secret-key-123")
    }

    func testSaveIgnoredWhenTextIsBlank() throws {
        let store = uniqueStore()
        let viewModel = CleanupEngineKeyViewModel(preset: .groq, keychainStore: store)
        viewModel.keyText = "   "

        viewModel.save()

        XCTAssertFalse(viewModel.hasStoredKey)
        XCTAssertNil(try store.readKey(account: ProviderPreset.groq.id))
    }

    func testSaveTwiceReplacesStoredValue() throws {
        let store = uniqueStore()
        let viewModel = CleanupEngineKeyViewModel(preset: .openRouter, keychainStore: store)

        viewModel.keyText = "first-key"
        viewModel.save()
        viewModel.keyText = "second-key"
        viewModel.save()

        XCTAssertEqual(try store.readKey(account: ProviderPreset.openRouter.id), "second-key")
    }

    func testClearRemovesStoredKey() throws {
        let store = uniqueStore()
        let viewModel = CleanupEngineKeyViewModel(preset: .openAI, keychainStore: store)
        viewModel.keyText = "to-be-removed"
        viewModel.save()
        XCTAssertTrue(viewModel.hasStoredKey)

        viewModel.clear()

        XCTAssertFalse(viewModel.hasStoredKey)
        XCTAssertNil(try store.readKey(account: ProviderPreset.openAI.id))
    }

    func testClearWithNoStoredKeyDoesNotError() {
        let viewModel = CleanupEngineKeyViewModel(preset: .openAI, keychainStore: uniqueStore())

        viewModel.clear()

        XCTAssertFalse(viewModel.hasStoredKey)
        XCTAssertNil(viewModel.errorMessage)
    }

    func testRefreshReflectsPreExistingKeychainState() throws {
        let store = uniqueStore()
        try store.save(key: "pre-existing", forAccount: ProviderPreset.openAI.id)
        let viewModel = CleanupEngineKeyViewModel(preset: .openAI, keychainStore: store)

        viewModel.refresh()

        XCTAssertTrue(viewModel.hasStoredKey)
        XCTAssertEqual(viewModel.keyText, "", "refresh must never populate keyText with the stored secret")
    }
}
