import AppKit
import SwiftUI

public final class NotchPanel: NSPanel {
    public override var canBecomeKey: Bool { true }
    public override var canBecomeMain: Bool { false }

    public init(frame: CGRect, content: some View) {
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
        isMovableByWindowBackground = false
        hidesOnDeactivate = false
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]

        contentView = NSHostingView(rootView: content)
        setFrame(frame, display: true)
    }

    /// `NSWindow` conforms to `NSCoding`, so declaring a designated
    /// initializer above forces this one to be provided. It is never used.
    public required init?(coder: NSCoder) {
        fatalError("NotchPanel is not loaded from a nib")
    }

    /// While collapsed the panel must be invisible to the mouse, or it would
    /// swallow clicks meant for menu bar items sitting next to the notch.
    public func setInteractive(_ interactive: Bool) {
        ignoresMouseEvents = !interactive
    }
}
