import Foundation

/// A point on the sketch canvas, in the canvas's own top-left-origin
/// coordinate space. Its own struct rather than `CGPoint` so the JSON on disk
/// encodes as named fields instead of Core Graphics' unkeyed pairs.
public struct SketchPoint: Codable, Equatable, Sendable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

/// The inks a stroke can be drawn in: white plus two accents, all chosen
/// against the panel's black. A small fixed set instead of a color well —
/// the same curation argument as `ScratchpadFont`.
public enum SketchInk: String, Codable, CaseIterable, Identifiable, Sendable {
    case white
    case amber
    case blue

    public var id: String { rawValue }

    var displayName: String {
        switch self {
        case .white: "White"
        case .amber: "Amber"
        case .blue: "Blue"
        }
    }

    /// An unknown stored ink reads as white, so a renamed case in a future
    /// version can never make a saved drawing undecodable.
    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = SketchInk(rawValue: raw) ?? .white
    }
}

/// One freehand stroke: the ink it was drawn in and the points the pointer
/// passed through, in order.
public struct SketchStroke: Codable, Equatable, Sendable {
    public var ink: SketchInk
    public var points: [SketchPoint]

    public init(ink: SketchInk, points: [SketchPoint]) {
        self.ink = ink
        self.points = points
    }

    /// True when the stroke never really moved — a click rather than a drag.
    /// Called out in the model because it changes how the stroke is rendered:
    /// stroking a zero-length path paints nothing, so a dot is filled instead.
    public var isDot: Bool {
        guard let first = points.first else { return false }
        return points.allSatisfy { abs($0.x - first.x) < 1 && abs($0.y - first.y) < 1 }
    }
}

/// Everything drawn on the notes' sketch canvas.
public struct SketchDrawing: Codable, Equatable, Sendable {
    public var strokes: [SketchStroke]

    public init(strokes: [SketchStroke] = []) {
        self.strokes = strokes
    }

    public static let empty = SketchDrawing()

    public var isEmpty: Bool { strokes.isEmpty }

    // MARK: - JSON

    /// Decodes the JSON persisted in `sketch.json`. Nil when the text is not
    /// a drawing, so a corrupt file reads as no drawing rather than wedging
    /// the store.
    public init?(json: String) {
        guard
            let data = json.data(using: .utf8),
            let decoded = try? JSONDecoder().decode(SketchDrawing.self, from: data)
        else { return nil }
        self = decoded
    }

    /// The canonical JSON for disk. Keys are sorted so the same drawing
    /// always encodes to the same string — the store compares strings to
    /// decide whether anything actually changed.
    public func encodedJSON() -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(self) else { return "" }
        return String(decoding: data, as: UTF8.self)
    }
}
