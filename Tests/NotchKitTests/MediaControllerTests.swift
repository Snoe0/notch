import Testing
import Foundation
@testable import NotchKit

private let fastInterval = Duration.milliseconds(10)

private func playing(_ app: MediaApp, _ title: String) -> MediaSnapshot {
    MediaSnapshot(app: app, title: title, artist: "Someone", isPlaying: true)
}

private func paused(_ app: MediaApp, _ title: String) -> MediaSnapshot {
    MediaSnapshot(app: app, title: title, artist: "Someone", isPlaying: false)
}

/// Answers from a dictionary and records what it was told to do.
private actor FakeMediaScripting: MediaScripting {
    struct Sent: Equatable {
        let command: MediaCommand
        let app: MediaApp
    }

    private var snapshots: [MediaApp: MediaSnapshot]
    private(set) var sent: [Sent] = []
    private(set) var snapshotRequests = 0

    init(_ snapshots: [MediaApp: MediaSnapshot] = [:]) {
        self.snapshots = snapshots
    }

    func snapshot(of app: MediaApp) async -> MediaSnapshot? {
        snapshotRequests += 1
        return snapshots[app]
    }

    func send(_ command: MediaCommand, to app: MediaApp) async {
        sent.append(Sent(command: command, app: app))
        snapshots[app] = nil
    }

    func replace(_ snapshots: [MediaApp: MediaSnapshot]) {
        self.snapshots = snapshots
    }
}

// MARK: - Source selection

@Test @MainActor func showsNothingWhenNoMediaAppIsRunning() async {
    let controller = MediaController(scripting: FakeMediaScripting(), interval: fastInterval)

    await controller.refresh()

    #expect(controller.nowPlaying == nil)
}

@Test @MainActor func showsTheOnlyRunningApp() async {
    let scripting = FakeMediaScripting([.spotify: paused(.spotify, "Teardrop")])
    let controller = MediaController(scripting: scripting, interval: fastInterval)

    await controller.refresh()

    #expect(controller.nowPlaying?.source == .spotify)
    #expect(controller.nowPlaying?.title == "Teardrop")
    #expect(controller.nowPlaying?.isPlaying == false)
}

@Test @MainActor func thePlayingAppBeatsThePausedOne() async {
    let scripting = FakeMediaScripting([
        .music: paused(.music, "Blue in Green"),
        .spotify: playing(.spotify, "Teardrop"),
    ])
    let controller = MediaController(scripting: scripting, interval: fastInterval)

    await controller.refresh()

    #expect(controller.nowPlaying?.source == .spotify)
}

@Test @MainActor func theMostRecentlyPlayingAppWinsWhenBothArePaused() async {
    let scripting = FakeMediaScripting([
        .music: paused(.music, "Blue in Green"),
        .spotify: playing(.spotify, "Teardrop"),
    ])
    let controller = MediaController(scripting: scripting, interval: fastInterval)
    await controller.refresh()

    await scripting.replace([
        .music: paused(.music, "Blue in Green"),
        .spotify: paused(.spotify, "Teardrop"),
    ])
    await controller.refresh()

    #expect(controller.nowPlaying?.source == .spotify)
}

@Test @MainActor func fallsBackToIdleWhenTheScriptStopsAnswering() async {
    let scripting = FakeMediaScripting([.music: playing(.music, "Blue in Green")])
    let controller = MediaController(scripting: scripting, interval: fastInterval)
    await controller.refresh()
    #expect(controller.nowPlaying != nil)

    await scripting.replace([:])
    await controller.refresh()

    #expect(controller.nowPlaying == nil)
}

// MARK: - Commands

@Test @MainActor func sendsCommandsOnlyToTheSelectedApp() async {
    let scripting = FakeMediaScripting([
        .music: paused(.music, "Blue in Green"),
        .spotify: playing(.spotify, "Teardrop"),
    ])
    let controller = MediaController(scripting: scripting, interval: fastInterval)
    await controller.refresh()

    await controller.nextTrack()

    let sent = await scripting.sent
    #expect(sent == [.init(command: .nextTrack, app: .spotify)])
}

@Test @MainActor func sendsNothingWhileIdle() async {
    let scripting = FakeMediaScripting()
    let controller = MediaController(scripting: scripting, interval: fastInterval)
    await controller.refresh()

    await controller.playPause()
    await controller.previousTrack()

    let sent = await scripting.sent
    #expect(sent.isEmpty)
}

@Test @MainActor func refreshesRightAfterACommand() async {
    // The fake drops the app from its dictionary once commanded, so a stale
    // `nowPlaying` here would mean the post-command refresh never ran.
    let scripting = FakeMediaScripting([.music: playing(.music, "Blue in Green")])
    let controller = MediaController(scripting: scripting, interval: fastInterval)
    await controller.refresh()

    await controller.playPause()

    #expect(controller.nowPlaying == nil)
}

// MARK: - Polling

@Test @MainActor func pollingPicksUpChangesUntilItIsStopped() async throws {
    let scripting = FakeMediaScripting([.music: playing(.music, "Blue in Green")])
    let controller = MediaController(scripting: scripting, interval: fastInterval)

    controller.startPolling()
    try await Task.sleep(for: .milliseconds(50))
    #expect(controller.nowPlaying?.title == "Blue in Green")

    await scripting.replace([.music: playing(.music, "So What")])
    try await Task.sleep(for: .milliseconds(50))
    #expect(controller.nowPlaying?.title == "So What")

    // Let the tick that was already in flight when we stopped drain first.
    controller.stopPolling()
    try await Task.sleep(for: .milliseconds(50))
    let requestsAtStop = await scripting.snapshotRequests
    try await Task.sleep(for: .milliseconds(50))

    let requestsAfterStop = await scripting.snapshotRequests
    #expect(requestsAfterStop == requestsAtStop)
}

@Test @MainActor func doesNotPollBeforeItIsStarted() async throws {
    let scripting = FakeMediaScripting([.music: playing(.music, "Blue in Green")])
    let controller = MediaController(scripting: scripting, interval: fastInterval)

    try await Task.sleep(for: .milliseconds(50))

    let requests = await scripting.snapshotRequests
    #expect(requests == 0)
    #expect(controller.nowPlaying == nil)
}
