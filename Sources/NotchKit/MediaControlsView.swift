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
            if let artwork = media.artwork {
                ArtworkView(image: artwork, side: 22)
            }
            if let nowPlaying = media.nowPlaying {
                TrackLabel(title: nowPlaying.title, artist: nowPlaying.artist, size: 11)
            }
            Spacer(minLength: 4)
            transport
        }
        // Leading matches the todo column below; trailing hugs the notch,
        // which provides its own visual margin.
        .padding(.leading, 18)
        .padding(.trailing, 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Idle means no media app had anything to report on the last poll.
    private var isIdle: Bool { media.nowPlaying == nil }

    private var transport: some View {
        HStack(spacing: 1) {
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
                .frame(width: 17, height: 20)
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
