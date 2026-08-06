import SwiftUI

/// The now-playing lozenge: what just started playing, shown under a collapsed
/// notch for a few seconds. Cover plus one line, nothing to click.
///
/// The artwork is optional in the strictest sense — while the notch is
/// collapsed no AppleScript runs unless Automation permission was already
/// granted, so a cover may simply never arrive.
struct MediaPopoutView: View {
    let popout: MediaPopout
    let artwork: NSImage?
    let notchSize: CGSize

    var body: some View {
        HStack(spacing: 8) {
            if let artwork {
                ArtworkView(image: artwork, side: 26)
            }
            TrackLabel(title: popout.title, artist: popout.artist, size: 12)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        // Leaves the notch band empty, so the lozenge's own top edge lands on
        // the screen edge exactly like the panel's and its black merges into
        // the notch rather than butting against it.
        .padding(.top, notchSize.height)
        .frame(width: max(notchSize.width, Self.width))
        .notchSurface(cornerRadius: 16)
    }

    /// A constant width rather than one that hugs the title: a lozenge that
    /// resized with every track would jitter under the notch, and the title
    /// truncates anyway. Never narrower than the notch it hangs from.
    private static let width: CGFloat = 300
}
