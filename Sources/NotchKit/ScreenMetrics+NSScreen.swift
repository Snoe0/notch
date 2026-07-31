import AppKit

extension ScreenMetrics {
    /// Reads the notch-relevant metrics off a real screen.
    public init(screen: NSScreen) {
        self.init(
            frame: screen.frame,
            topInset: screen.safeAreaInsets.top,
            auxiliaryTopLeftWidth: screen.auxiliaryTopLeftArea?.width ?? 0,
            auxiliaryTopRightWidth: screen.auxiliaryTopRightArea?.width ?? 0
        )
    }
}

extension NotchGeometry {
    /// Geometry for the built-in display, or nil when it has no notch.
    public static func forBuiltInScreen() -> NotchGeometry? {
        guard let screen = NSScreen.screens.first(where: {
            ScreenMetrics(screen: $0).topInset > 0
        }) else { return nil }
        return NotchGeometry(metrics: ScreenMetrics(screen: screen))
    }
}
