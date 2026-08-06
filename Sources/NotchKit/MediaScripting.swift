import Foundation

/// A media app Notch can read and control.
///
/// Only apps with an AppleScript dictionary qualify. Browsers and everything
/// else would need MediaRemote, which is blocked to third parties since 15.4.
public enum MediaApp: String, CaseIterable, Sendable {
    case music
    case spotify

    /// The name AppleScript addresses the app by: `tell application "…"`.
    public var scriptingName: String {
        switch self {
        case .music: "Music"
        case .spotify: "Spotify"
        }
    }

    /// Used to check whether the app is already running. Asking AppleScript
    /// the same question would launch it.
    public var bundleIdentifier: String {
        switch self {
        case .music: "com.apple.Music"
        case .spotify: "com.spotify.client"
        }
    }

    /// What the UI calls this app.
    public var displayName: String { scriptingName }

    /// The public notification the app posts on `DistributedNotificationCenter`
    /// whenever playback changes. Listening costs nothing and needs no
    /// permission, which is what keeps the collapsed notch free of polling.
    public var playbackNotification: Notification.Name {
        switch self {
        case .music: Notification.Name("com.apple.Music.playerInfo")
        case .spotify: Notification.Name("com.spotify.client.PlaybackStateChanged")
        }
    }
}

/// One of the three transport buttons on the media strip.
public enum MediaCommand: String, CaseIterable, Sendable {
    case playPause
    case nextTrack
    case previousTrack
}

/// What a media app reports about itself at one moment.
///
/// A missing snapshot — the app is not running, has no track loaded, or the
/// script failed — is expressed as `nil`, so there is no "empty" case here.
public struct MediaSnapshot: Equatable, Sendable {
    public let app: MediaApp
    public let title: String
    public let artist: String
    public let isPlaying: Bool

    public init(app: MediaApp, title: String, artist: String, isPlaying: Bool) {
        self.app = app
        self.title = title
        self.artist = artist
        self.isPlaying = isPlaying
    }
}

/// Which track a piece of artwork belongs to.
///
/// Title and artist are all the media apps agree on, and they are stable for as
/// long as the track is playing — enough to cache artwork against and to detect
/// that the track moved on mid-fetch.
public struct TrackIdentity: Hashable, Sendable {
    public let title: String
    public let artist: String

    public init(title: String, artist: String) {
        self.title = title
        self.artist = artist
    }
}

/// Reads and controls a single media app.
///
/// The seam that keeps `MediaController`'s source selection testable: the real
/// adapter shells out to `osascript`, the test double answers from a dictionary.
public protocol MediaScripting: Sendable {
    /// `nil` whenever there is nothing to show, for any reason.
    func snapshot(of app: MediaApp) async -> MediaSnapshot?

    /// Best effort. Failures are silent; the next poll tick shows the truth.
    func send(_ command: MediaCommand, to app: MediaApp) async

    /// Encoded image bytes for `track`, or `nil` when the track has no
    /// artwork, the app moved on, or the fetch failed.
    ///
    /// Far more expensive than a snapshot — Music copies the whole image out,
    /// Spotify needs a download — so callers fetch once per track, never per
    /// poll tick.
    func artwork(for app: MediaApp, track: TrackIdentity) async -> Data?

    /// Whether Automation permission for `app` has *already* been granted,
    /// answered without ever showing the permission prompt.
    func hasAutomationPermission(for app: MediaApp) async -> Bool
}
