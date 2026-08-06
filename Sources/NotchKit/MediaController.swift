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
}

/// Drives the media strip: polls the media apps while the panel is open, picks
/// which one to show, and routes the transport buttons to it.
///
/// Polling is started and stopped by the panel controller rather than running
/// for the app's lifetime. That is what keeps the collapsed state free, and it
/// is why the Automation prompt appears on first open instead of at launch.
@MainActor
public final class MediaController: ObservableObject {
    /// `nil` is the idle state: no media app running, or nothing to report.
    @Published public private(set) var nowPlaying: NowPlaying?

    private let scripting: MediaScripting
    private let interval: Duration
    private var pollTask: Task<Void, Never>?

    /// Breaks the tie when both apps are paused.
    private var lastPlayingApp: MediaApp?

    public init(
        scripting: MediaScripting = OsascriptMediaScripting(),
        interval: Duration = .seconds(2)
    ) {
        self.scripting = scripting
        self.interval = interval
    }

    deinit { pollTask?.cancel() }

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
    public func refresh() async {
        let selected = select(from: await snapshotsOfRunningApps())
        rememberIfPlaying(selected)
        nowPlaying = selected.map(NowPlaying.init)
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

    private func rememberIfPlaying(_ snapshot: MediaSnapshot?) {
        guard let snapshot, snapshot.isPlaying else { return }
        lastPlayingApp = snapshot.app
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
}
