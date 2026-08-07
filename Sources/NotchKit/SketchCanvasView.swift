import AppKit
import SwiftUI

extension SketchInk {
    /// Concrete colors for the panel's black background. The blue is the
    /// scratchpad's link blue, so both columns speak one accent language.
    var nsColor: NSColor {
        switch self {
        case .white: .white
        case .amber: .systemYellow
        case .blue: ScratchpadPalette.link
        }
    }

    var swatchColor: Color { Color(nsColor: nsColor) }
}

/// The sketch half of the notes column: paints the stored drawing and turns
/// mouse drags into new strokes.
struct SketchCanvasView: NSViewRepresentable {
    let drawing: SketchDrawing
    let ink: SketchInk
    let onStrokeBegan: () -> Void
    let onStrokeCommitted: (SketchStroke) -> Void

    func makeNSView(context: Context) -> StrokeCanvasNSView {
        let view = StrokeCanvasNSView()
        apply(to: view)
        return view
    }

    func updateNSView(_ view: StrokeCanvasNSView, context: Context) {
        apply(to: view)
    }

    private func apply(to view: StrokeCanvasNSView) {
        view.drawing = drawing
        view.ink = ink
        view.onStrokeBegan = onStrokeBegan
        view.onStrokeCommitted = onStrokeCommitted
    }
}

/// An AppKit view rather than a SwiftUI gesture, because raw `mouseDown` /
/// `mouseDragged` / `mouseUp` is the reliable event path in this borderless
/// non-activating panel. Drawing needs only mouse events, never key focus:
/// `acceptsFirstResponder` stays false, so the canvas can never take the
/// caret from a text field — the panel's standing first-responder rule.
final class StrokeCanvasNSView: NSView {
    var drawing: SketchDrawing = .empty {
        didSet {
            guard drawing != oldValue else { return }
            needsDisplay = true
        }
    }

    var ink: SketchInk = .white
    var onStrokeBegan: (() -> Void)?
    var onStrokeCommitted: ((SketchStroke) -> Void)?

    /// The stroke under the pointer right now, kept out of `drawing` so the
    /// store is only touched once, when the stroke is finished.
    private var pointsInProgress: [SketchPoint] = []

    private static let lineWidth: CGFloat = 2

    /// Stored points use a top-left origin, so a saved drawing stays anchored
    /// to the top of the notes whatever height the panel opens at.
    override var isFlipped: Bool { true }

    /// The panel never becomes the active app, so the click that arrives
    /// while another app is frontmost must draw rather than merely activate.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    /// The one affordance that says "this area draws": text shows an I-beam
    /// next door, the canvas shows a crosshair.
    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
    }

    // MARK: - Capturing strokes

    override func mouseDown(with event: NSEvent) {
        pointsInProgress = [point(from: event)]
        onStrokeBegan?()
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard !pointsInProgress.isEmpty else { return }
        pointsInProgress.append(point(from: event))
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard !pointsInProgress.isEmpty else { return }
        pointsInProgress.append(point(from: event))
        let stroke = SketchStroke(ink: ink, points: pointsInProgress)
        pointsInProgress = []
        // Local echo before the callback: the committed stroke keeps painting
        // through the beat before SwiftUI hands the updated drawing back down.
        drawing.strokes.append(stroke)
        onStrokeCommitted?(stroke)
    }

    private func point(from event: NSEvent) -> SketchPoint {
        let location = convert(event.locationInWindow, from: nil)
        return SketchPoint(x: location.x, y: location.y)
    }

    // MARK: - Painting

    override func draw(_ dirtyRect: NSRect) {
        for stroke in drawing.strokes {
            paint(stroke)
        }
        if !pointsInProgress.isEmpty {
            paint(SketchStroke(ink: ink, points: pointsInProgress))
        }
    }

    private func paint(_ stroke: SketchStroke) {
        guard let first = stroke.points.first else { return }
        stroke.ink.nsColor.set()
        if stroke.isDot {
            dotPath(at: first).fill()
        } else {
            let path = Self.smoothedPath(through: stroke.points)
            path.lineWidth = Self.lineWidth
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            path.stroke()
        }
    }

    private func dotPath(at point: SketchPoint) -> NSBezierPath {
        let radius = Self.lineWidth / 2
        let rect = NSRect(
            x: point.x - radius,
            y: point.y - radius,
            width: radius * 2,
            height: radius * 2
        )
        return NSBezierPath(ovalIn: rect)
    }

    /// Midpoint smoothing: each recorded point becomes the control of a curve
    /// between its neighboring midpoints, so the jitter of raw mouse samples
    /// reads as one continuous line instead of a chain of corners.
    static func smoothedPath(through points: [SketchPoint]) -> NSBezierPath {
        let path = NSBezierPath()
        guard let first = points.first else { return path }
        path.move(to: NSPoint(x: first.x, y: first.y))
        for (previous, current) in zip(points, points.dropFirst()) {
            let midpoint = NSPoint(
                x: (previous.x + current.x) / 2,
                y: (previous.y + current.y) / 2
            )
            path.curve(to: midpoint, controlPoint: NSPoint(x: previous.x, y: previous.y))
        }
        if let last = points.last {
            path.line(to: NSPoint(x: last.x, y: last.y))
        }
        return path
    }
}
