import Testing
import Foundation
@testable import NotchKit

private let fastDebounce = Duration.milliseconds(20)
private let afterDebounce = Duration.milliseconds(200)

@Test @MainActor func loadsExistingTodosOnInit() throws {
    let dir = try TemporaryDirectory()
    try dir.writeTodos("- [ ] ship v2\n- [x] email Sam\n")

    let store = TodoStore(directory: dir.url, debounce: fastDebounce)

    #expect(store.items.map(\.text) == ["ship v2", "email Sam"])
    #expect(store.items.map(\.isDone) == [false, true])
}

@Test @MainActor func startsWithAnEmptyListWhenNoFileExists() throws {
    let dir = try TemporaryDirectory()
    let store = TodoStore(directory: dir.url, debounce: fastDebounce)
    #expect(store.items.isEmpty)
}

@Test @MainActor func writesAddedTodosToDiskAfterTheDebounceInterval() async throws {
    let dir = try TemporaryDirectory()
    let store = TodoStore(directory: dir.url, debounce: fastDebounce)

    store.add("ship v2")
    try await Task.sleep(for: afterDebounce)

    #expect(try dir.readTodos() == "- [ ] ship v2\n")
}

@Test @MainActor func ignoresBlankInput() throws {
    let dir = try TemporaryDirectory()
    let store = TodoStore(directory: dir.url, debounce: fastDebounce)

    store.add("   \n ")

    #expect(store.items.isEmpty)
}

@Test @MainActor func coalescesRapidTodoEditsIntoASingleWrite() async throws {
    let dir = try TemporaryDirectory()
    let store = TodoStore(directory: dir.url, debounce: fastDebounce)

    store.add("one")
    store.add("two")
    store.add("three")
    try await Task.sleep(for: afterDebounce)

    #expect(store.writeCount == 1)
    #expect(try dir.readTodos() == "- [ ] one\n- [ ] two\n- [ ] three\n")
}

@Test @MainActor func togglingMarksTheItemDoneAndKeepsItInTheList() async throws {
    let dir = try TemporaryDirectory()
    let store = TodoStore(directory: dir.url, debounce: fastDebounce)
    store.add("ship v2")

    store.toggle(store.items[0].id)
    await store.flush()

    #expect(store.items.map(\.isDone) == [true])
    #expect(try dir.readTodos() == "- [x] ship v2\n")
}

@Test @MainActor func deletingRemovesTheItemFromTheFile() async throws {
    let dir = try TemporaryDirectory()
    let store = TodoStore(directory: dir.url, debounce: fastDebounce)
    store.add("keep")
    store.add("drop")

    store.delete(store.items[1].id)
    await store.flush()

    #expect(store.items.map(\.text) == ["keep"])
    #expect(try dir.readTodos() == "- [ ] keep\n")
}

@Test @MainActor func flushWritesWithoutWaitingForTheDebounce() async throws {
    let dir = try TemporaryDirectory()
    let store = TodoStore(directory: dir.url, debounce: .seconds(60))

    store.add("ship v2")
    await store.flush()

    #expect(try dir.readTodos() == "- [ ] ship v2\n")
}

@Test @MainActor func reloadsExternalTodoChangesWhenTheUserIsNotEditing() async throws {
    let dir = try TemporaryDirectory()
    try dir.writeTodos("- [ ] original\n")
    let store = TodoStore(directory: dir.url, debounce: fastDebounce)
    store.isEditing = false

    try dir.writeTodos("- [x] changed on another device\n")
    try await Task.sleep(for: afterDebounce)

    #expect(store.items.map(\.text) == ["changed on another device"])
    #expect(store.items.map(\.isDone) == [true])
}

@Test @MainActor func keepsTheInMemoryListWhileTheUserIsEditing() async throws {
    let dir = try TemporaryDirectory()
    try dir.writeTodos("- [ ] original\n")
    let store = TodoStore(directory: dir.url, debounce: fastDebounce)
    store.isEditing = true
    store.add("what I am typing right now")

    try dir.writeTodos("- [ ] changed on another device\n")
    try await Task.sleep(for: afterDebounce)

    #expect(store.items.map(\.text) == ["original", "what I am typing right now"])
}

@Test @MainActor func reportsAnErrorWhenTheTodoDirectoryCannotBeUsed() async throws {
    // A path under an existing *file* can never be created as a directory.
    let dir = try TemporaryDirectory()
    try dir.writeTodos("blocking file")
    let impossible = dir.todos.appending(path: "nested")

    let store = TodoStore(directory: impossible, debounce: fastDebounce)
    store.add("this cannot be saved")
    try await Task.sleep(for: afterDebounce)

    #expect(store.saveError != nil)
    #expect(store.items.map(\.text) == ["this cannot be saved"])
}
