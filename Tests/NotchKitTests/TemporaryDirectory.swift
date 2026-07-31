import Foundation

/// A scratch directory that deletes itself when the test releases it.
final class TemporaryDirectory {
    let url: URL

    init() throws {
        url = URL.temporaryDirectory.appending(path: "notch-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    var scratchpad: URL { url.appending(path: "scratchpad.md") }

    func write(_ text: String) throws {
        try text.write(to: scratchpad, atomically: true, encoding: .utf8)
    }

    func read() throws -> String {
        try String(contentsOf: scratchpad, encoding: .utf8)
    }

    deinit { try? FileManager.default.removeItem(at: url) }
}
