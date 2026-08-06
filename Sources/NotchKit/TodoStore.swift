import Foundation
import Combine

/// One line of `todos.md`. Identity is per-session: the file stores no ids, so
/// a reload from disk mints new ones.
public struct TodoItem: Identifiable, Equatable {
    public let id: UUID
    public var text: String
    public var isDone: Bool

    public init(id: UUID = UUID(), text: String, isDone: Bool = false) {
        self.id = id
        self.text = text
        self.isDone = isDone
    }
}

/// The markdown checklist format, as pure functions.
///
/// A todo is a `- [ ] text` or `- [x] text` line. Everything else — headings,
/// blank lines, prose — is dropped on the next save, because the file is
/// rewritten from the in-memory list.
enum TodoMarkdown {
    static func parse(_ markdown: String) -> [TodoItem] {
        markdown.split(separator: "\n", omittingEmptySubsequences: false)
            .compactMap { parseLine(String($0)) }
    }

    static func serialize(_ items: [TodoItem]) -> String {
        guard !items.isEmpty else { return "" }
        return items.map(line(for:)).joined(separator: "\n") + "\n"
    }

    private static func parseLine(_ line: String) -> TodoItem? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard let isDone = checkboxState(of: trimmed) else { return nil }
        let text = trimmed.dropFirst(checkboxWidth).trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return nil }
        return TodoItem(text: text, isDone: isDone)
    }

    /// Done, not done, or nil when the line is not a checklist item at all.
    private static func checkboxState(of line: String) -> Bool? {
        switch line.prefix(checkboxWidth).lowercased() {
        case "- [ ]": false
        case "- [x]": true
        default: nil
        }
    }

    private static func line(for item: TodoItem) -> String {
        "- [\(item.isDone ? "x" : " ")] \(item.text)"
    }

    private static let checkboxWidth = 5
}

/// Owns `todos.md`. Disk work lives in its `PersistedFile`.
@MainActor
public final class TodoStore: ObservableObject {
    /// The live list. Every change to it schedules a debounced save.
    @Published public var items: [TodoItem] = [] {
        didSet { saveIfChanged() }
    }

    /// Set by the view while the add field has focus. External changes are
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
        file = PersistedFile(name: "todos.md", in: directory, debounce: debounce)
        file.owner = self
        loadFromDisk()
        file.startWatching()
    }

    /// The app's real notes location.
    public static var defaultDirectory: URL {
        URL.documentsDirectory.appending(path: "NotchNotes")
    }

    // MARK: - Editing

    /// Appends a todo. Blank input is ignored, so the add field can fire on
    /// every return without guarding first.
    public func add(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        items.append(TodoItem(text: trimmed))
    }

    /// Flips one todo between done and not done. Done items stay in the list.
    public func toggle(_ id: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].isDone.toggle()
    }

    public func delete(_ id: UUID) {
        items.removeAll { $0.id == id }
    }

    /// Write immediately, bypassing the debounce. Called when the panel closes.
    public func flush() async {
        await file.flush()
    }

    // MARK: - Disk

    private func loadFromDisk() {
        guard let contents = file.loadText() else { return }
        items = TodoMarkdown.parse(contents)
    }

    private func saveIfChanged() {
        guard !file.holdsText(persistedText) else { return }
        file.scheduleSave()
    }
}

extension TodoStore: PersistedFileOwner {
    var persistedText: String { TodoMarkdown.serialize(items) }

    var suppressesExternalReloads: Bool { isEditing }

    func persistedFileChangedExternally(to contents: String) {
        items = TodoMarkdown.parse(contents)
    }

    func persistedFileDidReportSaveError(_ message: String?) {
        saveError = message
    }
}
