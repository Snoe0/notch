import Testing
import Foundation
@testable import NotchKit

private func playing(_ title: String) -> NowPlaying {
    NowPlaying(title: title, artist: "Someone", isPlaying: true, source: .spotify)
}

private func paused(_ title: String) -> NowPlaying {
    NowPlaying(title: title, artist: "Someone", isPlaying: false, source: .spotify)
}

/// Short enough to watch expire inside a test, long enough not to be flaky.
private let lifetime = Duration.milliseconds(120)

// MARK: - Decision

@Test func showsATrackThatStartsWhileCollapsed() {
    let decision = PopoutPresenter.decide(from: nil, to: playing("Teardrop"), while: .collapsed)

    #expect(decision == .show(MediaPopout(title: "Teardrop", artist: "Someone")))
}

@Test func showsATrackThatReplacesAnotherMidPlay() {
    let decision = PopoutPresenter.decide(
        from: playing("Teardrop"),
        to: playing("Angel"),
        while: .collapsed
    )

    #expect(decision == .show(MediaPopout(title: "Angel", artist: "Someone")))
}

@Test func showsATrackThatResumesAfterAPause() {
    let decision = PopoutPresenter.decide(
        from: paused("Teardrop"),
        to: playing("Teardrop"),
        while: .collapsed
    )

    #expect(decision == .show(MediaPopout(title: "Teardrop", artist: "Someone")))
}

@Test func ignoresARepeatOfTheTrackAlreadyPlaying() {
    let decision = PopoutPresenter.decide(
        from: playing("Teardrop"),
        to: playing("Teardrop"),
        while: .collapsed
    )

    #expect(decision == .ignore)
}

@Test func ignoresPausingAndStopping() {
    #expect(PopoutPresenter.decide(from: playing("Teardrop"), to: paused("Teardrop"), while: .collapsed) == .ignore)
    #expect(PopoutPresenter.decide(from: playing("Teardrop"), to: nil, while: .collapsed) == .ignore)
}

@Test func ignoresEverythingWhileThePanelIsOpen() {
    #expect(PopoutPresenter.decide(from: nil, to: playing("Teardrop"), while: .peek) == .ignore)
    #expect(PopoutPresenter.decide(from: nil, to: playing("Teardrop"), while: .pinned) == .ignore)
}

// MARK: - Presentation

@Test @MainActor func showsAndThenExpires() async throws {
    let presenter = PopoutPresenter(duration: lifetime)

    presenter.playbackChanged(to: playing("Teardrop"), while: .collapsed)
    #expect(presenter.popout?.title == "Teardrop")

    try await Task.sleep(for: lifetime * 2)
    #expect(presenter.popout == nil)
}

@Test @MainActor func aNewTrackRestartsTheClock() async throws {
    let presenter = PopoutPresenter(duration: lifetime)
    presenter.playbackChanged(to: playing("Teardrop"), while: .collapsed)

    try await Task.sleep(for: lifetime * 0.7)
    presenter.playbackChanged(to: playing("Angel"), while: .collapsed)

    // Past the first track's deadline, comfortably inside the second's.
    try await Task.sleep(for: lifetime * 0.7)
    #expect(presenter.popout?.title == "Angel")
}

@Test @MainActor func openingThePanelTakesTheLozengeAway() async {
    let presenter = PopoutPresenter(duration: .seconds(30))
    presenter.playbackChanged(to: playing("Teardrop"), while: .collapsed)

    presenter.notchStateChanged(to: .peek)

    #expect(presenter.popout == nil)
}

@Test @MainActor func collapsingAgainDoesNotBringItBack() async {
    let presenter = PopoutPresenter(duration: .seconds(30))
    presenter.playbackChanged(to: playing("Teardrop"), while: .collapsed)
    presenter.notchStateChanged(to: .pinned)

    presenter.notchStateChanged(to: .collapsed)

    #expect(presenter.popout == nil)
}

@Test @MainActor func showsNothingForAChangeThatArrivesWhileOpen() async {
    let presenter = PopoutPresenter(duration: .seconds(30))

    presenter.playbackChanged(to: playing("Teardrop"), while: .pinned)

    #expect(presenter.popout == nil)
}
