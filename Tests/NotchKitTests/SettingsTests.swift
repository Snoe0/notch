import Testing
import Foundation
@testable import NotchKit

/// A throwaway defaults suite so tests never touch the app's real settings.
private func makeScratchDefaults() -> UserDefaults {
    let suite = "panel-settings-tests-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    return defaults
}

// MARK: - Defaults

@Test @MainActor func everySurfaceIsOnByDefault() {
    let settings = PanelSettings(defaults: makeScratchDefaults())
    #expect(settings.showsMedia)
    #expect(settings.showsPomodoro)
    #expect(settings.showsTodos)
    #expect(settings.showsNotes)
}

@Test @MainActor func layoutShipsUnswapped() {
    let settings = PanelSettings(defaults: makeScratchDefaults())
    #expect(!settings.swapsColumns)
    #expect(!settings.swapsFlanks)
}

// MARK: - Persistence

@Test @MainActor func featureTogglesSurviveARelaunch() {
    let defaults = makeScratchDefaults()

    let settings = PanelSettings(defaults: defaults)
    settings.showsMedia = false
    settings.showsPomodoro = false
    settings.showsTodos = false
    settings.showsNotes = false

    let relaunched = PanelSettings(defaults: defaults)
    #expect(!relaunched.showsMedia)
    #expect(!relaunched.showsPomodoro)
    #expect(!relaunched.showsTodos)
    #expect(!relaunched.showsNotes)
}

@Test @MainActor func layoutChoicesSurviveARelaunch() {
    let defaults = makeScratchDefaults()

    let settings = PanelSettings(defaults: defaults)
    settings.swapsColumns = true
    settings.swapsFlanks = true

    let relaunched = PanelSettings(defaults: defaults)
    #expect(relaunched.swapsColumns)
    #expect(relaunched.swapsFlanks)
}

/// Each setting owns its key: flipping one must never drag another with it.
@Test @MainActor func settingsPersistIndependently() {
    let defaults = makeScratchDefaults()

    PanelSettings(defaults: defaults).showsMedia = false

    let relaunched = PanelSettings(defaults: defaults)
    #expect(!relaunched.showsMedia)
    #expect(relaunched.showsPomodoro)
    #expect(relaunched.showsTodos)
    #expect(relaunched.showsNotes)
    #expect(!relaunched.swapsColumns)
    #expect(!relaunched.swapsFlanks)
}

/// `bool(forKey:)` would read garbage as `false`; a feature key holding
/// something that is not a Bool must read as that feature's default instead.
@Test @MainActor func garbageStoredValueFallsBackToTheDefault() {
    let defaults = makeScratchDefaults()
    defaults.set("sideways", forKey: PanelSettings.Keys.showsTodos)
    defaults.set("sideways", forKey: PanelSettings.Keys.swapsFlanks)

    let settings = PanelSettings(defaults: defaults)
    #expect(settings.showsTodos)
    #expect(!settings.swapsFlanks)
}
