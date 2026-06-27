// App/History/HistoryViewModel.swift
//
// The `@MainActor ObservableObject` that drives the History window (roadmap P9).
//
// RESPONSIBILITIES:
//   - Loads recent entries from the shared `HistoryStoring` store (the same one
//     `SpeakEngine` writes to on each completed dictation).
//   - Live substring search (delegates to `store.search`).
//   - Clear-all and export-to-file actions.
//
// HONESTY BOUNDARY:
//   The store layer (`HistoryStore`, SQLite) is unit-tested independently
//   (`HistoryStoreTests`). Whether this window renders, the list scrolls, and the
//   export NSSavePanel works is [deferred — needs human verification: §4.5].
//
// THREADING:
//   - `@MainActor` throughout; all `@Published` mutations happen on main.
//   - `HistoryStoring` is a `Sendable` actor (or NullHistoryStore); every call is
//     `await`-ed off the main actor and the result is assigned back on main.

import AppKit
import os
import SpeakCore
import SwiftUI
import UniformTypeIdentifiers

// MARK: - HistoryViewModel

@MainActor
final class HistoryViewModel: ObservableObject {

    // MARK: - Published state

    /// The entries currently displayed (recent, or search results), newest first.
    @Published private(set) var entries: [HistoryEntry] = []

    /// The live search text. Empty → show recent entries.
    @Published var searchText: String = "" {
        didSet { scheduleReload() }
    }

    /// `true` while a load/search is in flight (drives a progress affordance).
    @Published private(set) var isLoading: Bool = false

    // MARK: - Private

    private let store: any HistoryStoring
    private let log = SpeakLog.storage

    /// Max entries to show when not searching. Sourced from the store's own
    /// capacity default so there is no second magic number to drift
    /// (`benchmark.md` §7 "history size" — single source = `HistoryStore`).
    private let recentLimit = defaultHistoryMaxEntries

    /// The in-flight reload task, cancelled when a newer query supersedes it.
    private var reloadTask: Task<Void, Never>?

    // MARK: - Init

    init(store: any HistoryStoring) {
        self.store = store
    }

    // MARK: - Lifecycle

    /// Call when the window appears — performs the initial load.
    func onAppear() {
        scheduleReload()
    }

    // MARK: - Actions

    /// Permanently delete all stored entries, then refresh the (now empty) list.
    func clearAll() {
        Task { [weak self] in
            guard let self else { return }
            do {
                try await self.store.clear()
                self.log.info("HistoryViewModel: history cleared.")
            } catch {
                self.log.error("HistoryViewModel: clear failed — \(error.localizedDescription, privacy: .public)")
            }
            self.scheduleReload()
        }
    }

    /// Export all entries to a user-chosen file via NSSavePanel (JSON).
    func exportToFile() {
        Task { [weak self] in
            guard let self else { return }
            let json: String
            do {
                json = try await self.store.export()
            } catch {
                self.log.error("HistoryViewModel: export failed — \(error.localizedDescription, privacy: .public)")
                return
            }
            self.presentSavePanel(contents: json)
        }
    }

    // MARK: - Private

    /// Debounced reload: cancels any in-flight query and starts a fresh one for
    /// the current `searchText`. Empty text → recent(limit:); else → search().
    private func scheduleReload() {
        reloadTask?.cancel()
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        reloadTask = Task { [weak self] in
            guard let self else { return }
            self.isLoading = true
            defer { self.isLoading = false }
            do {
                let results: [HistoryEntry]
                if query.isEmpty {
                    results = try await self.store.recent(limit: self.recentLimit)
                } else {
                    results = try await self.store.search(query)
                }
                if Task.isCancelled { return }
                self.entries = results
            } catch {
                if Task.isCancelled { return }
                self.log.error("HistoryViewModel: load failed — \(error.localizedDescription, privacy: .public)")
                self.entries = []
            }
        }
    }

    /// Present a save panel and write the export contents to the chosen URL.
    private func presentSavePanel(contents: String) {
        let panel = NSSavePanel()
        panel.title = "Export Dictation History"
        panel.nameFieldStringValue = "speak-history.json"
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else {
            log.info("HistoryViewModel: export cancelled by user.")
            return
        }
        do {
            try contents.write(to: url, atomically: true, encoding: .utf8)
            log.info("HistoryViewModel: history exported to \(url.lastPathComponent, privacy: .public).")
        } catch {
            log.error("HistoryViewModel: write failed — \(error.localizedDescription, privacy: .public)")
        }
    }
}
