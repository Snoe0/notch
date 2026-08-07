import Testing
import AppKit
@testable import NotchKit

// MARK: - Resolution

// Resolution tests run on the main actor: that is where the app resolves
// fonts, and AppKit's font machinery is not reliable from the parallel test
// runner's worker threads.

@Test @MainActor func everyFontChoiceResolvesAtTheRequestedSize() {
    for choice in ScratchpadFont.allCases {
        #expect(choice.resolved(size: 13).pointSize == 13)
    }
}

@Test @MainActor func monoResolvesToAMonospacedFont() {
    let traits = ScratchpadFont.mono.resolved(size: 13).fontDescriptor.symbolicTraits
    #expect(traits.contains(.monoSpace))
}

@Test @MainActor func designedChoicesDifferFromTheSystemFace() {
    let system = ScratchpadFont.system.resolved(size: 13)
    for choice in [ScratchpadFont.serif, .rounded, .mono] {
        let resolved = choice.resolved(size: 13)
        #expect(resolved.fontName != system.fontName, "\(choice) fell back to the system face")
    }
}

// MARK: - Persistence

/// A throwaway defaults suite so tests never touch the app's real settings.
private func makeScratchDefaults() -> UserDefaults {
    let suite = "scratchpad-font-tests-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    return defaults
}

@Test @MainActor func defaultsToTheSystemFontWhenNothingIsStored() {
    let setting = ScratchpadFontSetting(defaults: makeScratchDefaults())
    #expect(setting.choice == .system)
}

@Test @MainActor func choiceSurvivesARelaunch() {
    let defaults = makeScratchDefaults()

    ScratchpadFontSetting(defaults: defaults).choice = .serif

    let relaunched = ScratchpadFontSetting(defaults: defaults)
    #expect(relaunched.choice == .serif)
}

@Test @MainActor func everyChoiceRoundTripsThroughDefaults() {
    let defaults = makeScratchDefaults()
    for choice in ScratchpadFont.allCases {
        ScratchpadFontSetting(defaults: defaults).choice = choice
        #expect(ScratchpadFontSetting(defaults: defaults).choice == choice)
    }
}

@Test @MainActor func unknownStoredValueFallsBackToTheSystemFont() {
    let defaults = makeScratchDefaults()
    defaults.set("comic-sans", forKey: ScratchpadFontSetting.key)

    let setting = ScratchpadFontSetting(defaults: defaults)
    #expect(setting.choice == .system)
}
