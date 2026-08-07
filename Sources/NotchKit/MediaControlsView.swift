import SwiftUI

/// The media strip beside the notch. One line: what is playing, then the
/// transport hugging the notch. Sized for roughly 215×32pt, so everything
/// truncates rather than wraps.
public struct MediaControlsView: View {
    @ObservedObject var media: MediaController
    /// Which flank of the notch the strip occupies. The layout mirrors with
    /// it, so the transport stays against the notch on either side.
    let flank: HorizontalEdge

    public init(media: MediaController, flank: HorizontalEdge = .leading) {
        self.media = media
        self.flank = flank
    }

    public var body: some View {
        HStack(spacing: 6) {
            if flank == .leading {
                nowPlayingArea
                Spacer(minLength: 4)
                transport
            } else {
                transport
                Spacer(minLength: 4)
                nowPlayingArea
            }
        }
        // The outer edge matches the column below; the notch edge keeps just
        // a sliver, because the notch provides its own visual margin.
        .padding(.leading, flank == .leading ? 18 : 6)
        .padding(.trailing, flank == .leading ? 6 : 18)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Idle means no media app had anything to report on the last poll.
    private var isIdle: Bool { media.nowPlaying == nil }

    /// The passive half of the strip — cover and track label — doubling as one
    /// click target that brings the source app forward. A gesture on its own
    /// subview rather than a button over the row, so it can never take focus
    /// and the transport buttons beside it keep their own clicks. Empty while
    /// idle, so there is nothing to click when there is nothing to open.
    private var nowPlayingArea: some View {
        HStack(spacing: 6) {
            if let artwork = media.artwork {
                ArtworkView(image: artwork, side: 22)
            }
            if let nowPlaying = media.nowPlaying {
                TrackLabel(title: nowPlaying.title, artist: nowPlaying.artist, size: 11)
            }
        }
        .contentShape(.rect)
        .onTapGesture { media.openSourceApp() }
    }

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
