// Speak/SpeakCore/AgentBridge/TagRegistry.swift
//
// Central thread-safe registry actor tracking all active Spoken Tags (@tag).
// Manages dynamic registration, tag resolution, and capability checks for agents and plugins.

import Foundation

/// Lightweight metadata representation of a registered tag for UI lists and autocomplete.
public struct TagMetadata: Sendable, Equatable, Identifiable {
    public var id: String { tagName }
    public let tagName: String
    public let tagKind: TagKind
    public let description: String
    public let capabilities: [TagCapability]

    public init(tagName: String, tagKind: TagKind, description: String, capabilities: [TagCapability]) {
        // Guarantee canonical @ prefix
        self.tagName = tagName.hasPrefix("@") ? tagName : "@" + tagName
        self.tagKind = tagKind
        self.description = description
        self.capabilities = capabilities
    }
}

/// Actor managing the global registry of invokable tags.
public actor TagRegistry {
    public static let shared = TagRegistry()

    private var adapters: [String: any PluginTagAdapter] = [:]

    public init() {}

    /// Registers standard built-in tag adapters (@Claude, @terminal, @builder-qa, @github).
    public func registerDefaults() {
        register(DefaultClaudeTagAdapter())
        register(DefaultTerminalTagAdapter())
        register(DefaultBuilderQATagAdapter())
        register(DefaultGitHubTagAdapter())
    }

    /// Normalizes a tag string to canonical lowercase `@name` format.
    public static func normalizeTagName(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if trimmed.hasPrefix("@") {
            return trimmed
        }
        return "@" + trimmed
    }

    /// Registers a new plugin or agent tag adapter.
    public func register(_ adapter: any PluginTagAdapter) {
        let key = Self.normalizeTagName(adapter.tagName)
        adapters[key] = adapter
    }

    /// Unregisters a tag by name.
    public func unregister(tagName: String) {
        let key = Self.normalizeTagName(tagName)
        adapters.removeValue(forKey: key)
    }

    /// Looks up an adapter by tag name (case-insensitive, optional @ prefix).
    public func lookup(tagName: String) -> (any PluginTagAdapter)? {
        let key = Self.normalizeTagName(tagName)
        return adapters[key]
    }

    /// Returns metadata for all currently registered tags.
    public func allTags() -> [TagMetadata] {
        adapters.values.map { adapter in
            TagMetadata(
                tagName: adapter.tagName,
                tagKind: adapter.tagKind,
                description: adapter.description,
                capabilities: adapter.capabilities
            )
        }.sorted { $0.tagName < $1.tagName }
    }
}
