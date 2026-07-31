import SwiftUI

/// The visible surface that hangs off the notch, and the slot its content
/// lives in. v1 fills the slot with the scratchpad; media controls or a file
/// shelf would drop into the same place without touching anything else.
public struct NotchChrome<Content: View>: View {
    private let state: NotchState
    private let notchSize: CGSize
    private let content: () -> Content

    private static var cornerRadius: CGFloat { 22 }

    public init(
        state: NotchState,
        notchSize: CGSize,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.state = state
        self.notchSize = notchSize
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
        content()
            // The panel's top edge sits under the physical notch, so the first
            // notch-height of the surface is not visible. Reserving it here
            // means every module in the slot clears the notch automatically.
            .padding(.top, notchSize.height)
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
}
