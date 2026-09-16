// SpeakLLM/InferenceServer/LocalAPIKeyStore.swift
//
// Manages the Bearer token for the local inference server.
// Generates a unique API key (sk-speak-<uuid>) on first launch and stores it
// in the macOS Keychain. Follows the LLMKeychainStore service-namespace pattern.
//
// Security model: the key authenticates localhost-only requests. Combined with
// NWParameters.acceptLocalOnly, this provides defense-in-depth — even if the
// loopback binding were somehow bypassed, the key prevents unauthorized access.
//
// No third-party dependencies. Apple frameworks only (AGENTS.md §2.4).

import Foundation
import os
import Security

/// Manages the inference server API key in the macOS Keychain.
///
/// Thread-safe: all Keychain operations are synchronous and stateless.
/// The actor isolation prevents concurrent key generation races.
public actor LocalAPIKeyStore {

    // MARK: - State

    /// In-memory copy of the active key. `currentKey()` and `validate()` call
    /// this first so a Keychain read failure cannot make the key rotate
    /// mid-session (previously every `validate` regenerated → all Bearer
    /// checks failed once the stored item became unreadable, e.g. after a
    /// dev rebuild changed the binary's cdhash relative to the item's ACL).
    private var cachedKey: String?

    // MARK: - Constants

    /// Keychain service identifier for the inference server API key.
    /// [decision: distinct service namespace from LLM provider keys]
    private static let keychainService = "com.speak.inference.apikey"

    /// Keychain account name for the inference server key.
    private static let keychainAccount = "inference-server"

    /// Prefix for generated API keys. Matches the OpenAI key format convention
    /// so developer tools recognize it as a valid key shape.
    /// [decision: sk-speak- prefix identifies speak-generated keys in logs/configs]
    private static let keyPrefix = "sk-speak-"

    /// Logger for key management operations.
    private let logger = Logger(subsystem: "com.speak.app", category: "InferenceServer")

    // MARK: - Public API

    public init() {}

    /// Returns the current API key, generating and storing one if none exists.
    ///
    /// - Returns: The API key string (e.g., "sk-speak-9F8A7B6C-...").
    public func currentKey() -> String {
        if let cachedKey { return cachedKey }
        if let existing = readFromKeychain() {
            cachedKey = existing
            return existing
        }
        let newKey = generateKey()
        if saveToKeychain(newKey) {
            logger.info("Generated new inference API key")
        } else {
            logger.error("Inference API key not persisted — in-memory key is valid for this launch only")
        }
        cachedKey = newKey
        return newKey
    }

    /// Regenerates the API key, replacing the old one.
    ///
    /// All existing tool integrations using the old key will receive 401
    /// until reconfigured with the new key.
    ///
    /// - Returns: The newly generated API key string.
    public func regenerate() -> String {
        deleteFromKeychain()
        cachedKey = nil
        let newKey = generateKey()
        if saveToKeychain(newKey) {
            logger.info("Regenerated inference API key")
        } else {
            logger.error("Regenerated API key not persisted — in-memory key is valid for this launch only")
        }
        cachedKey = newKey
        return newKey
    }

    /// Validates an Authorization header value against the stored key.
    ///
    /// - Parameter authorizationHeader: The raw Authorization header value
    ///   (e.g., "Bearer sk-speak-9F8A7B6C-...").
    /// - Returns: `true` if the header contains a valid Bearer token matching
    ///   the stored key.
    public func validate(authorizationHeader: String?) -> Bool {
        guard let header = authorizationHeader else { return false }

        // Expected format: "Bearer <key>"
        let components = header.split(separator: " ", maxSplits: 1)
        guard components.count == 2 else { return false }
        guard components[0].lowercased() == "bearer" else { return false }

        let providedKey = String(components[1])
        let storedKey = currentKey()

        // Constant-time comparison to prevent timing attacks.
        return constantTimeEquals(providedKey, storedKey)
    }

    // MARK: - Key Generation

    /// Generates a new API key with the speak prefix and a UUID.
    private func generateKey() -> String {
        let uuid = UUID().uuidString
        return "\(Self.keyPrefix)\(uuid)"
    }

    // MARK: - Keychain Operations

    /// Reads the API key from the macOS Keychain.
    private func readFromKeychain() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.keychainService,
            kSecAttrAccount as String: Self.keychainAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let key = String(data: data, encoding: .utf8) else {
            return nil
        }
        return key
    }

    /// Saves the API key to the macOS Keychain.
    ///
    /// - Returns: `true` if the key was persisted. A stale item can occupy the
    ///   (service, account) slot while remaining unreadable to this binary —
    ///   e.g. an item written by a previous dev build whose cdhash no longer
    ///   satisfies the item's access requirement. In that case `SecItemAdd`
    ///   returns `errSecDuplicateItem`; fall back to updating the value, then
    ///   delete-and-recreate, matching LLMKeychainStore's delete-before-add.
    private func saveToKeychain(_ key: String) -> Bool {
        guard let data = key.data(using: .utf8) else { return false }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.keychainService,
            kSecAttrAccount as String: Self.keychainAccount
        ]
        var attributes = query
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly

        var status = SecItemAdd(attributes as CFDictionary, nil)
        if status == errSecDuplicateItem {
            status = SecItemUpdate(
                query as CFDictionary,
                [kSecValueData as String: data] as CFDictionary
            )
            if status != errSecSuccess {
                SecItemDelete(query as CFDictionary)
                status = SecItemAdd(attributes as CFDictionary, nil)
            }
        }
        if status != errSecSuccess {
            logger.error("Failed to save API key to Keychain: status \(status)")
            return false
        }
        return true
    }

    /// Deletes the API key from the macOS Keychain.
    private func deleteFromKeychain() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.keychainService,
            kSecAttrAccount as String: Self.keychainAccount
        ]

        SecItemDelete(query as CFDictionary)
    }

    // MARK: - Security Helpers

    /// Constant-time string comparison to prevent timing side-channel attacks.
    ///
    /// Both strings are compared byte-by-byte regardless of where a mismatch
    /// occurs, ensuring the comparison time does not leak information about
    /// the stored key's content.
    private func constantTimeEquals(_ a: String, _ b: String) -> Bool {
        let aBytes = Array(a.utf8)
        let bBytes = Array(b.utf8)

        guard aBytes.count == bBytes.count else { return false }

        var result: UInt8 = 0
        for i in 0..<aBytes.count {
            result |= aBytes[i] ^ bBytes[i]
        }
        return result == 0
    }
}
