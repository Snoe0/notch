import Testing
import Foundation
@testable import NotchKit

private let fastDebounce = Duration.milliseconds(20)
private let afterDebounce = Duration.milliseconds(200)

private let line = SketchStroke(ink: .white, points: [
    SketchPoint(x: 10, y: 10),
    SketchPoint(x: 60, y: 42),
])

/// `TemporaryDirectory` is shared by every store's tests; the sketch file
/// accessors live here beside the only tests that use them.
private extension TemporaryDirectory {
    var sketch: URL { url.appending(path: "sketch.json") }

    func writeSketch(_ text: String) throws {
        try text.write(to: sketch, atomically: true, encoding: .utf8)
    }

    func readSketch() throws -> String {
        try String(contentsOf: sketch, encoding: .utf8)
    }
}

@Test @MainActor func loadsExistingDrawingOnInit() throws {
    let dir = try TemporaryDirectory()
    try dir.writeSketch(SketchDrawing(strokes: [line]).encodedJSON())

    let store = SketchStore(directory: dir.url, debounce: fastDebounce)

    #expect(store.drawing.strokes == [line])
}

@Test @MainActor func startsEmptyWhenNoSketchFileExists() throws {
    let dir = try TemporaryDirectory()
    let store = SketchStore(directory: dir.url, debounce: fastDebounce)
    #expect(store.drawing.isEmpty)
}

@Test @MainActor func startsEmptyWhenTheFileIsCorrupt() async throws {
    // A mangled sketch.json must read as no drawing, and the next stroke
    // must still be able to save over it.
    let dir = try TemporaryDirectory()
    try dir.writeSketch("{{ not json")

    let store = SketchStore(directory: dir.url, debounce: fastDebounce)
    #expect(store.drawing.isEmpty)

    store.drawing.strokes.append(line)
    await store.flush()
    #expect(try SketchDrawing(json: dir.readSketch())?.strokes == [line])
}

@Test @MainActor func writesTheDrawingToDiskAfterTheDebounceInterval() async throws {
    let dir = try TemporaryDirectory()
    let store = SketchStore(directory: dir.url, debounce: fastDebounce)

    store.drawing.strokes.append(line)
    try await Task.sleep(for: afterDebounce)

    #expect(try SketchDrawing(json: dir.readSketch())?.strokes == [line])
}

@Test @MainActor func coalescesRapidStrokesIntoASingleWrite() async throws {
    let dir = try TemporaryDirectory()
    let store = SketchStore(directory: dir.url, debounce: fastDebounce)

    for offset in 0..<5 {
        store.drawing.strokes.append(
            SketchStroke(ink: .blue, points: [
                SketchPoint(x: Double(offset), y: 0),
                SketchPoint(x: Double(offset), y: 20),
            ])
        )
    }
    try await Task.sleep(for: afterDebounce)

    #expect(store.writeCount == 1)
    #expect(try SketchDrawing(json: dir.readSketch())?.strokes.count == 5)
}

@Test @MainActor func drawingSurvivesARelaunch() async throws {
    let dir = try TemporaryDirectory()
    let drawn = SketchDrawing(strokes: [
        line,
        SketchStroke(ink: .amber, points: [SketchPoint(x: 3.5, y: 7.25)]),
    ])

    let store = SketchStore(directory: dir.url, debounce: fastDebounce)
    store.drawing = drawn
    await store.flush()

    let relaunched = SketchStore(directory: dir.url, debounce: fastDebounce)
    #expect(relaunched.drawing == drawn)
}

@Test @MainActor func reloadsExternalChangesWhileNoStrokeIsInFlight() async throws {
    let dir = try TemporaryDirectory()
    let store = SketchStore(directory: dir.url, debounce: fastDebounce)
    store.isDrawing = false

    try dir.writeSketch(SketchDrawing(strokes: [line]).encodedJSON())
    try await Task.sleep(for: afterDebounce)

    #expect(store.drawing.strokes == [line])
}

@Test @MainActor func keepsTheInMemoryDrawingWhileAStrokeIsInFlight() async throws {
    let dir = try TemporaryDirectory()
    let store = SketchStore(directory: dir.url, debounce: fastDebounce)
    store.isDrawing = true
    store.drawing.strokes.append(line)

    try dir.writeSketch(SketchDrawing.empty.encodedJSON())
    try await Task.sleep(for: afterDebounce)

    #expect(store.drawing.strokes == [line])
}

@Test @MainActor func reportsAnErrorWhenTheSketchDirectoryCannotBeUsed() async throws {
    // A path under an existing *file* can never be created as a directory.
    let dir = try TemporaryDirectory()
    try dir.write("blocking file")
    let impossible = dir.scratchpad.appending(path: "nested")

    let store = SketchStore(directory: impossible, debounce: fastDebounce)
    store.drawing.strokes.append(line)
    try await Task.sleep(for: afterDebounce)

    #expect(store.saveError != nil)
    #expect(store.drawing.strokes == [line])
}
