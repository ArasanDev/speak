// SpeakCore/Hotkey/BindingStore.swift
//
// BindingStoring protocol and UserDefaultsBindingStore — persistence seam for
// HotkeyBinding. Moved from HotkeyMonitor.swift.
//
// Testable via InMemoryBindingStore (SpeakTests/HotkeyMonitorTests.swift).

import Foundation

// MARK: - BindingStoring

/// A thin, testable boundary around UserDefaults for hotkey binding persistence.
/// Concrete impl: UserDefaultsBindingStore. Mock: InMemoryBindingStore (tests).
///
/// [V01-5] Extended (not replaced) with `loadExtraBindings()`/`saveExtraBindings(_:)`
/// for the additive multi-binding-per-action feature (`ExtraBinding.swift`). Kept
/// on the same protocol/store as the primary binding — same pattern the P5/Phase B
/// comments describe for `SettingsStore.triggerMode`: one store, one source of
/// truth, `SettingsStore` is a thin user-facing surface over it (see SettingsStore
/// `extraBindings` property).
public protocol BindingStoring: Sendable {
    func load() -> HotkeyBinding?
    func save(_ binding: HotkeyBinding)

    /// Old payloads (or a fresh install) have no extra bindings — returns `nil`,
    /// callers fall back to `ExtraBindingSet.empty`, mirroring the primary
    /// binding's `store.load() ?? binding` fallback pattern.
    func loadExtraBindings() -> ExtraBindingSet?
    func saveExtraBindings(_ set: ExtraBindingSet)
}

/// Production store backed by UserDefaults.standard.
public final class UserDefaultsBindingStore: BindingStoring, @unchecked Sendable {
    private let key = "com.speak.hotkeyBinding"
    /// [V01-5] Separate key — decoding failures/format changes on one must never
    /// affect the other.
    private let extraBindingsKey = "com.speak.extraHotkeyBindings"

    /// [parallel-test-isolation] Injectable so tests can pass a UUID-suite
    /// `UserDefaults` instance instead of racing on the shared `.standard`
    /// domain (which is the same on-disk plist across concurrently-launched
    /// `xctest` worker processes sharing the app's bundle ID). Defaults to
    /// `.standard` — production call sites (`UserDefaultsBindingStore()`) are
    /// unaffected.
    private let defaults: UserDefaults

    // [Input-M2] JSONEncoder and JSONDecoder are NOT thread-safe (Apple docs).
    // `save()` is called from multiple threads (run-loop thread, main actor).
    // Create fresh instances per call to avoid data races under @unchecked Sendable.

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func load() -> HotkeyBinding? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(HotkeyBinding.self, from: data)
    }

    public func save(_ binding: HotkeyBinding) {
        guard let data = try? JSONEncoder().encode(binding) else { return }
        defaults.set(data, forKey: key)
    }

    public func loadExtraBindings() -> ExtraBindingSet? {
        guard let data = defaults.data(forKey: extraBindingsKey) else { return nil }
        return try? JSONDecoder().decode(ExtraBindingSet.self, from: data)
    }

    public func saveExtraBindings(_ set: ExtraBindingSet) {
        guard let data = try? JSONEncoder().encode(set) else { return }
        defaults.set(data, forKey: extraBindingsKey)
    }
}
