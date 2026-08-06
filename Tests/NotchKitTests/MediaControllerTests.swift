import AppKit
import Testing
import Foundation
@testable import NotchKit

private let fastInterval = Duration.milliseconds(10)

/// Long enough for a fetch task spawned by the controller to finish.
private let settleTime = Duration.milliseconds(50)

private func playing(_ app: MediaApp, _ title: String) -> MediaSnapshot {
    MediaSnapshot(app: app, title: title, artist: "Someone", isPlaying: true)
}

private func paused(_ app: MediaApp, _ title: String) -> MediaSnapshot {
    MediaSnapshot(app: app, title: title, artist: "Someone", isPlaying: false)
}

private func announcement(_ title: String, _ state: String) -> [String: String] {
    ["Name": title, "Artist": "Someone", "Player State": state]
}

/// The smallest thing `NSImage(data:)` accepts, so the controller's published
/// artwork is a real image rather than a decode failure.
private let artworkBytes: Data = {
    let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: 2,
        pixelsHigh: 2,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    )!
    return bitmap.representation(using: .png, properties: [:])!
}()

/// Answers from a dictionary and records what it was told to do.
private actor FakeMediaScripting: MediaScripting {
    struct Sent: Equatable {
        let command: MediaCommand
        let app: MediaApp
    }

    private var snapshots: [MediaApp: MediaSnapshot]
    private var permitted: Set<MediaApp>
    private(set) var sent: [Sent] = []
    private(set) var snapshotRequests = 0
    private(set) var artworkRequests: [TrackIdentity] = []
    private(set) var permissionChecks = 0

    init(_ snapshots: [MediaApp: MediaSnapshot] = [:], permitted: Set<MediaApp> = Set(MediaApp.allCases)) {
        self.snapshots = snapshots
        self.permitted = permitted
    }

    func snapshot(of app: MediaApp) async -> MediaSnapshot? {
        snapshotRequests += 1
        return snapshots[app]
    }

    func send(_ command: MediaCommand, to app: MediaApp) async {
        sent.append(Sent(command: command, app: app))
        snapshots[app] = nil
    }

    func artwork(for app: MediaApp, track: TrackIdentity) async -> Data? {
        artworkRequests.append(track)
        return artworkBytes
    }

    func hasAutomationPermission(for app: MediaApp) async -> Bool {
        permissionChecks += 1
        return permitted.contains(app)
    }

    func replace(_ snapshots: [MediaApp: MediaSnapshot]) {
        self.snapshots = snapshots
    }

    func permit(_ app: MediaApp) {
        permitted.insert(app)
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

// MARK: - Playback notifications

@Test @MainActor func adoptsWhatANotificationAnnounces() async {
    let controller = MediaController(scripting: FakeMediaScripting(), interval: fastInterval)

    controller.handlePlaybackNotification(announcement("Teardrop", "Playing"), from: .spotify)

    #expect(controller.nowPlaying?.title == "Teardrop")
    #expect(controller.nowPlaying?.artist == "Someone")
    #expect(controller.nowPlaying?.isPlaying == true)
    #expect(controller.nowPlaying?.source == .spotify)
}

@Test @MainActor func ignoresANotificationWithNoTrackName() async {
    let controller = MediaController(scripting: FakeMediaScripting(), interval: fastInterval)

    controller.handlePlaybackNotification(["Player State": "Playing"], from: .music)

    #expect(controller.nowPlaying == nil)
}

@Test @MainActor func ignoresANotificationWithNoPlayerState() async {
    let controller = MediaController(scripting: FakeMediaScripting(), interval: fastInterval)

    controller.handlePlaybackNotification(["Name": "Teardrop"], from: .music)

    #expect(controller.nowPlaying == nil)
}

@Test @MainActor func stoppingClearsOnlyTheAppThatWasShowing() async {
    let controller = MediaController(scripting: FakeMediaScripting(), interval: fastInterval)
    controller.handlePlaybackNotification(announcement("Teardrop", "Playing"), from: .spotify)

    controller.handlePlaybackNotification(["Player State": "Stopped"], from: .music)
    #expect(controller.nowPlaying?.title == "Teardrop")

    controller.handlePlaybackNotification(["Player State": "Stopped"], from: .spotify)
    #expect(controller.nowPlaying == nil)
}

@Test @MainActor func aPausedAppNeverDisplacesAPlayingOne() async {
    let controller = MediaController(scripting: FakeMediaScripting(), interval: fastInterval)
    controller.handlePlaybackNotification(announcement("Teardrop", "Playing"), from: .spotify)

    controller.handlePlaybackNotification(announcement("Blue in Green", "Paused"), from: .music)

    #expect(controller.nowPlaying?.source == .spotify)
}

@Test @MainActor func publishesEveryAdoptedAnnouncement() async {
    let controller = MediaController(scripting: FakeMediaScripting(), interval: fastInterval)
    var announced: [NowPlaying?] = []
    let subscription = controller.playbackEvents.sink { announced.append($0) }
    defer { subscription.cancel() }

    controller.handlePlaybackNotification(announcement("Teardrop", "Playing"), from: .spotify)
    controller.handlePlaybackNotification(announcement("Teardrop", "Paused"), from: .spotify)

    #expect(announced.count == 2)
    #expect(announced.first??.isPlaying == true)
    #expect(announced.last??.isPlaying == false)
}

// MARK: - Artwork

@Test @MainActor func fetchesArtworkOncePerTrack() async throws {
    let scripting = FakeMediaScripting([.music: playing(.music, "Blue in Green")])
    let controller = MediaController(scripting: scripting, interval: fastInterval)

    await controller.refresh()
    await controller.refresh()
    try await Task.sleep(for: settleTime)

    #expect(controller.artwork != nil)
    let requests = await scripting.artworkRequests
    #expect(requests.map(\.title) == ["Blue in Green"])
}

@Test @MainActor func refetchesOnlyForTracksItHasNotSeen() async throws {
    let scripting = FakeMediaScripting([.music: playing(.music, "Blue in Green")])
    let controller = MediaController(scripting: scripting, interval: fastInterval)
    await controller.refresh()

    await scripting.replace([.music: playing(.music, "So What")])
    await controller.refresh()
    try await Task.sleep(for: settleTime)

    // Back to a track that is still in the cache: no third round trip.
    await scripting.replace([.music: playing(.music, "Blue in Green")])
    await controller.refresh()
    try await Task.sleep(for: settleTime)

    let requests = await scripting.artworkRequests
    #expect(requests.map(\.title) == ["Blue in Green", "So What"])
    #expect(controller.artwork != nil)
}

@Test @MainActor func dropsTheArtworkWhenNothingIsPlaying() async throws {
    let scripting = FakeMediaScripting([.music: playing(.music, "Blue in Green")])
    let controller = MediaController(scripting: scripting, interval: fastInterval)
    await controller.refresh()
    try await Task.sleep(for: settleTime)
    #expect(controller.artwork != nil)

    await scripting.replace([:])
    await controller.refresh()

    #expect(controller.artwork == nil)
}

// MARK: - Automation permission gate

@Test @MainActor func doesNotScriptForABackgroundTrackUntilPermissionIsGranted() async throws {
    let scripting = FakeMediaScripting(permitted: [])
    let controller = MediaController(scripting: scripting, interval: fastInterval)

    controller.handlePlaybackNotification(announcement("Teardrop", "Playing"), from: .spotify)
    try await Task.sleep(for: settleTime)

    #expect(controller.artwork == nil)
    let requests = await scripting.artworkRequests
    #expect(requests.isEmpty)
    let checks = await scripting.permissionChecks
    #expect(checks == 1)
}

@Test @MainActor func fetchesForABackgroundTrackOncePermissionIsGranted() async throws {
    let scripting = FakeMediaScripting(permitted: [])
    let controller = MediaController(scripting: scripting, interval: fastInterval)
    controller.handlePlaybackNotification(announcement("Teardrop", "Playing"), from: .spotify)
    try await Task.sleep(for: settleTime)

    await scripting.permit(.spotify)
    controller.handlePlaybackNotification(announcement("Teardrop", "Playing"), from: .spotify)
    try await Task.sleep(for: settleTime)

    #expect(controller.artwork != nil)
    let requests = await scripting.artworkRequests
    #expect(requests.map(\.title) == ["Teardrop"])
}

@Test @MainActor func neverChecksPermissionForAUserInitiatedFetch() async throws {
    // The poll only runs while the panel is open, so its fetches are the ones
    // allowed to raise the Automation prompt.
    let scripting = FakeMediaScripting([.music: playing(.music, "Blue in Green")], permitted: [])
    let controller = MediaController(scripting: scripting, interval: fastInterval)

    await controller.refresh()
    try await Task.sleep(for: settleTime)

    let checks = await scripting.permissionChecks
    #expect(checks == 0)
    #expect(controller.artwork != nil)
}
