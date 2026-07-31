import AppKit
import SwiftUI

/// Owns the panel and drives it from the state machine.
@MainActor
public final class NotchController {
    private var panel: NotchPanel?
    private let geometry: NotchGeometry?

    public init() {
        geometry = NotchGeometry.forBuiltInScreen()
    }

    public func start() {
        guard let geometry else {
            print("Notch: no built-in notch on this Mac — staying dormant.")
            return
        }
        let panel = NotchPanel(frame: geometry.panelFrame, content: PlaceholderView())
        panel.setInteractive(false)
        panel.orderFrontRegardless()
        self.panel = panel
    }
}

private struct PlaceholderView: View {
    var body: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(.red.opacity(0.6))
                .frame(width: 320, height: 120)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}
