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

@Test func collapsedHoverRectAddsSlopBelowButNeverAboveTheScreen() throws {
    let geometry = try #require(NotchGeometry(metrics: mbp14))
    let hover = geometry.collapsedHoverRect

    #expect(hover.maxY == 982)
    #expect(hover.minY == geometry.notchRect.minY - NotchGeometry.hoverSlop)
    #expect(hover.contains(CGPoint(x: 756, y: 948)))   // just under the notch
    #expect(!hover.contains(CGPoint(x: 100, y: 975)))  // menu bar, far left
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
