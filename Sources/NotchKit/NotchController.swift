import AppKit
import SwiftUI
import Combine

/// Owns the panel and wires hover → state machine → panel visibility.
@MainActor
public final class NotchController {
    private let geometry: NotchGeometry?
    private let hover = HoverMonitor()
    private let machine = NotchStateMachine()
    private var panel: NotchPanel?
    private var cancellables = Set<AnyCancellable>()
    private var clickMonitor: Any?
    private var localClickMonitor: Any?

    public init() {
        geometry = NotchGeometry.forBuiltInScreen()
    }

    public func start() {
        guard let geometry else {
            print("Notch: no built-in notch on this Mac — staying dormant.")
            return
        }

        let panel = NotchPanel(
            frame: geometry.panelFrame,
            content: PlaceholderView(machine: machine)
        )
        panel.setInteractive(false)
        panel.orderFrontRegardless()
        self.panel = panel

        hover.activeRect = geometry.collapsedHoverRect
        hover.onChange = { [weak self] inside in
            self?.machine.hoverChanged(inside: inside)
        }
        hover.start()

        machine.$state
            .sink { [weak self] state in self?.apply(state) }
            .store(in: &cancellables)

        watchForClicks()
    }

    /// The panel accepts the mouse only while open, and the hover region grows
    /// to the whole panel so moving down into it does not close it.
    ///
    /// Collapsing orders the panel out rather than merely hiding its content.
    /// That is what releases key status — `resignKey()` must never be called
    /// directly — and it guarantees a collapsed panel can swallow nothing.
    private func apply(_ state: NotchState) {
        guard let geometry, let panel else { return }
        hover.activeRect = state.isOpen ? geometry.panelFrame : geometry.collapsedHoverRect
        panel.setInteractive(state.isOpen)

        switch state {
        case .collapsed: panel.orderOut(nil)
        case .peek:      panel.orderFrontRegardless()
        case .pinned:    panel.makeKeyAndOrderFront(nil)
        }
    }

    /// A click inside the open panel pins it; a click anywhere else dismisses it.
    ///
    /// Both monitors are needed. The global one never fires for events routed
    /// to our own app, so once the panel accepts the mouse only the local one
    /// sees clicks landing on it.
    private func watchForClicks() {
        let mask: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown]

        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] _ in
            MainActor.assumeIsolated { self?.handleClick() }
        }
        localClickMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            MainActor.assumeIsolated { self?.handleClick() }
            return event
        }
    }

    private func handleClick() {
        guard let geometry else { return }
        if geometry.panelFrame.contains(NSEvent.mouseLocation) {
            machine.click()
        } else {
            machine.dismiss()
        }
    }
}

private struct PlaceholderView: View {
    @ObservedObject var machine: NotchStateMachine

    var body: some View {
        VStack(spacing: 0) {
            if machine.state.isOpen {
                Rectangle()
                    .fill(machine.state == .pinned ? .green.opacity(0.6) : .red.opacity(0.6))
                    .frame(width: 320, height: 120)
                    .transition(.scale(scale: 0.92, anchor: .top).combined(with: .opacity))
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(.spring(response: 0.32, dampingFraction: 0.78), value: machine.state)
    }
}
