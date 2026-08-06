import SwiftUI

/// The cover, square and softly rounded. Fills rather than fits, because
/// covers are square and anything else is better cropped than letterboxed.
struct ArtworkView: View {
    let image: NSImage
    let side: CGFloat

    var body: some View {
        Image(nsImage: image)
            .resizable()
            .aspectRatio(contentMode: .fill)
            .frame(width: side, height: side)
            .clipShape(.rect(cornerRadius: side / 5))
    }
}

/// Title, then a dimmed artist on the same line: the one-line form both the
/// media strip and the now-playing lozenge use. Truncates, never wraps.
struct TrackLabel: View {
    let title: String
    let artist: String
    let size: CGFloat

    var body: some View {
        (titleText + artistText)
            .font(.system(size: size))
            .lineLimit(1)
            .truncationMode(.tail)
    }

    private var titleText: Text {
        Text(title).foregroundStyle(.white)
    }

    /// Disappears entirely when the app reports no artist, so the separator
    /// never dangles.
    private var artistText: Text {
        guard !artist.isEmpty else { return Text("") }
        return Text(" — \(artist)").foregroundStyle(.white.opacity(0.5))
    }
}
