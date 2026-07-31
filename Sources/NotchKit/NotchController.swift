import AppKit
import SwiftUI
import Combine

/// Owns the panel and wires hover → state machine → panel visibility.
@MainActor
public final class NotchController {
    private let geometry: NotchGeometry?
    private let hover = HoverMonitor()
    private let machine = NotchStateMachine()
    private let store = ScratchpadStore(directory: ScratchpadStore.defaultDirectory)
    private var panel: NotchPanel?
    private var cancellables = Set<AnyCancellable>()
    private var clickMonitor: Any?
    private var localClickMonitor: Any?
    private var escapeMonitor: Any?

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
            content: NotchRoot(
                machine: machine,
                store: store,
                notchWidth: geometry.notchRect.width
            )
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
        watchForEscape()
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

        flushOnClose(state)
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

    /// Escape closes the panel. A local monitor is enough because the panel is
    /// key whenever it is pinned, which is the only time Escape should apply.
    private func watchForEscape() {
        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53 else { return event }   // 53 = Escape
            let shouldSwallow = MainActor.assumeIsolated { () -> Bool in
                guard let self, self.machine.state == .pinned else { return false }
                self.machine.dismiss()
                return true
            }
            return shouldSwallow ? nil : event   // swallow it so the text view never sees Escape
        }
    }

    /// Never leave a pending debounced write unwritten when the panel closes.
    private func flushOnClose(_ state: NotchState) {
        guard state == .collapsed else { return }
        Task { await store.flush() }
    }
}

/// Bridges the observable state machine into the chrome.
private struct NotchRoot: View {
    @ObservedObject var machine: NotchStateMachine
    @ObservedObject var store: ScratchpadStore
    let notchWidth: CGFloat

    var body: some View {
        NotchChrome(state: machine.state, notchWidth: notchWidth) {
            ScratchpadView(store: store, isPinned: machine.state == .pinned)
        }
    }
}
