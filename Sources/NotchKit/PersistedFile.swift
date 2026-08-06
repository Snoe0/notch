import Foundation

/// The store half of a `PersistedFile`: it holds the value, the file holds the
/// bytes. Every callback lands on the main actor.
@MainActor
protocol PersistedFileOwner: AnyObject {
    /// The text to write on the next save.
    var persistedText: String { get }

    /// While true, edits made outside the app are ignored, so a remote write
    /// never eats what the user is typing.
    var suppressesExternalReloads: Bool { get }

    /// The file changed underneath us and the owner should adopt `contents`.
    func persistedFileChangedExternally(to contents: String)

    /// Result of the last write attempt: a message on failure, nil on success.
    func persistedFileDidReportSaveError(_ message: String?)
}

/// One text file on disk: debounced atomic writes, and a watcher that reports
/// edits made by other apps. Shared by every store that owns a file.
@MainActor
final class PersistedFile {
    let fileURL: URL

    /// Number of completed disk writes. Instrumentation for tests.
    private(set) var writeCount = 0

    weak var owner: (any PersistedFileOwner)?

    var directoryURL: URL { fileURL.deletingLastPathComponent() }

    private let debounce: Duration
    private var saveTask: Task<Void, Never>?
    private var watcher: DispatchSourceFileSystemObject?
    /// What the file held the last time we read or wrote it.
    private var lastSyncedText = ""

    init(name: String, in directory: URL, debounce: Duration) {
        self.fileURL = directory.appending(path: name)
        self.debounce = debounce
    }

    deinit { watcher?.cancel() }

    // MARK: - Loading

    /// The file's text, or nil when it does not exist yet. Reading through
    /// here records the text so it is not mistaken for an unsaved edit.
    func loadText() -> String? {
        guard let contents = readText() else { return nil }
        lastSyncedText = contents
        return contents
    }

    /// True when `text` is already what the file holds, so saving it is a no-op.
    func holdsText(_ text: String) -> Bool {
        text == lastSyncedText
    }

    private func readText() -> String? {
        try? String(contentsOf: fileURL, encoding: .utf8)
    }

    private func reloadIfChangedExternally() {
        guard let owner, !owner.suppressesExternalReloads else { return }
        guard let contents = readText(), contents != owner.persistedText else { return }
        lastSyncedText = contents
        owner.persistedFileChangedExternally(to: contents)
    }

    // MARK: - Saving

    /// Queue a write for one debounce interval from now, replacing any pending one.
    func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [debounce] in
            try? await Task.sleep(for: debounce)
            guard !Task.isCancelled else { return }
            await self.write()
        }
    }

    /// Write immediately, bypassing the debounce. Called when the panel closes.
    func flush() async {
        saveTask?.cancel()
        await write()
    }

    private func write() async {
        guard let owner else { return }
        let contents = owner.persistedText
        do {
            try writeAtomically(contents)
            lastSyncedText = contents
            writeCount += 1
            owner.persistedFileDidReportSaveError(nil)
        } catch {
            owner.persistedFileDidReportSaveError(error.localizedDescription)
        }
    }

    private func writeAtomically(_ contents: String) throws {
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
        try contents.write(to: fileURL, atomically: true, encoding: .utf8)
    }

    // MARK: - Watching

    /// Watches the containing directory rather than the file, because atomic
    /// writes swap the file's inode and orphan a file-level watcher.
    func startWatching() {
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
