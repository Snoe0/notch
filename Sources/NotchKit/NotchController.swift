import AppKit
import SwiftUI
import Combine

/// Owns the panel and wires hover → state machine → panel visibility.
@MainActor
public final class NotchController {
    private var geometry: NotchGeometry?
    private let cursor = CursorWatcher()
    private let machine = NotchStateMachine()
    private let store = ScratchpadStore(directory: ScratchpadStore.defaultDirectory)
    private let todos = TodoStore(directory: TodoStore.defaultDirectory)
    private let media = MediaController()
    private let popouts = PopoutPresenter()
    private var panel: NotchPanel?
    private var cancellables = Set<AnyCancellable>()
    private var localClickMonitor: Any?
    private var escapeMonitor: Any?
    private var isPollingMedia = false

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
                popouts: popouts,
                store: store,
                todos: todos,
                media: media,
                notchSize: geometry.notchRect.size
            )
        )
        panel.setInteractive(false)
        panel.orderFrontRegardless()
        self.panel = panel

        cursor.activeRect = geometry.collapsedHoverRect
        cursor.onChange = { [weak self] inside in
            self?.machine.hoverChanged(inside: inside)
        }
        cursor.start()

        machine.$state
            .sink { [weak self] state in self?.apply(state) }
            .store(in: &cancellables)

        watchForPlayback()
        watchForClicks()
        watchForKeyLoss()
        watchForEscape()
        watchForScreenChanges()
    }

    /// The panel accepts the mouse only while open, and the watched region
    /// grows to the whole panel so moving down into it does not close it.
    ///
    /// Collapsing orders the panel out rather than merely hiding its content.
    /// That is what releases key status — `resignKey()` must never be called
    /// directly — and it guarantees a collapsed panel can swallow nothing.
    private func apply(_ state: NotchState) {
        guard let geometry, let panel else { return }
        cursor.activeRect = state.isOpen ? geometry.openHoverRect : geometry.collapsedHoverRect
        panel.setInteractive(state.isOpen)

        // Opening takes the lozenge away, which orders the window out; the
        // switch below must have the last word, so this comes first.
        popouts.notchStateChanged(to: state)

        switch state {
        case .collapsed: updateCollapsedPanel(forPopout: popouts.popout)
        case .peek:      panel.orderFrontRegardless()
        case .pinned:    panel.makeKeyAndOrderFront(nil)
        }

        pollMediaWhileOpen(state)
        flushOnClose(state)
    }

    /// A collapsed panel is normally ordered out, which is what releases key
    /// status and guarantees it can swallow nothing. The now-playing lozenge
    /// is the one thing that draws while collapsed, so the window comes back
    /// for exactly as long as one is up — still ignoring the mouse, because
    /// `setInteractive(false)` above already covers the collapsed state.
    private func updateCollapsedPanel(forPopout popout: MediaPopout?) {
        guard let panel else { return }
        if popout == nil {
            panel.orderOut(nil)
        } else {
            panel.orderFrontRegardless()
        }
    }

    /// Playback announcements decide the lozenge; the lozenge decides whether
    /// a collapsed panel is on screen at all.
    private func watchForPlayback() {
        media.playbackEvents
            .sink { [weak self] nowPlaying in
                guard let self else { return }
                self.popouts.playbackChanged(to: nowPlaying, while: self.machine.state)
            }
            .store(in: &cancellables)

        popouts.$popout
            .sink { [weak self] popout in
                // `@Published` fires before the property changes, so this can
                // run mid-`apply` with a stale state. Ordering out in that
                // window is harmless: `apply` re-orders the panel right after.
                guard let self, self.machine.state == .collapsed else { return }
                self.updateCollapsedPanel(forPopout: popout)
            }
            .store(in: &cancellables)
    }

    /// Each poll tick costs an `osascript` round trip, so polling runs only
    /// while the panel is open — which is also why the Automation prompt
    /// appears on first open rather than at launch. Only the transition acts:
    /// re-starting on peek → pinned would reset the tick for nothing.
    private func pollMediaWhileOpen(_ state: NotchState) {
        guard state.isOpen != isPollingMedia else { return }
        isPollingMedia = state.isOpen
        if state.isOpen {
            media.startPolling()
        } else {
            media.stopPolling()
        }
    }

    /// A click in one of our own windows pins the panel. A local monitor is
    /// enough and, unlike the global variant, needs no Input Monitoring grant.
    private func watchForClicks() {
        localClickMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] event in
            MainActor.assumeIsolated {
                guard let self else { return }
                if event.window === self.panel {
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
        Task {
            await store.flush()
            await todos.flush()
        }
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
                    self.cursor.stop()
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
        NSWorkspace.shared.activateFileViewerSelecting([store.fileURL, todos.fileURL])
    }
}

/// Bridges the observable state machine into the chrome.
private struct NotchRoot: View {
    @ObservedObject var machine: NotchStateMachine
    @ObservedObject var popouts: PopoutPresenter
    let store: ScratchpadStore
    let todos: TodoStore
    @ObservedObject var media: MediaController
    let notchSize: CGSize

    var body: some View {
        NotchChrome(
            state: machine.state,
            notchSize: notchSize,
            popout: popouts.popout,
            artwork: media.artwork
        ) {
            MediaControlsView(media: media)
        } content: {
            PanelContentView(
                todos: todos,
                scratchpad: store,
                isPinned: machine.state == .pinned
            )
        }
    }
}
