import Foundation
import Combine

/// Owns `sketch.json`, the notes' drawing. Disk work lives in its
/// `PersistedFile` — the same debounced atomic writes and external-change
/// watching as the scratchpad, with the drawing serialized to canonical JSON
/// at the file boundary.
@MainActor
public final class SketchStore: ObservableObject {
    /// The live drawing. Assigning to it schedules a debounced save.
    @Published public var drawing: SketchDrawing = .empty {
        didSet {
            guard !file.holdsText(drawing.encodedJSON()) else { return }
            file.scheduleSave()
        }
    }

    /// Set by the canvas while a stroke is in flight. External changes are
    /// not applied while this is true, so a remote write never eats the line
    /// being drawn.
    @Published public var isDrawing: Bool = false

    /// Non-nil when the last save attempt failed. Surfaced as a banner.
    @Published public private(set) var saveError: String?

    /// Number of completed disk writes. Instrumentation for tests.
    public var writeCount: Int { file.writeCount }

    public var fileURL: URL { file.fileURL }
    public var directoryURL: URL { file.directoryURL }

    private let file: PersistedFile

    public init(directory: URL, debounce: Duration = .milliseconds(500)) {
        file = PersistedFile(name: "sketch.json", in: directory, debounce: debounce)
        file.owner = self
        loadFromDisk()
        file.startWatching()
    }

    /// Write immediately, bypassing the debounce. Called when the canvas
    /// leaves the screen.
    public func flush() async {
        await file.flush()
    }

    private func loadFromDisk() {
        guard
            let contents = file.loadText(),
            let loaded = SketchDrawing(json: contents)
        else { return }
        drawing = loaded
    }
}

extension SketchStore: PersistedFileOwner {
    var persistedText: String { drawing.encodedJSON() }

    var suppressesExternalReloads: Bool { isDrawing }

    func persistedFileChangedExternally(to contents: String) {
        guard let loaded = SketchDrawing(json: contents) else { return }
        drawing = loaded
    }

    func persistedFileDidReportSaveError(_ message: String?) {
        saveError = message
    }
}
