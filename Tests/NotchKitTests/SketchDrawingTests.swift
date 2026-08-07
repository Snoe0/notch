import Testing
import Foundation
@testable import NotchKit

private let squiggle = SketchDrawing(strokes: [
    SketchStroke(ink: .white, points: [
        SketchPoint(x: 10, y: 12),
        SketchPoint(x: 24.5, y: 30),
        SketchPoint(x: 40, y: 18.25),
    ]),
    SketchStroke(ink: .amber, points: [
        SketchPoint(x: 5, y: 5),
        SketchPoint(x: 6, y: 80),
    ]),
])

@Test func jsonRoundTripPreservesStrokesInksAndPoints() {
    let json = squiggle.encodedJSON()
    let decoded = SketchDrawing(json: json)
    #expect(decoded == squiggle)
}

@Test func encodingIsDeterministic() {
    // The store decides whether a save is needed by comparing encoded
    // strings, so the same drawing must always encode to the same bytes.
    let first = squiggle.encodedJSON()
    let second = SketchDrawing(json: first)?.encodedJSON()
    #expect(first == second)
}

@Test func corruptJSONReadsAsNoDrawing() {
    #expect(SketchDrawing(json: "not a drawing") == nil)
    #expect(SketchDrawing(json: "") == nil)
    #expect(SketchDrawing(json: "{\"strokes\":\"nope\"}") == nil)
}

@Test func unknownInkDecodesAsWhite() {
    // Forward compatibility: a drawing saved by a future version with an ink
    // this version does not know must still load, in the default ink.
    let json = #"{"strokes":[{"ink":"glitter","points":[{"x":1,"y":2}]}]}"#
    let decoded = SketchDrawing(json: json)
    #expect(decoded?.strokes.first?.ink == .white)
}

@Test func aClickSizedStrokeIsADot() {
    let click = SketchStroke(ink: .white, points: [
        SketchPoint(x: 20, y: 20),
        SketchPoint(x: 20.4, y: 19.8),
    ])
    #expect(click.isDot)
}

@Test func aDraggedStrokeIsNotADot() {
    let drag = SketchStroke(ink: .white, points: [
        SketchPoint(x: 20, y: 20),
        SketchPoint(x: 26, y: 21),
    ])
    #expect(!drag.isDot)
}
