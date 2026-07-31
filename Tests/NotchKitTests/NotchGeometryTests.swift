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

/// The catcher must overshoot the screen top: the cursor clamps at the edge,
/// and a region stopping exactly at 982 could miss it — which used to close the
/// panel just as the user reached for it.
@Test func catcherFrameOvershootsTheScreenTop() throws {
    let geometry = try #require(NotchGeometry(metrics: mbp14))
    let catcher = geometry.catcherFrame

    #expect(catcher.maxY > 982)
    #expect(catcher.contains(CGPoint(x: 756, y: 982)))   // the exact top edge
    #expect(catcher.minY == geometry.notchRect.minY)
}

/// The catcher accepts mouse events so its tracking area can fire, so it must
/// not extend past the notch horizontally — anything wider would swallow
/// clicks meant for menu bar items sitting beside the notch.
@Test func catcherFrameIsExactlyNotchWideSoItCannotClipTheMenuBar() throws {
    let geometry = try #require(NotchGeometry(metrics: mbp14))
    let catcher = geometry.catcherFrame

    #expect(catcher.minX == geometry.notchRect.minX)
    #expect(catcher.maxX == geometry.notchRect.maxX)
    #expect(!catcher.contains(CGPoint(x: geometry.notchRect.minX - 1, y: 970)))
    #expect(!catcher.contains(CGPoint(x: geometry.notchRect.maxX + 1, y: 970)))
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
