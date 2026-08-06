import SwiftUI

/// The now-playing chip: what just started playing, shown for a few seconds in
/// the menu bar band beside a collapsed notch. Cover, one line, the motion
/// lines — nothing to click.
///
/// It carries no geometry of its own: the chrome hands it the notch's leading
/// flank to live in, so it hugs its content, fills the band's height, and
/// truncates when a long title runs out of flank.
///
/// The artwork is optional in the strictest sense — while the notch is
/// collapsed no AppleScript runs unless Automation permission was already
/// granted, so a cover may simply never arrive.
struct MediaPopoutView: View {
    let popout: MediaPopout
    let artwork: NSImage?

    var body: some View {
        HStack(spacing: 8) {
            if let artwork {
                ArtworkView(image: artwork, side: 20)
            }
            TrackLabel(title: popout.title, artist: popout.artist, size: 11)
            EqualizerBars()
        }
        .padding(.leading, 12)
        .padding(.trailing, 11)
        // Fills the notch band rather than sizing to the row, so the black
        // reaches the screen edge above and the notch's own bottom below.
        .frame(maxHeight: .infinity)
        .notchChipSurface()
    }
}

/// The music motion lines: three bars breathing out of step, so the chip reads
/// as "playing" without pretending to be a level meter. The chip only exists
/// while something is playing, so they never need a resting state.
///
/// Driven by the clock rather than by `repeatForever` animations: those have to
/// start on appear, which is exactly when the chip is sliding out of the notch,
/// and the first cycle tends to be lost to the transition.
struct EqualizerBars: View {
    var body: some View {
        TimelineView(.animation) { context in
            HStack(alignment: .center, spacing: Self.spacing) {
                ForEach(Self.waves.indices, id: \.self) { index in
                    bar(height: Self.span * Self.waves[index].scale(at: context.date))
                }
            }
            .frame(height: Self.span)
        }
    }

    private func bar(height: CGFloat) -> some View {
        Capsule()
            .fill(.white.opacity(0.55))
            .frame(width: Self.thickness, height: height)
    }

    /// Periods close enough to read as one gesture, unrelated enough that the
    /// three bars never fall into step within the chip's few seconds.
    private static let waves = [
        Wave(period: 0.92, phase: 0),
        Wave(period: 1.27, phase: 0.4),
        Wave(period: 1.09, phase: 0.75),
    ]

    private static let span: CGFloat = 11
    private static let thickness: CGFloat = 2.5
    private static let spacing: CGFloat = 2.5

    private struct Wave {
        let period: Double
        let phase: Double

        /// The share of the full span this bar takes at a moment: a sine that
        /// never falls below a third, so no bar collapses to nothing.
        func scale(at date: Date) -> CGFloat {
            let turns = date.timeIntervalSinceReferenceDate / period + phase
            let swing = (sin(turns * 2 * .pi) + 1) / 2
            return 0.34 + 0.66 * swing
        }
    }
}
