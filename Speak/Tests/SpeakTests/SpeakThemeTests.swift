// SpeakTests/SpeakThemeTests.swift
//
// Tests for the runtime theme system (App/Theme/SpeakThemeSystem.swift +
// ThemeEngine.swift): role completeness, sparse-override merging, persistence
// round-trip, and engine selection/draft/delete semantics.

import Foundation
import SpeakCore
import Testing
@testable import Speak

@Suite("SpeakTheme — runtime palette model")
struct SpeakThemeTests {

    @MainActor private func makeEngine() throws -> (ThemeEngine, SettingsStore) {
        let defaults = try #require(UserDefaults(suiteName: UUID().uuidString))
        let store = SettingsStore(defaults: defaults)
        return (ThemeEngine(settingsStore: store), store)
    }

    // MARK: Model

    @Test("Default theme defines every role except optional accent")
    func defaultThemeCompleteness() {
        for role in ThemeColorRole.allCases where role != .accent {
            #expect(SpeakTheme.speak.colors[role.rawValue] != nil, "missing \(role)")
        }
        #expect(SpeakTheme.speak.colors[ThemeColorRole.accent.rawValue] == nil)
    }

    @Test("Both built-ins resolve every role")
    func builtInsResolveAllRoles() {
        for theme in SpeakTheme.builtInThemes {
            for role in ThemeColorRole.allCases {
                #expect(theme.pair(for: role) != nil || role == .accent,
                        "\(theme.id) missing \(role)")
            }
        }
    }

    @Test("Sparse custom theme falls back to default for missing roles")
    func sparseOverrideMerge() {
        let custom = SpeakTheme(
            id: "custom-x", name: "X",
            colors: ["windowCanvas": ThemeHexPair(light: "#000000", dark: "#111111")]
        )
        #expect(custom.pair(for: .windowCanvas)?.dark == "#111111")
        #expect(custom.pair(for: .cardCanvas) == SpeakTheme.speak.colors["cardCanvas"])
    }

    @Test("Unknown role keys in stored themes decode leniently")
    func lenientDecode() throws {
        let json = """
        [{"id":"custom-y","name":"Y","colors":{"windowCanvas":{"light":"#FFF","dark":"#000"},"futureRole":{"light":"#123456","dark":"#123456"}}}]
        """
        let decoded = try JSONDecoder().decode([SpeakTheme].self, from: Data(json.utf8))
        #expect(decoded.count == 1)
        #expect(decoded[0].colors["futureRole"] != nil)
        #expect(decoded[0].pair(for: .windowCanvas)?.light == "#FFF")
    }

    // MARK: Engine

    @Test("Selection persists and resolves")
    @MainActor func selectPersists() throws {
        let (engine, store) = try makeEngine()
        engine.select("ember")
        #expect(engine.activeTheme.id == "ember")
        #expect(store.themeID == "ember")
        #expect(SpeakThemeRuntime.active.id == "ember")
        engine.select("speak")  // leave runtime on the default for other tests
        #expect(SpeakThemeRuntime.active.id == "speak")
    }

    @Test("Unknown selection id is ignored")
    @MainActor func selectUnknownIgnored() throws {
        let (engine, _) = try makeEngine()
        engine.select("no-such-theme")
        #expect(engine.activeTheme.id == "speak")
    }

    @Test("Draft edits repaint live; discard restores committed theme")
    @MainActor func draftLifecycle() throws {
        let (engine, _) = try makeEngine()
        engine.beginDraft()
        engine.updateDraft(.windowCanvas, light: "#010203", dark: "#040506")
        #expect(SpeakThemeRuntime.active.pair(for: .windowCanvas)?.dark == "#040506")
        engine.discardDraft()
        #expect(engine.draft == nil)
        #expect(SpeakThemeRuntime.active.id == engine.activeTheme.id)
    }

    @Test("Commit persists custom theme and selects it")
    @MainActor func commitPersists() throws {
        let (engine, store) = try makeEngine()
        engine.beginDraft()
        engine.renameDraft("Test Theme")
        engine.commitDraft()
        #expect(engine.activeTheme.name == "Test Theme")
        #expect(engine.themes.contains { $0.name == "Test Theme" })
        // Round-trip through the stored JSON.
        let reloaded = ThemeEngine(settingsStore: store)
        #expect(reloaded.themes.contains { $0.name == "Test Theme" })
    }

    @Test("Deleting the active custom theme falls back to speak")
    @MainActor func deleteActiveFallsBack() throws {
        let (engine, store) = try makeEngine()
        engine.beginDraft()
        engine.commitDraft()
        let customID = engine.activeTheme.id
        #expect(customID != "speak")
        engine.deleteCustomTheme(id: customID)
        #expect(engine.activeTheme.id == "speak")
        #expect(store.themeID == "speak")
    }

    @Test("Corrupt stored JSON yields no customs, keeps default")
    @MainActor func corruptJSONLenient() throws {
        let store = SettingsStore(defaults: try #require(UserDefaults(suiteName: UUID().uuidString)))
        store.customThemesJSON = "{ not json"
        let engine = ThemeEngine(settingsStore: store)
        #expect(engine.themes == SpeakTheme.builtInThemes)
        #expect(engine.activeTheme.id == "speak")
    }
}
