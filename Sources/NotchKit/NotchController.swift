import AppKit
import SwiftUI
import Combine

/// Owns the panel and wires hover → state machine → panel visibility.
@MainActor
public final class NotchController {
    private var geometry: NotchGeometry?
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
                notchSize: geometry.notchRect.size
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
        watchForScreenChanges()
    }

    /// The panel accepts the mouse only while open, and the hover region grows
    /// to the whole panel so moving down into it does not close it.
    ///
    /// Collapsing orders the panel out rather than merely hiding its content.
    /// That is what releases key status — `resignKey()` must never be called
    /// directly — and it guarantees a collapsed panel can swallow nothing.
    private func apply(_ state: NotchState) {
        guard let geometry, let panel else { return }
        hover.activeRect = state.isOpen ? geometry.openHoverRect : geometry.collapsedHoverRect
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
        if geometry.openHoverRect.contains(NSEvent.mouseLocation) {
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

    /// Display changes move the notch. Collapse first so nothing is stranded
    /// mid-animation, then re-place the panel against the new geometry.
    ///
    /// After re-placing, the state is re-applied rather than ordering the
    /// panel front unconditionally: `dismiss()` above already put the state
    /// machine into `.collapsed`, whose normal handling is to order the panel
    /// OUT. Calling `orderFrontRegardless()` here would fight that and leave
    /// a visible-but-empty panel at the new position. Re-running `apply` with
    /// the current (collapsed) state reconciles frame, hover rect, and
    /// visibility from one source of truth instead of duplicating that logic.
    private func watchForScreenChanges() {
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.machine.dismiss()
                self.geometry = NotchGeometry.forBuiltInScreen()

                guard let geometry = self.geometry else {
                    self.panel?.orderOut(nil)
                    return
                }
                self.panel?.setFrame(geometry.panelFrame, display: true)
                self.apply(self.machine.state)
            }
        }
    }

    public func revealNotes() {
        try? FileManager.default.createDirectory(
            at: store.directoryURL,
            withIntermediateDirectories: true
        )
        NSWorkspace.shared.activateFileViewerSelecting([store.fileURL])
    }
}

/// Bridges the observable state machine into the chrome.
private struct NotchRoot: View {
    @ObservedObject var machine: NotchStateMachine
    @ObservedObject var store: ScratchpadStore
    let notchSize: CGSize

    var body: some View {
        NotchChrome(state: machine.state, notchSize: notchSize) {
            ScratchpadView(store: store, isPinned: machine.state == .pinned)
        }
    }
}
