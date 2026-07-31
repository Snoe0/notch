import Foundation
import Combine

/// Owns `scratchpad.md`. The only type in the app that touches disk.
@MainActor
public final class ScratchpadStore: ObservableObject {
    /// The live buffer. Assigning to it schedules a debounced save.
    @Published public var text: String = "" {
        didSet {
            guard text != lastLoadedText else { return }
            scheduleSave()
        }
    }

    /// Set by the view while the text field has focus. External changes are
    /// not applied while this is true, so remote edits never eat live typing.
    @Published public var isEditing: Bool = false

    /// Non-nil when the last save attempt failed. Surfaced as a banner.
    @Published public private(set) var saveError: String?

    /// Number of completed disk writes. Instrumentation for tests.
    public private(set) var writeCount = 0

    public let fileURL: URL
    public var directoryURL: URL { fileURL.deletingLastPathComponent() }

    private let debounce: Duration
    private var saveTask: Task<Void, Never>?
    private var watcher: DispatchSourceFileSystemObject?
    private var lastLoadedText = ""

    public init(directory: URL, debounce: Duration = .milliseconds(500)) {
        self.fileURL = directory.appending(path: "scratchpad.md")
        self.debounce = debounce
        load()
        startWatching()
    }

    deinit { watcher?.cancel() }

    /// The app's real notes location.
    public static var defaultDirectory: URL {
        URL.documentsDirectory.appending(path: "NotchNotes")
    }

    // MARK: - Loading

    private func load() {
        guard let contents = try? String(contentsOf: fileURL, encoding: .utf8) else { return }
        lastLoadedText = contents
        text = contents
    }

    private func reloadIfChangedExternally() {
        guard !isEditing else { return }
        guard let contents = try? String(contentsOf: fileURL, encoding: .utf8) else { return }
        guard contents != text else { return }
        lastLoadedText = contents
        text = contents
    }

    // MARK: - Saving

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [debounce] in
            try? await Task.sleep(for: debounce)
            guard !Task.isCancelled else { return }
            await self.write()
        }
    }

    /// Write immediately, bypassing the debounce. Called when the panel closes.
    public func flush() async {
        saveTask?.cancel()
        await write()
    }

    private func write() async {
        let contents = text
        do {
            try FileManager.default.createDirectory(
                at: directoryURL,
                withIntermediateDirectories: true
            )
            try contents.write(to: fileURL, atomically: true, encoding: .utf8)
            lastLoadedText = contents
            writeCount += 1
            saveError = nil
        } catch {
            saveError = error.localizedDescription
        }
    }

    // MARK: - Watching

    /// Watches the containing directory rather than the file, because atomic
    /// writes swap the file's inode and orphan a file-level watcher.
    private func startWatching() {
        try? FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
        let descriptor = open(directoryURL.path, O_EVTONLY)
        guard descriptor >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .rename],
            queue: .main
        )
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.reloadIfChangedExternally() }
        }
        source.setCancelHandler { close(descriptor) }
        source.resume()
        watcher = source
    }
}
