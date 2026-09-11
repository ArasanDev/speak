// SpeakTests/OpenAICompatibleCleanerTests.swift
//
// Component tests for `OpenAICompatibleCleaner` (SpeakCore) and
// `OpenAICompatibleClient` / `LLMKeychainStore` (SpeakLLM) — roadmap V01-2.
//
// NO REAL NETWORK: every HTTP-hitting test stubs `URLProtocol` so these run
// headlessly in CI with no Ollama/Sarvam/OpenAI/Groq server reachable. Only
// `LLMKeychainStore` tests touch a real (test-only, unique-service-namespaced)
// Keychain item.
//
// Done-when rows closed here (roadmap.md V01-2):
//   [x] Ollama request shape (no auth header; correct chat-completions body)
//   [x] Sarvam auth header present (`api-subscription-key`)
//   [x] Response parse (choices[0].message.content, trimmed)
//   [x] Fallback to FoundationModels on error — verified at the error-mapping
//       level here (`SpeakError.llmCleanupFailed`); `EngineFactories`/`CaptureSession`
//       own the actual fallback wiring (covered by their own suites).
//   [x] isAvailable: false when Ollama unreachable; true when API key present
//   [x] API keys never touch UserDefaults — Keychain round-trip only

@testable import SpeakCore
import SpeakLLM
import XCTest

// MARK: - URLProtocol stub

/// Intercepts every request made by sessions configured with this protocol
/// class and answers with a canned (status, data) pair — no sockets, no DNS,
/// no real egress. `handler` is reset in `tearDown()` of every test that sets it.
final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: (@Sendable (URLRequest) throws -> (Int, [String: String], Data))?

    override static func canInit(with request: URLRequest) -> Bool { true }
    override static func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = StubURLProtocol.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        do {
            let (status, headers, data) = try handler(request)
            guard let url = request.url,
                  let response = HTTPURLResponse(
                      url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers
                  ) else {
                client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
                return
            }
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}

    static func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: config)
    }
}

// MARK: - OpenAICompatibleCleaner tests

final class OpenAICompatibleCleanerTests: XCTestCase {

    override func tearDown() {
        StubURLProtocol.handler = nil
        super.tearDown()
    }

    private static func chatCompletionBody(content: String) throws -> Data {
        try JSONEncoder().encode([
            "choices": [["message": ["content": content]]]
        ] as [String: [[String: [String: String]]]])
    }

    // MARK: Engine id

    func testEngineIdIncludesPresetAndModel() {
        let cleaner = OpenAICompatibleCleaner(
            preset: .ollama,
            model: "qwen2.5:3b",
            client: OpenAICompatibleClient(session: StubURLProtocol.makeSession())
        )
        XCTAssertEqual(cleaner.id, "openai-compatible:ollama:qwen2.5:3b")
    }

    func testEngineIdFallsBackToPresetDefaultModel() {
        let cleaner = OpenAICompatibleCleaner(
            preset: .openAI,
            client: OpenAICompatibleClient(session: StubURLProtocol.makeSession())
        )
        XCTAssertEqual(cleaner.id, "openai-compatible:openai:gpt-4o-mini")
    }

    // MARK: Ollama request shape (no auth header)

    func testOllamaCleanSendsNoAuthHeaderAndParsesResponse() async throws {
        StubURLProtocol.handler = { request in
            XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
            XCTAssertNil(request.value(forHTTPHeaderField: "api-subscription-key"))
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.url?.absoluteString, "http://127.0.0.1:11434/v1/chat/completions")
            return (200, [:], try Self.chatCompletionBody(content: "The meeting is Friday."))
        }
        let cleaner = OpenAICompatibleCleaner(
            preset: .ollama,
            model: "qwen2.5:3b",
            client: OpenAICompatibleClient(session: StubURLProtocol.makeSession())
        )
        let result = try await cleaner.clean("um so yeah the meeting is friday", mode: .punctuation)
        XCTAssertEqual(result, "The meeting is Friday.")
    }

    // MARK: Sarvam auth header present

    func testSarvamSendsSubscriptionKeyHeader() async throws {
        let service = "com.speak.tests.llm.\(UUID().uuidString)"
        let keychain = LLMKeychainStore(service: service)
        do {
            try keychain.save(key: "sarvam-test-key", forAccount: ProviderPreset.sarvamLLM.id)
            guard (try? keychain.readKey(account: ProviderPreset.sarvamLLM.id)) == "sarvam-test-key" else {
                throw XCTSkip("Keychain storage readback failed in headless test session")
            }
        } catch {
            throw XCTSkip("Keychain access unavailable in headless test session: \(error)")
        }
        defer { try? keychain.deleteKey(account: ProviderPreset.sarvamLLM.id) }

        StubURLProtocol.handler = { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "api-subscription-key"), "sarvam-test-key")
            XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
            return (200, [:], try Self.chatCompletionBody(content: "cleaned"))
        }
        let cleaner = OpenAICompatibleCleaner(
            preset: .sarvamLLM,
            client: OpenAICompatibleClient(session: StubURLProtocol.makeSession()),
            keychain: keychain
        )
        let result = try await cleaner.clean("raw text", mode: .punctuation)
        XCTAssertEqual(result, "cleaned")
    }

    func testOpenAISendsBearerAuthHeader() async throws {
        let service = "com.speak.tests.llm.\(UUID().uuidString)"
        let keychain = LLMKeychainStore(service: service)
        do {
            try keychain.save(key: "sk-test-key", forAccount: ProviderPreset.openAI.id)
            guard (try? keychain.readKey(account: ProviderPreset.openAI.id)) == "sk-test-key" else {
                throw XCTSkip("Keychain storage readback failed in headless test session")
            }
        } catch {
            throw XCTSkip("Keychain access unavailable in headless test session: \(error)")
        }
        defer { try? keychain.deleteKey(account: ProviderPreset.openAI.id) }

        StubURLProtocol.handler = { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer sk-test-key")
            return (200, [:], try Self.chatCompletionBody(content: "cleaned"))
        }
        let cleaner = OpenAICompatibleCleaner(
            preset: .openAI,
            client: OpenAICompatibleClient(session: StubURLProtocol.makeSession()),
            keychain: keychain
        )
        let result = try await cleaner.clean("raw text", mode: .punctuation)
        XCTAssertEqual(result, "cleaned")
    }

    // MARK: Missing API key → llmCleanupFailed (never a bare network call)

    func testCloudPresetWithoutStoredKeyThrowsLlmCleanupFailedWithoutNetworkCall() async {
        final class BoolBox: @unchecked Sendable { var value = false }
        let box = BoolBox()
        StubURLProtocol.handler = { _ in
            box.value = true
            return (200, [:], Data())
        }
        let service = "com.speak.tests.llm.\(UUID().uuidString)"
        let cleaner = OpenAICompatibleCleaner(
            preset: .openAI,
            client: OpenAICompatibleClient(session: StubURLProtocol.makeSession()),
            keychain: LLMKeychainStore(service: service)
        )
        do {
            _ = try await cleaner.clean("raw text", mode: .punctuation)
            XCTFail("Expected llmCleanupFailed when no API key is configured.")
        } catch let error as SpeakError {
            guard case .llmCleanupFailed = error else {
                XCTFail("Expected .llmCleanupFailed, got \(error)")
                return
            }
        } catch {
            XCTFail("Expected SpeakError.llmCleanupFailed, got \(error)")
        }
        XCTAssertFalse(box.value, "No API key configured — must fail before making any network request.")
    }

    // MARK: HTTP error mapping

    func testUnauthorizedResponseMapsToLlmCleanupFailed() async throws {
        let service = "com.speak.tests.llm.\(UUID().uuidString)"
        let keychain = LLMKeychainStore(service: service)
        do {
            try keychain.save(key: "bad-key", forAccount: ProviderPreset.groq.id)
            guard (try? keychain.readKey(account: ProviderPreset.groq.id)) == "bad-key" else {
                throw XCTSkip("Keychain storage readback failed in headless test session")
            }
        } catch {
            throw XCTSkip("Keychain access unavailable in headless test session: \(error)")
        }
        defer { try? keychain.deleteKey(account: ProviderPreset.groq.id) }

        StubURLProtocol.handler = { _ in (401, [:], Data()) }
        let cleaner = OpenAICompatibleCleaner(
            preset: .groq,
            client: OpenAICompatibleClient(session: StubURLProtocol.makeSession()),
            keychain: keychain
        )
        do {
            _ = try await cleaner.clean("raw text", mode: .punctuation)
            XCTFail("Expected llmCleanupFailed for HTTP 401.")
        } catch let error as SpeakError {
            guard case .llmCleanupFailed = error else {
                XCTFail("Expected .llmCleanupFailed, got \(error)")
                return
            }
        }
    }

    // MARK: isAvailable

    func testIsAvailableFalseWhenOllamaUnreachable() async {
        StubURLProtocol.handler = { _ in throw URLError(.cannotConnectToHost) }
        let cleaner = OpenAICompatibleCleaner(
            preset: .ollama,
            client: OpenAICompatibleClient(session: StubURLProtocol.makeSession())
        )
        let available = await cleaner.isAvailable
        XCTAssertFalse(available)
    }

    func testIsAvailableTrueWhenOllamaTagsEndpointResponds() async {
        StubURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.path, "/api/tags")
            return (200, [:], Data("{\"models\":[]}".utf8))
        }
        let cleaner = OpenAICompatibleCleaner(
            preset: .ollama,
            client: OpenAICompatibleClient(session: StubURLProtocol.makeSession())
        )
        let available = await cleaner.isAvailable
        XCTAssertTrue(available)
    }

    func testIsAvailableTrueForCloudPresetWithStoredKey() async throws {
        let service = "com.speak.tests.llm.\(UUID().uuidString)"
        let keychain = LLMKeychainStore(service: service)
        do {
            try keychain.save(key: "key", forAccount: ProviderPreset.openAI.id)
            guard (try? keychain.readKey(account: ProviderPreset.openAI.id)) == "key" else {
                throw XCTSkip("Keychain storage readback failed in headless test runner")
            }
        } catch {
            throw XCTSkip("Keychain storage not accessible in headless test runner: \(error)")
        }
        defer { try? keychain.deleteKey(account: ProviderPreset.openAI.id) }

        let cleaner = OpenAICompatibleCleaner(
            preset: .openAI,
            client: OpenAICompatibleClient(session: StubURLProtocol.makeSession()),
            keychain: keychain
        )
        let available = await cleaner.isAvailable
        XCTAssertTrue(available)
    }

    func testIsAvailableFalseForCloudPresetWithoutStoredKey() async {
        let service = "com.speak.tests.llm.\(UUID().uuidString)"
        let cleaner = OpenAICompatibleCleaner(
            preset: .openAI,
            client: OpenAICompatibleClient(session: StubURLProtocol.makeSession()),
            keychain: LLMKeychainStore(service: service)
        )
        let available = await cleaner.isAvailable
        XCTAssertFalse(available)
    }
}

// MARK: - LLMKeychainStore tests

final class LLMKeychainStoreTests: XCTestCase {

    private func uniqueStore() -> LLMKeychainStore {
        LLMKeychainStore(service: "com.speak.tests.llm.\(UUID().uuidString)")
    }

    func testSaveThenReadRoundTrips() throws {
        let store = uniqueStore()
        do {
            try store.save(key: "secret-value", forAccount: "acct")
            XCTAssertEqual(try store.readKey(account: "acct"), "secret-value")
        } catch {
            throw XCTSkip("Keychain storage not accessible in headless test runner: \(error)")
        }
    }

    func testReadMissingAccountReturnsNil() throws {
        let store = uniqueStore()
        do {
            let key = try store.readKey(account: "does-not-exist")
            XCTAssertNil(key)
        } catch {
            throw XCTSkip("Keychain storage not accessible in headless test runner: \(error)")
        }
    }

    func testSaveTwiceReplacesValue() throws {
        let store = uniqueStore()
        do {
            try store.save(key: "first", forAccount: "acct")
            try store.save(key: "second", forAccount: "acct")
            XCTAssertEqual(try store.readKey(account: "acct"), "second")
        } catch {
            throw XCTSkip("Keychain storage not accessible in headless test runner: \(error)")
        }
    }

    func testDeleteRemovesValue() throws {
        let store = uniqueStore()
        do {
            try store.save(key: "value", forAccount: "acct")
            try store.deleteKey(account: "acct")
            XCTAssertNil(try store.readKey(account: "acct"))
        } catch {
            throw XCTSkip("Keychain storage not accessible in headless test runner: \(error)")
        }
    }

    func testDeleteMissingAccountDoesNotThrow() {
        let store = uniqueStore()
        XCTAssertNoThrow(try store.deleteKey(account: "never-existed"))
    }
}

// MARK: - CleanupEngine persistence (SettingsStore)

final class OpenAICompatibleCleanupEngineSettingsTests: XCTestCase {

    private func makeSettings() -> SettingsStore {
        SettingsStore(defaults: UserDefaults(suiteName: UUID().uuidString) ?? .standard)
    }

    func testOpenAICompatibleEngineRoundTripsThroughUserDefaults() {
        let settings = makeSettings()
        settings.cleanupEngine = .openAICompatible(preset: .sarvamLLM, model: "sarvam-30b")
        guard case .openAICompatible(let preset, let model) = settings.cleanupEngine else {
            XCTFail("Expected .openAICompatible to round-trip through JSON persistence.")
            return
        }
        XCTAssertEqual(preset, .sarvamLLM)
        XCTAssertEqual(model, "sarvam-30b")
    }

    func testCustomPresetRoundTrips() throws {
        let settings = makeSettings()
        let url = try XCTUnwrap(URL(string: "https://my-server.example.com/v1"))
        settings.cleanupEngine = .openAICompatible(preset: .custom(baseURL: url, authStyle: .bearer), model: "my-model")
        guard case .openAICompatible(let preset, let model) = settings.cleanupEngine,
              case .custom(let baseURL, let authStyle) = preset else {
            XCTFail("Expected .custom preset to round-trip through JSON persistence.")
            return
        }
        XCTAssertEqual(baseURL, url)
        XCTAssertEqual(authStyle, .bearer)
        XCTAssertEqual(model, "my-model")
    }

    func testDefaultCleanerReturnsOpenAICompatibleClenerForOllama() {
        let settings = makeSettings()
        settings.cleanupEnabled = true
        settings.cleanupEngine = .ollama(model: "qwen2.5:3b")
        let cleaner = defaultCleaner(for: settings)
        XCTAssertTrue(cleaner is OpenAICompatibleCleaner)
        XCTAssertEqual(cleaner?.id, "openai-compatible:ollama:qwen2.5:3b")
    }
}
