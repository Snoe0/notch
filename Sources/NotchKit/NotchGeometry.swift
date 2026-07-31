import CoreGraphics

/// The only facts about a display that the geometry needs. Extracted from
/// `NSScreen` at the edge of the app so the math stays testable headlessly.
public struct ScreenMetrics: Equatable, Sendable {
    public let frame: CGRect
    public let topInset: CGFloat
    public let auxiliaryTopLeftWidth: CGFloat
    public let auxiliaryTopRightWidth: CGFloat

    public init(
        frame: CGRect,
        topInset: CGFloat,
        auxiliaryTopLeftWidth: CGFloat,
        auxiliaryTopRightWidth: CGFloat
    ) {
        self.frame = frame
        self.topInset = topInset
        self.auxiliaryTopLeftWidth = auxiliaryTopLeftWidth
        self.auxiliaryTopRightWidth = auxiliaryTopRightWidth
    }
}

/// Where the notch is and where the panel that hangs off it should sit.
/// All rects are in AppKit screen coordinates (origin bottom-left).
public struct NotchGeometry: Equatable, Sendable {
    /// The fixed size of the panel window. It never changes; the content
    /// inside it animates instead.
    public static let expandedSize = CGSize(width: 620, height: 200)

    public let notchRect: CGRect
    public let panelFrame: CGRect

    public init?(metrics: ScreenMetrics) {
        let notchWidth = metrics.frame.width
            - metrics.auxiliaryTopLeftWidth
            - metrics.auxiliaryTopRightWidth

        // A notch requires both a top inset and auxiliary areas flanking it.
        // An inset without them is some other kind of screen and is ignored.
        guard metrics.topInset > 0,
              metrics.auxiliaryTopLeftWidth > 0,
              metrics.auxiliaryTopRightWidth > 0,
              notchWidth > 0
        else { return nil }

        let top = metrics.frame.maxY

        // Derive the notch from where the auxiliary areas actually end, rather
        // than assuming it is centred. On real hardware the two areas are not
        // symmetric — a measured 14" reports 665 left and 662 right — so
        // centring on the screen puts the notch 1.5pt off its true position.
        notchRect = CGRect(
            x: metrics.frame.minX + metrics.auxiliaryTopLeftWidth,
            y: top - metrics.topInset,
            width: notchWidth,
            height: metrics.topInset
        )

        let size = Self.expandedSize
        panelFrame = CGRect(
            x: notchRect.midX - size.width / 2,
            y: top - size.height,
            width: size.width,
            height: size.height
        )
    }

    /// How far the hover regions extend above the top of the screen.
    ///
    /// `CGRect.contains` excludes its own `maxY`, so a rect ending exactly at
    /// the screen top reports the cursor as *outside* when the user shoves it
    /// into the top edge — which closed the panel at the very moment the user
    /// was reaching for it. The cursor also clamps at the screen edge, so
    /// without this overshoot, shoving the cursor into the top edge could land
    /// outside the tracked region entirely. Nothing exists above the screen,
    /// so overshooting is free.
    public static let topOvershoot: CGFloat = 40

    /// The always-present hover catcher: exactly the notch, extended above the
    /// screen top.
    ///
    /// Exactly notch-width on purpose — lateral slop would make the notch
    /// easier to hit but would clip menu bar items sitting beside it, because
    /// the catcher has to accept mouse events for its tracking area to fire.
    ///
    /// The upward extension exists because `CGRect.contains` excludes `maxY`
    /// and, more importantly, because the cursor clamps at the screen edge:
    /// without it, shoving the cursor into the top edge could land outside the
    /// tracked region and close the panel just as the user reached for it.
    public var catcherFrame: CGRect {
        CGRect(
            x: notchRect.minX,
            y: notchRect.minY,
            width: notchRect.width,
            height: notchRect.height + Self.topOvershoot
        )
    }
}
