import Foundation

/// A scratch directory that deletes itself when the test releases it.
final class TemporaryDirectory {
    let url: URL

    init() throws {
        url = URL.temporaryDirectory.appending(path: "notch-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    var scratchpad: URL { url.appending(path: "scratchpad.md") }
    var todos: URL { url.appending(path: "todos.md") }

    func write(_ text: String) throws {
        try write(text, to: scratchpad)
    }

    func read() throws -> String {
        try read(scratchpad)
    }

    func writeTodos(_ text: String) throws {
        try write(text, to: todos)
    }

    func readTodos() throws -> String {
        try read(todos)
    }

    private func write(_ text: String, to file: URL) throws {
        try text.write(to: file, atomically: true, encoding: .utf8)
    }

    private func read(_ file: URL) throws -> String {
        try String(contentsOf: file, encoding: .utf8)
    }

    deinit { try? FileManager.default.removeItem(at: url) }
}
