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
    private let pomodoro = PomodoroTimer()
    private let notesPopout = NotesPopoutPresenter()
    private let settings = PanelSettings()
    /// One instance for the whole app: the panel column, the floating notes
    /// window, and the settings form all observe it, so a font picked in
    /// Settings lands in every host at once.
    private let fontSetting = ScratchpadFontSetting()
    private var notesWindow: NotesPopoutWindowController?
    private var settingsWindow: SettingsWindowController?
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
                settings: settings,
                store: store,
                todos: todos,
                media: media,
                pomodoro: pomodoro,
                notesPopout: notesPopout,
                fontSetting: fontSetting,
                notchSize: geometry.notchRect.size
            )
        )
        panel.setInteractive(false)
        panel.orderFrontRegardless()
        self.panel = panel
        notesWindow = NotesPopoutWindowController(
            presenter: notesPopout,
            store: store,
            fontSetting: fontSetting
        )

        cursor.activeRect = geometry.collapsedHoverRect
        cursor.onChange = { [weak self] inside in
            self?.machine.hoverChanged(inside: inside)
        }
        cursor.start()

        machine.$state
            .sink { [weak self] state in self?.apply(state) }
            .store(in: &cancellables)

        watchForPlayback()
        watchForNotesPopout()
        watchForMediaSetting()
        watchForPomodoroCompletions()
        watchForClicks()
        watchForKeyLoss()
        watchForEscape()
        watchForScreenChanges()
    }

    /// The panel accepts the mouse only while open, and the watched region
    /// grows to the whole panel so moving down into it does not close it.
    private func apply(_ state: NotchState) {
        guard let geometry, let panel else { return }
        cursor.activeRect = state.isOpen ? geometry.openHoverRect : geometry.collapsedHoverRect
        panel.setInteractive(state.isOpen)

        // Opening takes the lozenge away; done first so the ordering switch
        // below always has the last word.
        popouts.notchStateChanged(to: state)

        switch state {
        case .collapsed: shedKeyKeepingPanelOnScreen()
        case .peek:      panel.orderFrontRegardless()
        case .pinned:    panel.makeKeyAndOrderFront(nil)
        }

        pollMediaWhileOpen(state)
        flushOnClose(state)
    }

    /// Collapsing must release key status — `resignKey()` must never be called
    /// directly, and ordering out is what actually sheds it — but the window
    /// itself stays on screen: transparent, mouse-ignoring, and live. It has
    /// to, because SwiftUI does not reliably animate in a window that is off
    /// screen — a now-playing chip inserted while the window was being ordered
    /// back in committed straight to its final position instead of sliding out
    /// of the notch. The out-and-back pair lands in one window-server
    /// transaction, so nothing visibly blinks.
    private func shedKeyKeepingPanelOnScreen() {
        guard let panel else { return }
        panel.orderOut(nil)
        panel.orderFrontRegardless()
    }

    /// Playback announcements decide the lozenge; the always-on-screen
    /// collapsed panel means showing one needs no window management at all.
    private func watchForPlayback() {
        media.playbackEvents
            .sink { [weak self] nowPlaying in
                guard let self else { return }
                self.popouts.playbackChanged(to: nowPlaying, while: self.machine.state)
            }
            .store(in: &cancellables)
    }

    /// Shows or hides the floating notes window as the notes change host, and
    /// flushes the scratchpad on every switch: the debounce must never be the
    /// only thing holding an edit while its editor is being torn down. The
    /// sketch flushes itself from the view (`onDisappear`), same as on panel
    /// collapse.
    private func watchForNotesPopout() {
        notesPopout.$isPoppedOut
            .dropFirst()
            .sink { [weak self] isPoppedOut in
                guard let self else { return }
                if isPoppedOut {
                    self.notesWindow?.show()
                } else {
                    self.notesWindow?.hide()
                }
                Task { await self.store.flush() }
            }
            .store(in: &cancellables)
    }

    /// A finished work or break interval gets a system sound and nothing more:
    /// `NSSound` needs no entitlement and no prompt, unlike user
    /// notifications, and this app asks for zero permissions.
    private func watchForPomodoroCompletions() {
        pomodoro.phaseCompletions
            .sink { _ in NSSound(named: "Glass")?.play() }
            .store(in: &cancellables)
    }

    /// Each poll tick costs an `osascript` round trip, so polling runs only
    /// while the panel is open — which is also why the Automation prompt
    /// appears on first open rather than at launch — and only while the media
    /// strip is enabled at all: with the strip and its chip both off, a poll
    /// would fetch state nothing draws. Only the transition acts: re-starting
    /// on peek → pinned would reset the tick for nothing.
    private func pollMediaWhileOpen(_ state: NotchState) {
        updateMediaPolling(state: state, showsMedia: settings.showsMedia)
    }

    /// The settings toggle feeds the same reconciliation as the state machine,
    /// with the incoming value — `$showsMedia` emits before the property is
    /// written, so reading `settings` here would see the old one.
    private func watchForMediaSetting() {
        settings.$showsMedia
            .dropFirst()
            .sink { [weak self] showsMedia in
                guard let self else { return }
                self.updateMediaPolling(state: self.machine.state, showsMedia: showsMedia)
            }
            .store(in: &cancellables)
    }

    private func updateMediaPolling(state: NotchState, showsMedia: Bool) {
        let shouldPoll = state.isOpen && showsMedia
        guard shouldPoll != isPollingMedia else { return }
        isPollingMedia = shouldPoll
        if shouldPoll {
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
    /// panel front by hand: re-running `apply` with the current (collapsed)
    /// state reconciles frame, hover rect, interactivity, and ordering from
    /// one source of truth instead of duplicating that logic here.
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

    /// Created lazily rather than in `start()`: the settings window must work
    /// even on a Mac without a notch, where `start()` bails before wiring
    /// anything — the panel may be dormant, but its configuration is not.
    public func showSettings() {
        let window = settingsWindow
            ?? SettingsWindowController(settings: settings, fontSetting: fontSetting)
        settingsWindow = window
        window.show()
    }

    public func revealNotes() {
        try? FileManager.default.createDirectory(
            at: store.directoryURL,
            withIntermediateDirectories: true
        )
        NSWorkspace.shared.activateFileViewerSelecting([store.fileURL, todos.fileURL])
    }
}

/// Bridges the observable state machine and the settings into the chrome.
private struct NotchRoot: View {
    @ObservedObject var machine: NotchStateMachine
    @ObservedObject var popouts: PopoutPresenter
    @ObservedObject var settings: PanelSettings
    let store: ScratchpadStore
    let todos: TodoStore
    @ObservedObject var media: MediaController
    @ObservedObject var pomodoro: PomodoroTimer
    let notesPopout: NotesPopoutPresenter
    let fontSetting: ScratchpadFontSetting
    let notchSize: CGSize

    /// The pomodoro chip mirrors the now-playing lozenge but needs no
    /// presenter: it has no expiry and no announcement policy — it is up
    /// exactly while the timer runs and its surface is enabled, and the
    /// chrome already ignores it whenever the panel is open.
    private var pomodoroChip: PomodoroChip? {
        guard settings.showsPomodoro, pomodoro.isRunning else { return nil }
        return PomodoroChip(phase: pomodoro.phase, remaining: pomodoro.remaining)
    }

    private var mediaFlank: HorizontalEdge {
        settings.swapsFlanks ? .trailing : .leading
    }

    var body: some View {
        NotchChrome(
            state: machine.state,
            notchSize: notchSize,
            popout: settings.showsMedia ? popouts.popout : nil,
            artwork: media.artwork,
            pomodoroChip: pomodoroChip,
            mediaFlank: mediaFlank,
            showsContent: settings.showsTodos || settings.showsNotes
        ) {
            strip(on: .leading)
        } topTrailing: {
            strip(on: .trailing)
        } content: {
            PanelContentView(
                todos: todos,
                scratchpad: store,
                notesPopout: notesPopout,
                fontSetting: fontSetting,
                isPinned: machine.state == .pinned,
                showsTodos: settings.showsTodos,
                showsNotes: settings.showsNotes,
                swapsColumns: settings.swapsColumns
            )
        }
    }

    /// The strip a flank shows: media on `mediaFlank`, pomodoro on the other,
    /// either one absent when its settings toggle is off. The flank is passed
    /// along so each strip mirrors itself against the notch.
    @ViewBuilder
    private func strip(on flank: HorizontalEdge) -> some View {
        if flank == mediaFlank {
            if settings.showsMedia {
                MediaControlsView(media: media, flank: flank)
            }
        } else if settings.showsPomodoro {
            PomodoroControlsView(timer: pomodoro, flank: flank)
        }
    }
}
