import Testing
import CoreGraphics
@testable import NotchKit

private let mbp14 = ScreenMetrics(
    frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
    topInset: 32,
    auxiliaryTopLeftWidth: 596,
    auxiliaryTopRightWidth: 596
)

@Test func notchRectIsCenteredAndFlushWithScreenTop() throws {
    let geometry = try #require(NotchGeometry(metrics: mbp14))
    #expect(geometry.notchRect.width == 320)   // 1512 - 596 - 596
    #expect(geometry.notchRect.height == 32)
    #expect(geometry.notchRect.midX == 756)
    #expect(geometry.notchRect.maxY == 982)
}

@Test func screenWithoutNotchHasNoGeometry() {
    let external = ScreenMetrics(
        frame: CGRect(x: 0, y: 0, width: 2560, height: 1440),
        topInset: 0,
        auxiliaryTopLeftWidth: 0,
        auxiliaryTopRightWidth: 0
    )
    #expect(NotchGeometry(metrics: external) == nil)
}

@Test func screenWithInsetButNoAuxiliaryAreasIsTreatedAsNotchless() {
    let ambiguous = ScreenMetrics(
        frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
        topInset: 32,
        auxiliaryTopLeftWidth: 0,
        auxiliaryTopRightWidth: 0
    )
    #expect(NotchGeometry(metrics: ambiguous) == nil)
}

@Test func panelIsCenteredOnNotchAndAnchoredToScreenTop() throws {
    let geometry = try #require(NotchGeometry(metrics: mbp14))
    #expect(geometry.panelFrame.size == NotchGeometry.expandedSize)
    #expect(geometry.panelFrame.midX == geometry.notchRect.midX)
    #expect(geometry.panelFrame.maxY == 982)
}



@Test func geometryRespectsANonZeroScreenOrigin() throws {
    let shifted = ScreenMetrics(
        frame: CGRect(x: -1512, y: 300, width: 1512, height: 982),
        topInset: 32,
        auxiliaryTopLeftWidth: 596,
        auxiliaryTopRightWidth: 596
    )
    let geometry = try #require(NotchGeometry(metrics: shifted))
    #expect(geometry.notchRect.midX == -756)
    #expect(geometry.notchRect.maxY == 1282)
    #expect(geometry.panelFrame.maxY == 1282)
}

/// Regression: real hardware does not report symmetric auxiliary areas.
/// These are the measured values from a 14" MacBook Pro. Centring the notch on
/// the screen instead of on the auxiliary boundaries put it 1.5pt off.
@Test func notchFollowsAsymmetricAuxiliaryAreas() throws {
    let measured = ScreenMetrics(
        frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
        topInset: 32,
        auxiliaryTopLeftWidth: 665,
        auxiliaryTopRightWidth: 662
    )
    let geometry = try #require(NotchGeometry(metrics: measured))

    #expect(geometry.notchRect.minX == 665)          // where the left area ends
    #expect(geometry.notchRect.maxX == 850)          // where the right area starts
    #expect(geometry.notchRect.width == 185)
    #expect(geometry.notchRect.midX != measured.frame.midX)   // genuinely off-centre
    #expect(geometry.panelFrame.midX == geometry.notchRect.midX)
}

/// Originally the hover rect stopped at the screen top. That was wrong in use:
/// the cursor clamps at the edge and `CGRect.contains` excludes `maxY`, so
/// shoving the cursor upward read as *outside* and closed the panel at the
/// moment the user was reaching for it.
@Test func collapsedHoverRectOvershootsTheScreenTop() throws {
    let geometry = try #require(NotchGeometry(metrics: mbp14))
    let hover = geometry.collapsedHoverRect

    #expect(hover.maxY > 982)
    #expect(hover.contains(CGPoint(x: 756, y: 982)))   // the exact top edge
    #expect(hover.minY == geometry.notchRect.minY - NotchGeometry.hoverSlop)
    #expect(hover.contains(CGPoint(x: 756, y: 948)))   // just under the notch
    #expect(!hover.contains(CGPoint(x: 100, y: 975)))  // menu bar, far left
}

@Test func openHoverRectCoversThePanelAndTheTopEdge() throws {
    let geometry = try #require(NotchGeometry(metrics: mbp14))
    let hover = geometry.openHoverRect

    #expect(hover.contains(CGPoint(x: 756, y: 982)))   // the exact top edge
    #expect(hover.minY == geometry.panelFrame.minY)    // no taller at the bottom
    #expect(hover.width == geometry.panelFrame.width)
    #expect(hover.contains(CGPoint(x: 756, y: 800)))   // deep inside the panel
    #expect(!hover.contains(CGPoint(x: 756, y: 700)))  // below the panel
}
