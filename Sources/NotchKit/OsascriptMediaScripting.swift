import AppKit
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
