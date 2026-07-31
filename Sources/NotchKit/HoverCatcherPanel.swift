import AppKit

/// A small always-present window covering the notch, whose only job is to
/// report hover without any permission.
///
/// It accepts mouse events — a tracking area cannot fire in a window that
/// ignores them — which is safe because it is sized to exactly the notch, and
/// the notch is dead space that macOS never places menu bar items behind.
public final class HoverCatcherPanel: NSPanel {
    private let tracker = TrackingView()

    public override var canBecomeKey: Bool { false }
    public override var canBecomeMain: Bool { false }

    public init(frame: CGRect, onHover: @escaping (Bool) -> Void) {
        super.init(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isMovable = false
        hidesOnDeactivate = false
        // One level above the content panel, so hovering the notch still
        // registers here while the panel is open.
        level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        tracker.onHover = onHover
        contentView = tracker
        setFrame(frame, display: true)
    }

    public required init?(coder: NSCoder) {
        fatalError("HoverCatcherPanel is not loaded from a nib")
    }
}
