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
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init() {}

    public func load() -> HotkeyBinding? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? decoder.decode(HotkeyBinding.self, from: data)
    }

    public func save(_ binding: HotkeyBinding) {
        guard let data = try? encoder.encode(binding) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}
