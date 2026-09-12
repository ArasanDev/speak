// SpeakCore/STT/LocaleSupport.swift
//
// Exposes the real SpeechAnalyzer locale surface to SpeakCore consumers
// (the Language card in Settings).
//
// API VERIFICATION — all symbols [verified] from arm64e-apple-macos.swiftinterface
// inside the macOS 26 SDK (Xcode.app/…/Speech.swiftmodule), 2026-06-22 /
// re-confirmed 2026-07-06:
//
//   • DictationTranscriber.supportedLocales: [Locale] { get async }
//     — All locales the dictation engine can recognize (model may need download).
//   • DictationTranscriber.installedLocales: [Locale] { get async }
//     — Subset whose model asset is already on disk (ready to use).
//   • DictationTranscriber.supportedLocale(equivalentTo:) async -> Locale?
//     — SDK-side canonical matcher; resolves identifier-shape differences such
//       as a persisted "en_IN" against the SDK's canonical "en-IN".
//
// ENGINE MATCH [fix: settings queried the wrong model family]:
//   The capture path instantiates `DictationTranscriber`
//   (AppleSpeechTranscriber.swift, .progressiveLongDictation), NOT
//   `SpeechTranscriber`. The two have different asset families and different
//   locale lists, so this source queries DictationTranscriber — the list must
//   describe the engine that will actually transcribe.
//
// NON-BLOCKING CONTRACT [fix: settings hang]:
//   The SDK getters await a reply from the speech-assets daemon with no
//   timeout; a wedged or slow daemon leaves the await suspended forever.
//   `fetchLists` therefore races the real fetch against a deadline (the
//   resumeOnce pattern from CaptureSession+Cleanup). Callers must treat nil
//   as "unknown", NOT as "empty" — the user's stored language is never
//   authoritative-reset based on this list.
//
// IDENTIFIER NORMALIZATION:
//   UserDefaults may persist "en_IN" while the SDK returns "en-IN".
//   Raw `identifier` equality is therefore unsafe; all matching here goes
//   through `normalizedIdentifier` (underscore → hyphen) or the SDK's own
//   `supportedLocale(equivalentTo:)`.

import Foundation
import os
import Speech

// MARK: - DictationTranscriberLocaleSource

/// Queries `DictationTranscriber` for its supported and installed locales.
///
/// Usage (in SwiftUI):
/// ```swift
/// .task {
///     if let lists = await DictationTranscriberLocaleSource.fetchLists() {
///         supported = lists.supported
///         installed = Set(lists.installed.map(DictationTranscriberLocaleSource.normalizedIdentifier))
///     }
/// }
/// ```
@available(macOS 26.0, *)
public enum DictationTranscriberLocaleSource {

    /// How long `fetchLists` waits for the speech-assets daemon before
    /// reporting the list as unavailable. Generous because a cold daemon can
    /// take seconds; bounded so the UI can never spin forever.
    /// [decision: 8 s — observed healthy fetches complete well under this;
    ///  a longer wait is indistinguishable from a hang to the user.]
    public static let fetchTimeoutNanoseconds: UInt64 = 8_000_000_000

    public struct LocaleLists: Sendable {
        public let supported: [Locale]
        public let installed: [Locale]
    }

    // MARK: - Public API

    /// All locales the DictationTranscriber engine supports — installed plus
    /// downloadable. Sorted by display name in the current locale.
    /// Can suspend indefinitely if the speech-assets daemon doesn't reply;
    /// prefer `fetchLists` from UI code.
    public static func supportedLocales() async -> [Locale] {
        sorted(await DictationTranscriber.supportedLocales)   // [verified]
    }

    /// Subset of `supportedLocales()` whose speech model is already installed.
    /// Same suspension caveat as `supportedLocales()`.
    public static func installedLocales() async -> [Locale] {
        sorted(await DictationTranscriber.installedLocales)   // [verified]
    }

    /// SDK-canonical equivalent for `locale`, or nil when the dictation
    /// engine supports nothing equivalent. Use this to canonicalize a
    /// persisted identifier ("en_IN" → "en-IN") without guessing.
    /// [verified: DictationTranscriber.supportedLocale(equivalentTo:)
    ///  from arm64e-apple-macos.swiftinterface, 2026-07-06]
    public static func supportedLocale(equivalentTo locale: Locale) async -> Locale? {
        await DictationTranscriber.supportedLocale(equivalentTo: locale)
    }

    /// Bounded fetch of both lists. Returns nil on timeout — the caller must
    /// treat nil as "unknown" and keep the user's stored selection usable.
    ///
    /// The SDK await cannot be cancelled cooperatively, so the fetch task is
    /// abandoned (not killed) on timeout — same trade-off as the cleanup
    /// timeout in CaptureSession+Cleanup: one suspended task, zero UI block.
    public static func fetchLists(
        timeoutNanoseconds: UInt64 = fetchTimeoutNanoseconds
    ) async -> LocaleLists? {
        await withCheckedContinuation { continuation in
            // resumeOnce: fetch and timeout race to resume; only the first wins.
            let resumeOnce = OSAllocatedUnfairLock<Bool>(initialState: false)

            let fetch = Task {
                async let s = supportedLocales()
                async let i = installedLocales()
                let lists = LocaleLists(supported: await s, installed: await i)
                resumeOnce.withLock { done in
                    guard !done else { return }
                    done = true
                    continuation.resume(returning: lists)
                }
            }

            Task {
                try? await Task.sleep(nanoseconds: timeoutNanoseconds)
                resumeOnce.withLock { done in
                    guard !done else { return }
                    done = true
                    fetch.cancel()   // best-effort — the SDK await may ignore it
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    /// Returns `true` when `locale` is supported but its model is not yet
    /// installed. Compares normalized identifiers so "en_IN" and "en-IN"
    /// match instead of producing a false "needs download".
    public static func needsDownload(locale: Locale, installedLocales: [Locale]) -> Bool {
        let wanted = normalizedIdentifier(for: locale)
        return !installedLocales.contains { normalizedIdentifier(for: $0) == wanted }
    }

    /// Identifier with underscores converted to hyphens — the shape the SDK
    /// returns ("en-IN"). Persisted values may carry either form.
    public static func normalizedIdentifier(for locale: Locale) -> String {
        locale.identifier.replacingOccurrences(of: "_", with: "-")
    }

    /// Human-readable name for a locale, e.g. `"English (United States)"`.
    /// Falls back to `locale.identifier` when `localizedString` returns nil.
    public static func displayName(for locale: Locale) -> String {
        Locale.current.localizedString(forIdentifier: locale.identifier) ?? locale.identifier
    }

    // MARK: - Helpers

    /// Sorts locales by display name in the current locale; identifier
    /// tie-breaks for determinism.
    private static func sorted(_ locales: [Locale]) -> [Locale] {
        locales.sorted { a, b in
            let nameA = displayName(for: a)
            let nameB = displayName(for: b)
            if nameA == nameB { return a.identifier < b.identifier }
            return nameA.localizedCompare(nameB) == .orderedAscending
        }
    }
}
