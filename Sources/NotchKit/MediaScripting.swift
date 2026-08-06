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

/// Reads and controls a single media app.
///
/// The seam that keeps `MediaController`'s source selection testable: the real
/// adapter shells out to `osascript`, the test double answers from a dictionary.
public protocol MediaScripting: Sendable {
    /// `nil` whenever there is nothing to show, for any reason.
    func snapshot(of app: MediaApp) async -> MediaSnapshot?

    /// Best effort. Failures are silent; the next poll tick shows the truth.
    func send(_ command: MediaCommand, to app: MediaApp) async
}
