// SpeakTests/Support/TestStorage.swift
//
// Shared test fixture for filesystem-backed tests.
// Models the TemporaryStorage.withTempDir pattern from Apple's container project.
// Use instead of ad-hoc `FileManager.temporaryDirectory + UUID()` in each test.

import Foundation

enum TestStorage {

    /// Creates a unique temporary directory, passes its URL to `body`, then
    /// removes the directory when `body` returns — even on throw.
    ///
    /// Prefer this over `addTeardownBlock` for tests that only need the temp
    /// path within a single async function body.
    static func withTempDir<T: Sendable>(_ body: @Sendable (URL) async throws -> T) async throws -> T {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("speak-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        return try await body(dir)
    }

    /// Sync variant for non-async test helpers.
    static func withTempDir<T>(_ body: (URL) throws -> T) throws -> T {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("speak-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        return try body(dir)
    }

    /// Returns a unique temporary file URL (does not create any file or directory).
    /// Add an `addTeardownBlock` if the test needs guaranteed cleanup.
    static func tempFileURL(suffix: String = ".tmp") -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("speak-test-\(UUID().uuidString)\(suffix)")
    }

    /// Returns a unique SQLite database URL in the system temp directory.
    static func tempDatabaseURL() -> URL {
        tempFileURL(suffix: ".sqlite")
    }
}
