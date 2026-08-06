import SwiftUI

/// The visible surface that hangs off the notch: a notch-height top strip and
/// the content slot below it. Both are slots — the chrome only knows where the
/// physical notch is, never what is drawn around it.
public struct NotchChrome<TopLeading: View, Content: View>: View {
    private let state: NotchState
    private let notchSize: CGSize
    private let topLeading: () -> TopLeading
    private let content: () -> Content

    private static var cornerRadius: CGFloat { 22 }

    public init(
        state: NotchState,
        notchSize: CGSize,
        @ViewBuilder topLeading: @escaping () -> TopLeading,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.state = state
        self.notchSize = notchSize
        self.topLeading = topLeading
        self.content = content
    }

    public var body: some View {
        VStack(spacing: 0) {
            if state.isOpen {
                surface
                    .transition(
                        .scale(scale: 0.9, anchor: .top).combined(with: .opacity)
                    )
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(.spring(response: 0.34, dampingFraction: 0.8), value: state)
    }

    private var surface: some View {
        VStack(spacing: 0) {
            topStrip
            content()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .frame(minWidth: notchSize.width)
        .background(.black)
        // Square at the top so the panel merges into the notch and the
        // screen edge; rounded at the bottom so it reads as a lozenge.
        .clipShape(
            .rect(
                topLeadingRadius: 0,
                bottomLeadingRadius: Self.cornerRadius,
                bottomTrailingRadius: Self.cornerRadius,
                topTrailingRadius: 0
            )
        )
        .overlay(alignment: .bottom) {
            UnevenRoundedRectangle(
                topLeadingRadius: 0,
                bottomLeadingRadius: Self.cornerRadius,
                bottomTrailingRadius: Self.cornerRadius,
                topTrailingRadius: 0
            )
            .strokeBorder(.white.opacity(0.08), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.5), radius: 18, y: 8)
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
