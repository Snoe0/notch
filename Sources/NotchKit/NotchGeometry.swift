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

    /// Extra margin around the notch that still counts as "hovering", so the
    /// cursor does not have to land pixel-perfectly inside it.
    public static let hoverSlop: CGFloat = 4

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

    /// The region that counts as hovering while the panel is closed.
    /// Grows sideways and downward only — never above the screen edge.
    public var collapsedHoverRect: CGRect {
        let slop = Self.hoverSlop
        return CGRect(
            x: notchRect.minX - slop,
            y: notchRect.minY - slop,
            width: notchRect.width + slop * 2,
            height: notchRect.height + slop
        )
    }
}
