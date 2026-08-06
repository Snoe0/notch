import AppKit
import SwiftUI

/// The visible surface that hangs off the notch: a notch-height top strip and
/// the content slot below it. Both are slots — the chrome only knows where the
/// physical notch is, never what is drawn around it.
///
/// While the notch is collapsed the same frame is where the now-playing
/// lozenge appears, so the chrome also knows how to hang one under the notch.
public struct NotchChrome<TopLeading: View, Content: View>: View {
    private let state: NotchState
    private let notchSize: CGSize
    private let popout: MediaPopout?
    private let artwork: NSImage?
    private let topLeading: () -> TopLeading
    private let content: () -> Content

    static var animation: Animation { .spring(response: 0.34, dampingFraction: 0.8) }

    /// The artwork travels beside the popout rather than inside it, because it
    /// is fetched separately and often arrives once the lozenge is already up.
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

    /// The open panel always wins: a lozenge only ever stands in for content
    /// that is not on screen.
    public var body: some View {
        VStack(spacing: 0) {
            if state.isOpen {
                surface.transition(Self.dropIn)
            } else if let popout {
                lozenge(for: popout).transition(Self.dropIn)
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

    /// Hangs off the notch, centred on it because the panel itself is.
    /// Non-interactive by construction: while collapsed the panel ignores
    /// mouse events entirely.
    private func lozenge(for popout: MediaPopout) -> some View {
        MediaPopoutView(popout: popout, artwork: artwork, notchSize: notchSize)
    }

    /// The band the physical notch covers: a usable slot on each side of it and
    /// dead space in the middle. The surface is centred on the notch, so the
    /// two flanks are equal — the trailing one is deliberately left empty.
    private var topStrip: some View {
        GeometryReader { proxy in
            HStack(spacing: 0) {
                topLeading()
                    .frame(width: flankWidth(in: proxy.size.width))
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
    /// The look shared by the panel surface and the now-playing lozenge:
    /// black, square at the top so it merges into the notch and the screen
    /// edge, rounded below so it reads as a lozenge, hairline border, one
    /// soft shadow.
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
}
