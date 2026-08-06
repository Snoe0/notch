import Combine
import Foundation

/// What the now-playing lozenge says.
///
/// The artwork is deliberately not carried here: it is fetched separately and
/// often lands after the lozenge is already on screen, so the chrome reads it
/// straight from the media controller instead.
public struct MediaPopout: Equatable, Sendable {
    public let title: String
    public let artist: String

    public init(title: String, artist: String) {
        self.title = title
        self.artist = artist
    }

    init(_ nowPlaying: NowPlaying) {
        self.init(title: nowPlaying.title, artist: nowPlaying.artist)
    }
}

/// Whether a playback change is worth showing a lozenge for.
enum PopoutDecision: Equatable {
    case show(MediaPopout)
    case ignore
}

/// Decides when the now-playing lozenge appears under a collapsed notch, and
/// takes it away again a few seconds later.
///
/// The policy lives in `decide`, a pure function of what was playing, what is
/// playing now, and where the notch is — so it is tested without a clock. The
/// presenter itself only owns the timer and the published value.
@MainActor
public final class PopoutPresenter: ObservableObject {
    /// `nil` whenever nothing should be drawn under a collapsed notch.
    @Published public private(set) var popout: MediaPopout?

    private let duration: Duration
    private var expiry: Task<Void, Never>?

    /// The last playback change we were told about — the baseline the next one
    /// is compared against.
    private var lastAnnounced: NowPlaying?

    public init(duration: Duration = .seconds(3)) {
        self.duration = duration
    }

    deinit { expiry?.cancel() }

    /// A media app announced a playback change.
    public func playbackChanged(to nowPlaying: NowPlaying?, while state: NotchState) {
        let decision = Self.decide(from: lastAnnounced, to: nowPlaying, while: state)
        lastAnnounced = nowPlaying
        guard case .show(let popout) = decision else { return }
        show(popout)
    }

    /// Opening the panel replaces the lozenge with the real thing.
    public func notchStateChanged(to state: NotchState) {
        guard state.isOpen else { return }
        hide()
    }

    /// Only a track that just started playing, or one that replaced another
    /// mid-play, is worth interrupting for — and only while nothing else is on
    /// screen. Pausing and stopping stay silent.
    ///
    /// `nonisolated` because it is the pure half: no state, no clock, nothing
    /// to serialize.
    nonisolated static func decide(
        from previous: NowPlaying?,
        to current: NowPlaying?,
        while state: NotchState
    ) -> PopoutDecision {
        guard state == .collapsed, let current, current.isPlaying else { return .ignore }
        guard let previous, previous.isPlaying, previous.track == current.track else {
            return .show(MediaPopout(current))
        }
        return .ignore
    }

    // MARK: - Timing

    /// Showing again restarts the clock, so a run of track changes leaves the
    /// lozenge up until the last one has had its full moment.
    private func show(_ popout: MediaPopout) {
        self.popout = popout
        expiry?.cancel()
        expiry = Task { [weak self, duration] in
            try? await Task.sleep(for: duration)
            guard !Task.isCancelled else { return }
            self?.popout = nil
        }
    }

    private func hide() {
        expiry?.cancel()
        expiry = nil
        popout = nil
    }
}
