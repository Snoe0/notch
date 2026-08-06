import AppKit
import SwiftUI

/// The visible surface that hangs off the notch: a notch-height top strip and
/// the content slot below it. Both are slots — the chrome only knows where the
/// physical notch is, never what is drawn around it.
///
/// While the notch is collapsed the same frame is where the now-playing chip
/// appears, so the chrome also knows how to slide one out beside the notch.
public struct NotchChrome<TopLeading: View, Content: View>: View {
    private let state: NotchState
    private let notchSize: CGSize
    private let popout: MediaPopout?
    private let artwork: NSImage?
    private let topLeading: () -> TopLeading
    private let content: () -> Content

    static var animation: Animation { .spring(response: 0.34, dampingFraction: 0.8) }

    /// The artwork travels beside the popout rather than inside it, because it
    /// is fetched separately and often arrives once the chip is already up.
    public init(
        state: NotchState,
        notchSize: CGSize,
        popout: MediaPopout? = nil,
        artwork: NSImage? = nil,
        @ViewBuilder topLeading: @escaping () -> TopLeading,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.state = state
        self.notchSize = notchSize
        self.popout = popout
        self.artwork = artwork
        self.topLeading = topLeading
        self.content = content
    }

    /// The open panel always wins: a chip only ever stands in for content that
    /// is not on screen.
    public var body: some View {
        VStack(spacing: 0) {
            if state.isOpen {
                surface.transition(Self.dropIn)
            } else {
                chipBand
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(Self.animation, value: state)
        .animation(Self.animation, value: popout)
    }

    private static var dropIn: AnyTransition {
        .scale(scale: 0.9, anchor: .top).combined(with: .opacity)
    }

    private var surface: some View {
        VStack(spacing: 0) {
            topStrip
            content()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .frame(minWidth: notchSize.width)
        .notchSurface()
    }

    /// Sits in the notch band itself, right edge against the notch, growing
    /// leftwards into the flank. Non-interactive by construction: while
    /// collapsed the panel ignores mouse events entirely.
    ///
    /// The band is always here while the notch is collapsed, empty or not, so
    /// the chip is the only thing that ever animates: were the clip itself
    /// coming and going, SwiftUI would fade it in and out around the slide.
    ///
    /// Accepted trade-off: for the ~3 seconds it is up, the chip may cover menu
    /// titles of an app whose menus reach the notch's left flank. It is
    /// mouse-transparent, so the menus stay clickable throughout and the band
    /// is its own again a moment later.
    private var chipBand: some View {
        notchBand(alignment: .trailing) {
            if let popout {
                MediaPopoutView(popout: popout, artwork: artwork)
                    .transition(Self.slideOutOfNotch)
            }
        }
    }

    /// The chip leaves the way it came in. `move(edge: .trailing)` offsets it by
    /// its own width, which lands it exactly behind the notch, and the band's
    /// clip takes it from there — so it emerges from under the hardware rather
    /// than fading in place.
    private static var slideOutOfNotch: AnyTransition {
        .move(edge: .trailing)
    }

    /// The band the physical notch covers: a usable slot on each side of it and
    /// dead space in the middle. The surface is centred on the notch, so the
    /// two flanks are equal — the trailing one is deliberately left empty.
    private var topStrip: some View {
        notchBand(alignment: .leading) { topLeading() }
    }

    /// The notch's leading flank, the only part of the band anything may be
    /// drawn in. The open surface's top strip and the collapsed chip both live
    /// here, so the clip that keeps content out from under the notch — and
    /// hides the chip while it is behind it — is written once.
    private func notchBand<Slot: View>(
        alignment: Alignment,
        @ViewBuilder slot: () -> Slot
    ) -> some View {
        let slot = slot()
        return GeometryReader { proxy in
            HStack(spacing: 0) {
                slot
                    .frame(width: flankWidth(in: proxy.size.width), alignment: alignment)
                    // Nothing may spill under the notch, whatever the slot draws.
                    .clipped()
                Spacer(minLength: 0)
            }
        }
        .frame(height: notchSize.height)
    }

    /// Measured rather than derived from `expandedSize`, because the surface
    /// stretches to whatever width it is given and only its minimum is known
    /// here.
    private func flankWidth(in surfaceWidth: CGFloat) -> CGFloat {
        max(0, (surfaceWidth - notchSize.width) / 2)
    }
}

extension View {
    /// The panel surface: black, square at the top so it merges into the notch
    /// and the screen edge, rounded below so it reads as a lozenge, hairline
    /// border, one soft shadow.
    func notchSurface(cornerRadius: CGFloat = 22) -> some View {
        let shape = UnevenRoundedRectangle(
            topLeadingRadius: 0,
            bottomLeadingRadius: cornerRadius,
            bottomTrailingRadius: cornerRadius,
            topTrailingRadius: 0
        )
        return background(.black)
            .clipShape(shape)
            .overlay(alignment: .bottom) {
                shape.strokeBorder(.white.opacity(0.08), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.5), radius: 18, y: 8)
    }

    /// The now-playing chip: the same black and the same corner idiom, square
    /// on the three edges it shares with something — the screen top, and the
    /// notch on its trailing side — and rounded only on the outer bottom
    /// corner it turns back on.
    ///
    /// Deliberately lighter than `notchSurface`: no border, no shadow. The chip
    /// lives *inside* the notch band rather than hanging below it, and the
    /// hardware notch it must read as an extension of casts neither — a
    /// hairline would draw a seam down the junction, and a shadow would be cut
    /// off by the clip that hides the chip behind the notch anyway.
    func notchChipSurface(cornerRadius: CGFloat = 12) -> some View {
        let shape = UnevenRoundedRectangle(
            topLeadingRadius: 0,
            bottomLeadingRadius: cornerRadius,
            bottomTrailingRadius: 0,
            topTrailingRadius: 0
        )
        return background(.black).clipShape(shape)
    }
}
