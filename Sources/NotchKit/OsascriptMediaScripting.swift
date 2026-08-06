import AppKit
import Carbon.OpenScripting
import Foundation

/// Talks to Music and Spotify by running `/usr/bin/osascript` as a child process.
///
/// Two rules shape this adapter:
///
/// - **Never launch an app.** Addressing a quit app with AppleScript starts
///   it, so every call is gated on a running-application check first.
/// - **Never block the main actor.** The process runs on a background queue and
///   is awaited, so a media app that is slow — or sitting behind the first
///   "Notch wants to control Music" prompt — only delays the next poll tick.
public struct OsascriptMediaScripting: MediaScripting {
    public init() {}

    // MARK: - MediaScripting

    public func snapshot(of app: MediaApp) async -> MediaSnapshot? {
        guard isRunning(app) else { return nil }
        guard let output = await runScript(snapshotScript(for: app)) else { return nil }
        return snapshot(from: output, of: app)
    }

    public func send(_ command: MediaCommand, to app: MediaApp) async {
        guard isRunning(app) else { return }
        _ = await runScript(commandScript(command, for: app))
    }

    public func artwork(for app: MediaApp, track: TrackIdentity) async -> Data? {
        guard isRunning(app) else { return nil }
        switch app {
        case .music: return await musicArtwork(track)
        case .spotify: return await spotifyArtwork(track)
        }
    }

    public func hasAutomationPermission(for app: MediaApp) async -> Bool {
        guard isRunning(app) else { return false }
        return await withCheckedContinuation { continuation in
            Self.queue.async {
                continuation.resume(returning: Self.isAutomationPermitted(app.bundleIdentifier))
            }
        }
    }

    // MARK: - Artwork

    /// Music hands over the bytes it already holds, so there is no download.
    private func musicArtwork(_ track: TrackIdentity) async -> Data? {
        guard let output = await runScript(musicArtworkScript(track)) else { return nil }
        return Self.artworkData(fromLiteral: output)
    }

    /// Spotify only hands out a URL, on a public CDN that needs no permission
    /// of its own — but the URL still comes from AppleScript, so the caller's
    /// permission gate covers this path too.
    private func spotifyArtwork(_ track: TrackIdentity) async -> Data? {
        guard let output = await runScript(spotifyArtworkScript(track)),
              let url = Self.artworkURL(fromLiteral: output)
        else { return nil }
        return try? await URLSession.shared.data(from: url).0
    }

    // MARK: - Scripts

    /// Reports title, artist and player state on one tab-separated line, and an
    /// empty line when no track is loaded.
    private func snapshotScript(for app: MediaApp) -> String {
        """
        tell application "\(app.scriptingName)"
            try
                set trackTitle to name of current track
                set trackArtist to artist of current track
            on error
                return ""
            end try
            if player state is playing then
                return trackTitle & tab & trackArtist & tab & "\(Self.playingMarker)"
            else
                return trackTitle & tab & trackArtist & tab & "paused"
            end if
        end tell
        """
    }

    /// Returns the raw bytes of the current track's first artwork. The title
    /// check makes the whole thing a no-op once the track has moved on, so a
    /// slow fetch can never hand back the wrong cover.
    private func musicArtworkScript(_ track: TrackIdentity) -> String {
        """
        tell application "Music"
            try
                if name of current track is not \(quoted(track.title)) then return ""
                get data of artwork 1 of current track
            on error
                return ""
            end try
        end tell
        """
    }

    private func spotifyArtworkScript(_ track: TrackIdentity) -> String {
        """
        tell application "Spotify"
            try
                if name of current track is not \(quoted(track.title)) then return ""
                get artwork url of current track
            on error
                return ""
            end try
        end tell
        """
    }

    /// AppleScript string literals escape exactly like C's.
    private func quoted(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }

    private func commandScript(_ command: MediaCommand, for app: MediaApp) -> String {
        "tell application \"\(app.scriptingName)\" to \(verb(for: command))"
    }

    /// Both apps share these three verbs.
    private func verb(for command: MediaCommand) -> String {
        switch command {
        case .playPause: "playpause"
        case .nextTrack: "next track"
        case .previousTrack: "previous track"
        }
    }

    // MARK: - Parsing

    private static let playingMarker = "playing"

    private func snapshot(from output: String, of app: MediaApp) -> MediaSnapshot? {
        let fields = output
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: "\t")
        guard fields.count == 3, !fields[0].isEmpty else { return nil }
        return MediaSnapshot(
            app: app,
            title: fields[0],
            artist: fields[1],
            isPlaying: fields[2] == Self.playingMarker
        )
    }

    /// AppleScript prints raw data as `«data tdta89504E47…»`: a four-character
    /// type code followed by hex bytes. Anything else — the empty line the
    /// script returns when the track changed or has no cover, an error
    /// message — means there is no artwork to show.
    static func artworkData(fromLiteral literal: String) -> Data? {
        let trimmed = literal.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("«data "), trimmed.hasSuffix("»") else { return nil }
        let body = trimmed.dropFirst("«data ".count).dropLast()
        guard body.count > 4 else { return nil }
        return data(fromHex: body.dropFirst(4))
    }

    private static func data(fromHex hex: Substring) -> Data? {
        guard !hex.isEmpty, hex.count.isMultiple(of: 2) else { return nil }
        var bytes = Data(capacity: hex.count / 2)
        var index = hex.startIndex
        while index < hex.endIndex {
            let end = hex.index(index, offsetBy: 2)
            guard let byte = UInt8(hex[index..<end], radix: 16) else { return nil }
            bytes.append(byte)
            index = end
        }
        return bytes
    }

    /// Only http(s) is accepted: everything else is an error string the script
    /// let through, not a cover.
    static func artworkURL(fromLiteral literal: String) -> URL? {
        let trimmed = literal.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed),
              url.scheme == "https" || url.scheme == "http"
        else { return nil }
        return url
    }

    // MARK: - Automation permission

    /// Asks TCC whether we may drive `bundleIdentifier`, with
    /// `askUserIfNeeded: false` so the question is never put to the user here.
    ///
    /// The prompt has one agreed home — the first panel open, which the user
    /// asked for. Everything triggered in the background (a song changing
    /// while the notch is collapsed) runs through this check first and simply
    /// does nothing when the answer is anything but `noErr`: `procNotFound`
    /// when the app is not running, `errAEEventNotPermitted` when the user
    /// said no, `errAEEventWouldRequireUserConsent` when they have not been
    /// asked yet.
    private static func isAutomationPermitted(_ bundleIdentifier: String) -> Bool {
        var target = AEAddressDesc()
        let identifier = Array(bundleIdentifier.utf8)
        let created = identifier.withUnsafeBufferPointer { buffer in
            AECreateDesc(typeApplicationBundleID, buffer.baseAddress, buffer.count, &target)
        }
        guard created == noErr else { return false }
        defer { AEDisposeDesc(&target) }

        return AEDeterminePermissionToAutomateTarget(
            &target,
            AEEventClass(typeWildCard),
            AEEventID(typeWildCard),
            false
        ) == noErr
    }

    // MARK: - Process

    private func isRunning(_ app: MediaApp) -> Bool {
        !NSRunningApplication
            .runningApplications(withBundleIdentifier: app.bundleIdentifier)
            .isEmpty
    }

    /// A concurrent queue rather than the cooperative pool: `waitUntilExit`
    /// parks a whole thread, and one stalled script must not stall the others.
    private static let queue = DispatchQueue(
        label: "com.notch.osascript",
        qos: .userInitiated,
        attributes: .concurrent
    )

    private func runScript(_ source: String) async -> String? {
        await withCheckedContinuation { continuation in
            Self.queue.async {
                continuation.resume(returning: Self.execute(source))
            }
        }
    }

    /// `nil` for anything that is not a clean exit: app quit mid-script,
    /// Automation permission denied, osascript syntax error.
    private static func execute(_ source: String) -> String? {
        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/osascript")
        process.arguments = ["-e", source]

        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice

        guard (try? process.run()) != nil else { return nil }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
