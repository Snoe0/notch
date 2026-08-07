import AppKit
import SwiftUI

/// The floating notes window: the same scratchpad column as the panel, in a
/// compact always-on-top panel that stays visible while the user works
/// elsewhere.
///
/// Unlike the notch panel this is an ordinary user window — titled, closable,
/// activating — so typing in it just works. `.floating` keeps it above normal
/// windows without contesting system UI, and `.canJoinAllSpaces` (deliberately
/// without `.fullScreenAuxiliary`) makes it follow the user across desktops
/// while leaving full-screen spaces alone: pinned notes over a spreadsheet
/// are the point, pinned notes over a full-screen film are not.
final class NotesPopoutPanel: NSPanel {
    override var canBecomeKey: Bool { true }

    init(frame: NSRect) {
        super.init(
            contentRect: frame,
            styleMask: [.titled, .closable, .resizable, .utilityWindow, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        // The panel chrome's look: solid black, title bar melted into it.
        title = "Notes"
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        backgroundColor = .black
        appearance = NSAppearance(named: .darkAqua)

        level = .floating
        collectionBehavior = [.canJoinAllSpaces]
        hidesOnDeactivate = false          // utility panels default to hiding
        isReleasedWhenClosed = false       // closed is hidden; the controller reuses it
        isMovableByWindowBackground = true
        minSize = NSSize(width: 240, height: 180)
    }

    /// `NSWindow` conforms to `NSCoding`, so declaring a designated
    /// initializer above forces this one to be provided. It is never used.
    required init?(coder: NSCoder) {
        fatalError("NotesPopoutPanel is not loaded from a nib")
    }
}

/// Owns the floating notes window and keeps it in step with the presenter.
///
/// The scratchpad content is mounted on show and torn down on hide rather
/// than kept alive off screen: removing the hosting view runs the column's
/// `onDisappear` flushes (the sketch store lives inside the view), and the
/// next pop-out starts on the notes face like the panel does. The window
/// itself survives hides so `frameAutosaveName` keeps its place across
/// pop-outs and relaunches.
@MainActor
final class NotesPopoutWindowController: NSObject, NSWindowDelegate {
    private let presenter: NotesPopoutPresenter
    private let store: ScratchpadStore
    private var panel: NotesPopoutPanel?

    private static let autosaveName = "NotesPopout"

    init(presenter: NotesPopoutPresenter, store: ScratchpadStore) {
        self.presenter = presenter
        self.store = store
    }

    func show() {
        let panel = self.panel ?? makePanel()
        self.panel = panel
        panel.contentView = NSHostingView(rootView: windowRoot)
        panel.makeKeyAndOrderFront(nil)
        // The click that popped the notes out landed in the non-activating
        // notch panel, so the app may not be active — and only an active
        // app's key window gets keystrokes.
        NSApp.activate()
    }

    func hide() {
        guard let panel else { return }
        panel.contentView = nil            // tears down the column → flushes run
        panel.orderOut(nil)
    }

    /// The close box goes through the presenter so the panel's placeholder
    /// clears too; the presenter ignores the echo when `hide` follows.
    func windowWillClose(_ notification: Notification) {
        presenter.returnToPanel()
    }

    /// The same column the panel shows, with clearance for the close box in
    /// the hidden title bar.
    private var windowRoot: some View {
        ScratchpadView(store: store, popout: presenter, isPinned: true, isPopoutWindow: true)
            .padding(.top, 14)
    }

    private func makePanel() -> NotesPopoutPanel {
        let panel = NotesPopoutPanel(frame: Self.defaultFrame())
        panel.delegate = self
        panel.setFrameAutosaveName(Self.autosaveName)
        panel.setFrameUsingName(Self.autosaveName)
        return panel
    }

    /// First launch only — afterwards the autosaved frame wins: top-right of
    /// the screen, out of the notch panel's way.
    private static func defaultFrame() -> NSRect {
        let size = NSSize(width: 300, height: 240)
        guard let visible = NSScreen.main?.visibleFrame else {
            return NSRect(origin: .zero, size: size)
        }
        return NSRect(
            x: visible.maxX - size.width - 24,
            y: visible.maxY - size.height - 24,
            width: size.width,
            height: size.height
        )
    }
}
