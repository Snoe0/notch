import AppKit
import Combine
import Foundation

/// The one track the media strip is showing, and where it came from.
public struct NowPlaying: Equatable, Sendable {
    public let title: String
    public let artist: String
    public let isPlaying: Bool
    public let source: MediaApp

    public init(title: String, artist: String, isPlaying: Bool, source: MediaApp) {
        self.title = title
        self.artist = artist
        self.isPlaying = isPlaying
        self.source = source
    }

    init(_ snapshot: MediaSnapshot) {
        self.init(
            title: snapshot.title,
            artist: snapshot.artist,
            isPlaying: snapshot.isPlaying,
            source: snapshot.app
        )
    }

    /// What artwork is cached against.
    public var track: TrackIdentity {
        TrackIdentity(title: title, artist: artist)
    }
}

/// Drives the media strip: polls the media apps while the panel is open, picks
/// which one to show, and routes the transport buttons to it.
///
/// Polling is started and stopped by the panel controller rather than running
/// for the app's lifetime. That is what keeps the collapsed state free, and it
/// is why the Automation prompt appears on first open instead of at launch.
///
/// While collapsed, state still stays fresh: both apps announce every playback
/// change on `DistributedNotificationCenter`, and those announcements are free
/// — no polling, no permission, no process spawned.
@MainActor
public final class MediaController: ObservableObject {
    /// `nil` is the idle state: no media app running, or nothing to report.
    @Published public private(set) var nowPlaying: NowPlaying?

    /// The cover of `nowPlaying`, once it has been fetched. `nil` while a
    /// fetch is in flight, when the track has no artwork, and whenever the
    /// permission gate below refuses a background fetch.
    @Published public private(set) var artwork: NSImage?

    /// Playback changes as the apps announce them, rather than as the poll
    /// discovers them. Only these mean "something just happened", which is
    /// what the now-playing popout keys off.
    public var playbackEvents: AnyPublisher<NowPlaying?, Never> {
        playbackSubject.eraseToAnyPublisher()
    }

    private let scripting: MediaScripting
    private let interval: Duration
    /// How `openSourceApp` reaches the Dock — `NSWorkspace` in production, a
    /// recorder in tests, the same seam idea as `scripting`.
    private let openApp: @MainActor (MediaApp) -> Void
    private let playbackSubject = PassthroughSubject<NowPlaying?, Never>()
    private var pollTask: Task<Void, Never>?
    /// Only ever written on the main actor, during `init`; `nonisolated` so
    /// `deinit`, which is not main-actor isolated, can hand the tokens back.
    private nonisolated(unsafe) var observers: [any NSObjectProtocol] = []

    /// Breaks the tie when both apps are paused.
    private var lastPlayingApp: MediaApp?

    /// The track `artwork` belongs to, fetched or still being fetched.
    private var artworkTrack: TrackIdentity?
    private var artworkTask: Task<Void, Never>?
    /// The last few results, misses included: re-asking for a track that has
    /// no cover costs the same round trip as asking for one that does.
    private var artworkCache: [(track: TrackIdentity, image: NSImage?)] = []
    private static let artworkCacheLimit = 4

    public init(
        scripting: MediaScripting = OsascriptMediaScripting(),
        interval: Duration = .seconds(2),
        openApp: (@MainActor (MediaApp) -> Void)? = nil
    ) {
        self.scripting = scripting
        self.interval = interval
        self.openApp = openApp ?? Self.activateInWorkspace
        observePlaybackNotifications()
    }

    deinit {
        pollTask?.cancel()
        artworkTask?.cancel()
        let center = DistributedNotificationCenter.default()
        for observer in observers {
            center.removeObserver(observer)
        }
    }

    // MARK: - Polling

    /// Refreshes immediately, then once per interval until stopped.
    public func startPolling() {
        stopPolling()
        pollTask = Task { [weak self, interval] in
            while !Task.isCancelled {
                await self?.refresh()
                try? await Task.sleep(for: interval)
            }
        }
    }

    public func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    /// One poll tick. Public so a command can pull fresh state right away.
    ///
    /// Polling only runs while the panel is open, so everything it triggers
    /// counts as user-initiated and may prompt for Automation.
    public func refresh() async {
        let selected = select(from: await snapshotsOfRunningApps()).map(NowPlaying.init)
        rememberIfPlaying(selected)
        nowPlaying = selected
        updateArtwork(userInitiated: true)
    }

    private func snapshotsOfRunningApps() async -> [MediaSnapshot] {
        var snapshots: [MediaSnapshot] = []
        for app in MediaApp.allCases {
            if let snapshot = await scripting.snapshot(of: app) {
                snapshots.append(snapshot)
            }
        }
        return snapshots
    }

    // MARK: - Source selection

    /// A playing app always beats a paused one; among equals, the app that
    /// played most recently wins.
    private func select(from snapshots: [MediaSnapshot]) -> MediaSnapshot? {
        preferred(among: snapshots.filter(\.isPlaying)) ?? preferred(among: snapshots)
    }

    private func preferred(among snapshots: [MediaSnapshot]) -> MediaSnapshot? {
        snapshots.first { $0.app == lastPlayingApp } ?? snapshots.first
    }

    private func rememberIfPlaying(_ nowPlaying: NowPlaying?) {
        guard let nowPlaying, nowPlaying.isPlaying else { return }
        lastPlayingApp = nowPlaying.source
    }

    // MARK: - Playback notifications

    /// Observed for the app's whole lifetime, unlike the poll: this is what
    /// keeps `nowPlaying` true while the notch is collapsed, at no cost.
    private func observePlaybackNotifications() {
        let center = DistributedNotificationCenter.default()
        observers = MediaApp.allCases.map { app in
            center.addObserver(
                forName: app.playbackNotification,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                let fields = Self.stringFields(in: notification.userInfo)
                // Delivered on the main queue, so this is the same hop-free
                // bridge the file and cursor watchers use.
                MainActor.assumeIsolated {
                    self?.handlePlaybackNotification(fields, from: app)
                }
            }
        }
    }

    /// Everything the apps report that we care about is a string, and unlike a
    /// raw `userInfo` a `[String: String]` can cross to the main actor.
    private nonisolated static func stringFields(
        in userInfo: [AnyHashable: Any]?
    ) -> [String: String] {
        var fields: [String: String] = [:]
        for (key, value) in userInfo ?? [:] {
            guard let key = key as? String, let value = value as? String else { continue }
            fields[key] = value
        }
        return fields
    }

    /// The body of the observers above. Internal rather than private so the
    /// parsing can be tested without posting system-wide notifications.
    func handlePlaybackNotification(_ fields: [String: String], from app: MediaApp) {
        guard let state = Self.playerState(in: fields) else { return }
        switch state {
        case .stopped:
            clearIfShowing(app)
        case .playing, .paused:
            guard let announced = Self.nowPlaying(in: fields, from: app, isPlaying: state == .playing)
            else { return }
            adopt(announced)
        }
        playbackSubject.send(nowPlaying)
    }

    /// Both apps report the same three states under the same key.
    private enum PlayerState: String {
        case playing = "Playing"
        case paused = "Paused"
        case stopped = "Stopped"
    }

    private static func playerState(in fields: [String: String]) -> PlayerState? {
        fields["Player State"].flatMap(PlayerState.init(rawValue:))
    }

    /// A notification without a usable track name is not worth acting on —
    /// the next poll, or the next notification, will say what is true.
    /// An absent artist is normal (podcasts, unnamed uploads) and reads as "".
    private static func nowPlaying(
        in fields: [String: String],
        from app: MediaApp,
        isPlaying: Bool
    ) -> NowPlaying? {
        guard let title = fields["Name"], !title.isEmpty else { return nil }
        return NowPlaying(
            title: title,
            artist: fields["Artist"] ?? "",
            isPlaying: isPlaying,
            source: app
        )
    }

    /// A paused app never displaces a playing one: the same rule the poll's
    /// source selection applies, restated for the single-app view one
    /// notification gives us.
    private func adopt(_ announced: NowPlaying) {
        guard shouldAdopt(announced) else { return }
        nowPlaying = announced
        rememberIfPlaying(announced)
        updateArtwork(userInitiated: false)
    }

    private func shouldAdopt(_ announced: NowPlaying) -> Bool {
        guard let current = nowPlaying, current.source != announced.source else { return true }
        return announced.isPlaying || !current.isPlaying
    }

    /// Stopping says nothing about the *other* app, so it only clears the
    /// strip when the strip was showing the app that stopped.
    private func clearIfShowing(_ app: MediaApp) {
        guard nowPlaying?.source == app else { return }
        nowPlaying = nil
        updateArtwork(userInitiated: false)
    }

    // MARK: - Artwork

    /// Artwork is fetched once per track and then cached: one fetch is a whole
    /// `osascript` round trip — Spotify's is a download on top — which is far
    /// too much to repeat every two seconds. The fetch runs in its own task so
    /// a slow one never delays the next poll tick.
    private func updateArtwork(userInitiated: Bool) {
        guard let nowPlaying else { return forgetArtwork() }
        guard nowPlaying.track != artworkTrack else { return }

        artworkTask?.cancel()
        artworkTrack = nowPlaying.track

        if let cached = cachedArtwork(for: nowPlaying.track) {
            artwork = cached.image
            return
        }
        artwork = nil
        artworkTask = Task { [weak self] in
            await self?.fetchArtwork(
                for: nowPlaying.track,
                from: nowPlaying.source,
                userInitiated: userInitiated
            )
        }
    }

    private func fetchArtwork(
        for track: TrackIdentity,
        from app: MediaApp,
        userInitiated: Bool
    ) async {
        guard await isFetchAllowed(from: app, userInitiated: userInitiated) else {
            // Nothing was asked and nothing is cached, so the next
            // user-initiated update is free to try again for real.
            if artworkTrack == track { artworkTrack = nil }
            return
        }
        let image = await scripting.artwork(for: app, track: track).flatMap(NSImage.init(data:))
        remember(image, for: track)
        guard artworkTrack == track else { return }   // the track moved on mid-fetch
        artwork = image
    }

    /// The prompt-placement rule. A fetch the user did not ask for — one a
    /// notification triggered while the notch was collapsed — may only run
    /// AppleScript when Automation permission is *already* granted. Otherwise
    /// a song changing in the background would raise "Notch wants to control
    /// Music" out of nowhere; that prompt belongs to the first panel open and
    /// nowhere else.
    private func isFetchAllowed(from app: MediaApp, userInitiated: Bool) async -> Bool {
        if userInitiated { return true }
        return await scripting.hasAutomationPermission(for: app)
    }

    private func forgetArtwork() {
        artworkTask?.cancel()
        artworkTrack = nil
        artwork = nil
    }

    private func cachedArtwork(for track: TrackIdentity) -> (track: TrackIdentity, image: NSImage?)? {
        artworkCache.first { $0.track == track }
    }

    private func remember(_ image: NSImage?, for track: TrackIdentity) {
        artworkCache.removeAll { $0.track == track }
        artworkCache.append((track, image))
        if artworkCache.count > Self.artworkCacheLimit {
            artworkCache.removeFirst(artworkCache.count - Self.artworkCacheLimit)
        }
    }

    // MARK: - Commands

    public func playPause() async { await send(.playPause) }

    public func nextTrack() async { await send(.nextTrack) }

    public func previousTrack() async { await send(.previousTrack) }

    /// Commands only ever reach the app the strip is currently showing.
    private func send(_ command: MediaCommand) async {
        guard let target = nowPlaying?.source else { return }
        await scripting.send(command, to: target)
        await refresh()
    }

    // MARK: - Opening the source app

    /// Brings the app the strip is showing to the front: the click action of
    /// the strip's passive parts (artwork, title). A no-op while idle.
    public func openSourceApp() {
        guard let source = nowPlaying?.source else { return }
        openApp(source)
    }

    /// The production opener. `openApplication` activates a running app and
    /// launches a quit one, and neither path activates Notch itself — the
    /// panel stays the non-activating overlay it is.
    static func activateInWorkspace(_ app: MediaApp) {
        guard let url = NSWorkspace.shared
            .urlForApplication(withBundleIdentifier: app.bundleIdentifier)
        else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }
}
