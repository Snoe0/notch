import AppKit
import SwiftUI
import Combine

/// Owns the panel and wires hover → state machine → panel visibility.
@MainActor
public final class NotchController {
    private var geometry: NotchGeometry?
    private var catcher: HoverCatcherPanel?
    private var catcherInside = false
    private var panelInside = false
    private let machine = NotchStateMachine()
    private let store = ScratchpadStore(directory: ScratchpadStore.defaultDirectory)
    private var panel: NotchPanel?
    private var cancellables = Set<AnyCancellable>()
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
            ),
            onHover: { [weak self] inside in
                self?.panelInside = inside
                self?.updateHover()
            }
        )
        panel.setInteractive(false)
        panel.orderFrontRegardless()
        self.panel = panel

        let catcher = HoverCatcherPanel(frame: geometry.catcherFrame) { [weak self] inside in
            self?.catcherInside = inside
            self?.updateHover()
        }
        catcher.orderFrontRegardless()
        self.catcher = catcher

        machine.$state
            .sink { [weak self] state in self?.apply(state) }
            .store(in: &cancellables)

        watchForClicks()
        watchForKeyLoss()
        watchForEscape()
        watchForScreenChanges()
    }

    /// The cursor counts as hovering if it is over the notch or anywhere in the
    /// open panel. Two tracked windows, one answer.
    private func updateHover() {
        machine.hoverChanged(inside: catcherInside || panelInside)
    }

    /// The panel accepts the mouse only while open.
    ///
    /// Collapsing orders the panel out rather than merely hiding its content.
    /// That is what releases key status — `resignKey()` must never be called
    /// directly — and it guarantees a collapsed panel can swallow nothing.
    private func apply(_ state: NotchState) {
        guard let panel else { return }
        panel.setInteractive(state.isOpen)

        switch state {
        case .collapsed: panel.orderOut(nil)
        case .peek:      panel.orderFrontRegardless()
        case .pinned:    panel.makeKeyAndOrderFront(nil)
        }

        flushOnClose(state)
    }

    /// A click in one of our own windows pins the panel. A local monitor is
    /// enough and, unlike the global variant, needs no Input Monitoring grant.
    private func watchForClicks() {
        localClickMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] event in
            MainActor.assumeIsolated {
                guard let self else { return }
                if event.window === self.panel || event.window === self.catcher {
                    self.machine.click()
                }
            }
            return event
        }
    }

    /// Clicking another app makes the pinned panel resign key, which is how
    /// click-outside dismissal works without watching other apps' events.
    private func watchForKeyLoss() {
        NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification,
            object: panel,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.machine.state == .pinned else { return }
                self.machine.dismiss()
            }
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
                    self.catcher?.orderOut(nil)
                    return
                }
                self.panel?.setFrame(geometry.panelFrame, display: true)
                self.catcher?.setFrame(geometry.catcherFrame, display: true)
                self.catcher?.orderFrontRegardless()
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
