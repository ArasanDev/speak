// SpeakCore/STT/LocaleSupport.swift
//
// Exposes the real SpeechAnalyzer locale surface to SpeakCore consumers
// (primarily the TranscriptionSettingsTab in the UI layer).
//
// API VERIFICATION — all symbols [verified] from arm64e-apple-macos.swiftinterface
// inside the macOS 26 SDK (Xcode.app/…/Speech.swiftmodule), 2026-06-22:
//
//   • SpeechTranscriber.supportedLocales: [Locale] { get async }
//     — All locales the on-device SpeechAnalyzer can recognize (model may need download).
//   • SpeechTranscriber.installedLocales: [Locale] { get async }
//     — Subset of supportedLocales whose model asset is already on disk (ready to use).
//
// DESIGN:
//   This struct is a pure async fetch helper — no state, no caching.
//   The UI layer decides how to cache (via @State + .task{}).
//   Not added to the `Transcribing` protocol because:
//     (a) The protocol is availability-unguarded; adding a static async requirement
//         forces every future engine to implement locale introspection, which is
//         engine-specific, not protocol-shaped.
//     (b) SpeakCore exposing this as a standalone type keeps the seam minimal.
//
// ASSET-AVAILABILITY:
//   `supportedLocales` includes locales whose model is available for download
//   but not yet installed. `installedLocales` is the ready-to-use subset.
//   The UI surfaces which locales need download via `needsDownload(locale:)`.
//   Whether SpeechAnalyzer will auto-trigger a download at session start for a
//   supported-but-not-installed locale is `[unverified — live]`: the existing
//   `provisionAsset` path in AppleSpeechTranscriber handles this at transcription
//   time regardless, so the UI label is informational, not a gate.

import Foundation
import Speech
import os

// MARK: - SpeechTranscriberLocaleSource

/// Queries `SpeechTranscriber` for its supported and installed locales.
///
/// Usage (in SwiftUI):
/// ```swift
/// @State private var locales: [Locale] = []
/// .task {
///     locales = await SpeechTranscriberLocaleSource.supportedLocales()
/// }
/// ```
@available(macOS 26.0, *)
public enum SpeechTranscriberLocaleSource {

    // MARK: - Public API

    /// All locales the SpeechAnalyzer engine supports.
    ///
    /// Includes both installed locales (model on disk) and locales that can be
    /// downloaded. Sorted by human-readable display name in the current locale.
    ///
    /// [verified: SpeechTranscriber.supportedLocales from arm64e-apple-macos.swiftinterface, 2026-06-22]
    public static func supportedLocales() async -> [Locale] {
        let locales = await SpeechTranscriber.supportedLocales   // [verified]
        return sorted(locales)
    }

    /// Subset of `supportedLocales()` whose speech model is already installed.
    ///
    /// These locales can be used immediately without a download step.
    ///
    /// [verified: SpeechTranscriber.installedLocales from arm64e-apple-macos.swiftinterface, 2026-06-22]
    public static func installedLocales() async -> [Locale] {
        let locales = await SpeechTranscriber.installedLocales   // [verified]
        return sorted(locales)
    }

    /// Returns `true` when `locale` is in `supportedLocales` but not in `installedLocales`.
    ///
    /// [unverified — live]: whether SpeechAnalyzer auto-installs at session start is
    /// not directly tested here; `AppleSpeechTranscriber.provisionAsset` handles the
    /// actual download at transcription time.
    public static func needsDownload(locale: Locale, installedLocales: [Locale]) -> Bool {
        !installedLocales.contains { $0.identifier == locale.identifier }
    }

    // MARK: - Helpers

    /// Sorts locales by their human-readable display name in the current locale.
    /// Ties are broken by identifier string for determinism.
    private static func sorted(_ locales: [Locale]) -> [Locale] {
        locales.sorted { a, b in
            let nameA = displayName(for: a)
            let nameB = displayName(for: b)
            if nameA == nameB { return a.identifier < b.identifier }
            return nameA.localizedCompare(nameB) == .orderedAscending
        }
    }

    /// Human-readable name for a locale, e.g. `"English (United States)"`.
    ///
    /// Falls back to `locale.identifier` if `localizedString(forIdentifier:)`
    /// returns `nil` (should not happen in practice, but never force-unwrap).
    public static func displayName(for locale: Locale) -> String {
        Locale.current.localizedString(forIdentifier: locale.identifier) ?? locale.identifier
    }
}
