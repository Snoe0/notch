import SwiftUI

/// The media strip that sits to the left of the notch. One line: what is
/// playing, then the transport. Sized for roughly 215×32pt, so everything
/// truncates rather than wraps.
public struct MediaControlsView: View {
    @ObservedObject var media: MediaController

    public init(media: MediaController) {
        self.media = media
    }

    public var body: some View {
        HStack(spacing: 6) {
            if let nowPlaying = media.nowPlaying {
                trackLabel(nowPlaying)
            }
            Spacer(minLength: 4)
            transport
        }
        .padding(.leading, 18)
        .padding(.trailing, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Idle means no media app had anything to report on the last poll.
    private var isIdle: Bool { media.nowPlaying == nil }

    private func trackLabel(_ nowPlaying: NowPlaying) -> some View {
        (title(nowPlaying) + artist(nowPlaying))
            .font(.system(size: 11))
            .lineLimit(1)
            .truncationMode(.tail)
    }

    private func title(_ nowPlaying: NowPlaying) -> Text {
        Text(nowPlaying.title).foregroundStyle(.white)
    }

    /// Trails the title on the same line, and disappears entirely when the app
    /// reports no artist, so the separator never dangles.
    private func artist(_ nowPlaying: NowPlaying) -> Text {
        guard !nowPlaying.artist.isEmpty else { return Text("") }
        return Text(" — \(nowPlaying.artist)").foregroundStyle(.white.opacity(0.5))
    }

    private var transport: some View {
        HStack(spacing: 2) {
            transportButton(.previousTrack, symbol: "backward.fill", size: 10)
            transportButton(.playPause, symbol: playPauseSymbol, size: 12)
            transportButton(.nextTrack, symbol: "forward.fill", size: 10)
        }
    }

    private var playPauseSymbol: String {
        media.nowPlaying?.isPlaying == true ? "pause.fill" : "play.fill"
    }

    private func transportButton(
        _ command: MediaCommand,
        symbol: String,
        size: CGFloat
    ) -> some View {
        Button {
            send(command)
        } label: {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .medium))
                .frame(width: 20, height: 20)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        // The panel's only focusable control is the text it is written in;
        // a button that took focus would pull the caret out of the notes.
        .focusable(false)
        .foregroundStyle(.white.opacity(isIdle ? 0.25 : 0.85))
        .disabled(isIdle)
    }

    private func send(_ command: MediaCommand) {
        Task {
            switch command {
            case .playPause: await media.playPause()
            case .nextTrack: await media.nextTrack()
            case .previousTrack: await media.previousTrack()
            }
        }
    }
}
