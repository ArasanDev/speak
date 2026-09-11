// SpeakTests/SettingsCategoryTests.swift
//
// Tests for `SettingsCategory` / `SettingsCategoryGroup` — the rail model of
// the dedicated two-panel Settings experience (App/Settings/).
// Asserts the IA invariants: every category is reachable from exactly one
// group, groups render in order, and no rail row has empty display metadata.

@testable import Speak
import Testing

@Suite("SettingsCategory — rail information architecture")
struct SettingsCategoryTests {

    @Test("Every category belongs to exactly one group")
    func everyCategoryIsGrouped() {
        let grouped = SettingsCategoryGroup.allCases.flatMap(\.categories)
        #expect(grouped.count == SettingsCategory.allCases.count)
        #expect(Set(grouped) == Set(SettingsCategory.allCases))
    }

    @Test("Groups preserve category display order")
    func groupOrderMatchesAllCasesOrder() {
        for group in SettingsCategoryGroup.allCases {
            let allCasesOrder = SettingsCategory.allCases.filter { $0.group == group }
            #expect(group.categories == allCasesOrder)
        }
    }

    @Test("No category has empty display metadata")
    func displayMetadataIsNonEmpty() {
        for category in SettingsCategory.allCases {
            #expect(!category.title.isEmpty)
            #expect(!category.subtitle.isEmpty)
            #expect(!category.systemImage.isEmpty)
        }
    }

    @Test("Category ids are unique raw values")
    func idsAreUnique() {
        let ids = SettingsCategory.allCases.map(\.id)
        #expect(Set(ids).count == ids.count)
    }
}
