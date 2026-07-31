import AppKit

/// An `NSView` that reports cursor enter/exit through an `NSTrackingArea`.
///
/// This is the permission-free alternative to `addGlobalMonitorForEvents`:
/// tracking areas report the cursor only inside windows the app already owns,
/// so macOS does not gate them behind Input Monitoring.
final class TrackingView: NSView {
    var onHover: ((Bool) -> Void)?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas {
            removeTrackingArea(area)
        }
        // `.inVisibleRect` keeps the area sized to the view automatically.
        // `.activeAlways` is required because this app is never frontmost.
        addTrackingArea(
            NSTrackingArea(
                rect: .zero,
                options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                owner: self
            )
        )
    }

    override func mouseEntered(with event: NSEvent) { onHover?(true) }
    override func mouseExited(with event: NSEvent) { onHover?(false) }
}
