import Foundation
import Combine

/// Owns `scratchpad.md`. Disk work lives in its `PersistedFile`.
@MainActor
public final class ScratchpadStore: ObservableObject {
    /// The live buffer. Assigning to it schedules a debounced save.
    @Published public var text: String = "" {
        didSet {
            guard !file.holdsText(text) else { return }
            file.scheduleSave()
        }
    }

    /// Set by the view while the text field has focus. External changes are
    /// not applied while this is true, so remote edits never eat live typing.
    @Published public var isEditing: Bool = false

    /// Non-nil when the last save attempt failed. Surfaced as a banner.
    @Published public private(set) var saveError: String?

    /// Number of completed disk writes. Instrumentation for tests.
    public var writeCount: Int { file.writeCount }

    public var fileURL: URL { file.fileURL }
    public var directoryURL: URL { file.directoryURL }

    private let file: PersistedFile

    public init(directory: URL, debounce: Duration = .milliseconds(500)) {
        file = PersistedFile(name: "scratchpad.md", in: directory, debounce: debounce)
        file.owner = self
        loadFromDisk()
        file.startWatching()
    }

    /// The app's real notes location.
    public static var defaultDirectory: URL {
        URL.documentsDirectory.appending(path: "NotchNotes")
    }

    /// Write immediately, bypassing the debounce. Called when the panel closes.
    public func flush() async {
        await file.flush()
    }

    private func loadFromDisk() {
        guard let contents = file.loadText() else { return }
        text = contents
    }
}

extension ScratchpadStore: PersistedFileOwner {
    var persistedText: String { text }

    var suppressesExternalReloads: Bool { isEditing }

    func persistedFileChangedExternally(to contents: String) {
        text = contents
    }

    func persistedFileDidReportSaveError(_ message: String?) {
        saveError = message
    }
}
