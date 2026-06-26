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
public protocol BindingStoring: Sendable {
    func load() -> HotkeyBinding?
    func save(_ binding: HotkeyBinding)
}

/// Production store backed by UserDefaults.standard.
public final class UserDefaultsBindingStore: BindingStoring, @unchecked Sendable {
    private let key = "com.speak.hotkeyBinding"

    // [Input-M2] JSONEncoder and JSONDecoder are NOT thread-safe (Apple docs).
    // `save()` is called from multiple threads (run-loop thread, main actor).
    // Create fresh instances per call to avoid data races under @unchecked Sendable.

    public init() {}

    public func load() -> HotkeyBinding? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(HotkeyBinding.self, from: data)
    }

    public func save(_ binding: HotkeyBinding) {
        guard let data = try? JSONEncoder().encode(binding) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}
