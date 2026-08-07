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

    /// Expanding rides a gentle spring with just enough give to settle softly;
    /// collapsing is a touch quicker and strictly eased — the panel is hover
    /// UI, so it should arrive with a little life and leave without ceremony.
    static var expand: Animation { .spring(response: 0.34, dampingFraction: 0.78) }
    static var collapse: Animation { .easeIn(duration: 0.22) }

    /// The chip's slide keeps its own spring, independent of the open/close
    /// pair above, so tuning the panel never changes how the chip emerges.
    static var chipSlide: Animation { .spring(response: 0.34, dampingFraction: 0.8) }

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
        // The animation is picked per direction: the branch below re-evaluates
        // with the *new* state, so opening lands on the spring and closing on
        // the ease — one symmetric transition, two feels.
        .animation(state.isOpen ? Self.expand : Self.collapse, value: state)
        .animation(Self.chipSlide, value: popout)
    }

    private static var dropIn: AnyTransition {
        .scale(scale: 0.9, anchor: .top).combined(with: .opacity)
    }

    /// The chrome leads and the content follows: on expand the columns fade in
    /// a beat after the black surface starts growing, and on collapse they
    /// clear out quickly so no text is caught mid-shrink. The stagger is why
    /// these carry their own animations instead of riding the transaction's.
    private static var slotFade: AnyTransition {
        .asymmetric(
            insertion: .opacity.animation(.easeOut(duration: 0.2).delay(0.07)),
            removal: .opacity.animation(.easeIn(duration: 0.1))
        )
    }

    private var surface: some View {
        VStack(spacing: 0) {
            topStrip
            content()
                .transition(Self.slotFade)
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
        notchBand(alignment: .trailing, overhang: Self.notchOverhang) {
            if let popout {
                MediaPopoutView(
                    popout: popout,
                    artwork: artwork,
                    notchOverhang: Self.notchOverhang
                )
                .transition(Self.slideOutOfNotch)
            }
        }
    }

    /// How far the chip's black extends under the physical notch. The reported
    /// notch rect and the hardware cutout can disagree by a point or two, and
    /// a chip clipped exactly at the reported edge shows that disagreement as
    /// a seam of wallpaper between chip and notch. Points drawn under the
    /// cutout are invisible, so overshooting is free — the same reasoning as
    /// `NotchGeometry.topOvershoot`.
    static var notchOverhang: CGFloat { 12 }

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
        notchBand(alignment: .leading) {
            topLeading()
                // Same stagger as the content slot, so the media controls and
                // the columns below them arrive as one.
                .transition(Self.slotFade)
        }
    }

    /// The notch's leading flank, the only part of the band anything may be
    /// drawn in. The open surface's top strip and the collapsed chip both live
    /// here, so the clip that keeps content out from under the notch — and
    /// hides the chip while it is behind it — is written once.
    private func notchBand<Slot: View>(
        alignment: Alignment,
        overhang: CGFloat = 0,
        @ViewBuilder slot: () -> Slot
    ) -> some View {
        let slot = slot()
        return GeometryReader { proxy in
            HStack(spacing: 0) {
                slot
                    .frame(
                        width: flankWidth(in: proxy.size.width) + overhang,
                        alignment: alignment
                    )
                Spacer(minLength: 0)
            }
            // A static mask on the band, not `.clipped()` on the slot: the
            // slide transition lives inside the slot's modifier chain and its
            // offset could paint past a clip that animates with it — on
            // hardware the chip's edge showed on the far side of the notch
            // mid-slide. The band itself never transitions, so a mask here
            // bounds the finished rendering no matter what moves inside.
            .mask(alignment: .leading) {
                Rectangle()
                    .frame(width: flankWidth(in: proxy.size.width) + overhang)
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
    /// border.
    ///
    /// No shadow: the surface fills the panel window edge to edge, so a shadow
    /// has nowhere legitimate to land — the window clips it everywhere except
    /// inside the corner cutouts, where it puddles into a hard-edged grey
    /// square over the wallpaper.
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
