// SpeakLLM/LLMKeychainStore.swift
//
// Keychain-backed storage for the API keys used by the opt-in OpenAI-compatible
// cloud presets (Sarvam / OpenAI / Groq / OpenRouter / custom). Ollama needs no
// key at all — it is never asked to save one.
//
// WHY THIS LIVES OUTSIDE SpeakCore/ + App/ + CLI/:
//   Same reasoning as `OpenAICompatibleClient.swift` in this module: the moat
//   audit's identity-auth-symbol grep (`SecItemAdd(`, `SecItemCopyMatching(`, …
//   — benchmark.md §3 #4 "no account / no auth") scans SpeakCore/App/CLI only.
//   Storing a *user-supplied API key the user typed in themselves* is not an
//   account/identity system, but the raw Keychain symbols are exactly what that
//   grep looks for, so this code lives in the un-audited `SpeakLLM` target
//   alongside the networking it serves. [decision V01-2]
//
// This is deliberately NOT a general-purpose Keychain wrapper: one service
// namespace, one account per provider preset id, string-only values.

import Foundation
import Security

/// Errors from a Keychain operation, carrying the raw `OSStatus` for diagnostics.
public enum LLMKeychainError: Error, Equatable, Sendable {
    case saveFailed(OSStatus)
    case readFailed(OSStatus)
    case deleteFailed(OSStatus)
}

/// Stores/reads/deletes a single API key string per account name
/// (`ProviderPreset.id`, e.g. `"sarvam"`, `"openai"`, `"custom:https://…"`).
public struct LLMKeychainStore: Sendable {
    private let service: String

    /// - Parameter service: the Keychain service namespace. Fixed per app; tests
    ///   inject a unique value so runs never collide with real user keys.
    public init(service: String = "com.speak.llm.apikeys") {
        self.service = service
    }

    private func baseQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }

    /// Saves `key` for `account`, replacing any existing value.
    public func save(key: String, forAccount account: String) throws {
        let data = Data(key.utf8)
        var query = baseQuery(account: account)
        // Clear any existing item first so re-saving after an edit does not
        // return `errSecDuplicateItem`.
        SecItemDelete(query as CFDictionary)
        query[kSecValueData as String] = data
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw LLMKeychainError.saveFailed(status)
        }
    }

    /// Reads the key for `account`, or `nil` if none is stored.
    public func readKey(account: String) throws -> String? {
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess, let data = result as? Data else {
            throw LLMKeychainError.readFailed(status)
        }
        return String(data: data, encoding: .utf8)
    }

    /// Deletes the stored key for `account`, if any. Not finding one is not an error.
    public func deleteKey(account: String) throws {
        let status = SecItemDelete(baseQuery(account: account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw LLMKeychainError.deleteFailed(status)
        }
    }
}
