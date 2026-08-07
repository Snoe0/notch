import Testing
import Foundation
@testable import NotchKit

private let fastDebounce = Duration.milliseconds(20)
private let afterDebounce = Duration.milliseconds(200)

@Test @MainActor func loadsExistingFileOnInit() throws {
    let dir = try TemporaryDirectory()
    try dir.write("gate 34, 6:40pm")

    let store = ScratchpadStore(directory: dir.url, debounce: fastDebounce)

    #expect(store.text == "gate 34, 6:40pm")
}

@Test @MainActor func startsEmptyWhenNoFileExists() throws {
    let dir = try TemporaryDirectory()
    let store = ScratchpadStore(directory: dir.url, debounce: fastDebounce)
    #expect(store.text == "")
}

@Test @MainActor func writesTextToDiskAfterTheDebounceInterval() async throws {
    let dir = try TemporaryDirectory()
    let store = ScratchpadStore(directory: dir.url, debounce: fastDebounce)

    store.text = "wifi pw: hunter2"
    try await Task.sleep(for: afterDebounce)

    #expect(try dir.read() == "wifi pw: hunter2")
}

@Test @MainActor func coalescesRapidEditsIntoASingleWrite() async throws {
    let dir = try TemporaryDirectory()
    let store = ScratchpadStore(directory: dir.url, debounce: fastDebounce)

    for character in "hello" {
        store.text.append(character)
    }
    try await Task.sleep(for: afterDebounce)

    #expect(store.writeCount == 1)
    #expect(try dir.read() == "hello")
}

@Test @MainActor func reloadsExternalChangesWhenTheUserIsNotEditing() async throws {
    let dir = try TemporaryDirectory()
    try dir.write("original")
    let store = ScratchpadStore(directory: dir.url, debounce: fastDebounce)
    store.isEditing = false

    try dir.write("changed on another device")
    try await Task.sleep(for: afterDebounce)

    #expect(store.text == "changed on another device")
}

@Test @MainActor func keepsTheInMemoryBufferWhileTheUserIsEditing() async throws {
    let dir = try TemporaryDirectory()
    try dir.write("original")
    let store = ScratchpadStore(directory: dir.url, debounce: fastDebounce)
    store.isEditing = true
    store.text = "what I am typing right now"

    try dir.write("changed on another device")
    try await Task.sleep(for: afterDebounce)

    #expect(store.text == "what I am typing right now")
}

@Test @MainActor func formattingMarkersAndLinksSurviveARelaunch() async throws {
    // Styling is persisted as plain markers inside the markdown string, so a
    // round trip through disk must preserve them byte for byte.
    let dir = try TemporaryDirectory()
    let noted = "call ==Ann== about the <u>rent</u> via https://example.com"

    let store = ScratchpadStore(directory: dir.url, debounce: fastDebounce)
    store.text = noted
    await store.flush()

    let relaunched = ScratchpadStore(directory: dir.url, debounce: fastDebounce)
    #expect(relaunched.text == noted)
    #expect(ScratchpadMarkup.markupSpans(in: relaunched.text).count == 2)
    #expect(ScratchpadMarkup.linkSpans(in: relaunched.text).count == 1)
}

@Test @MainActor func reportsAnErrorWhenTheDirectoryCannotBeUsed() async throws {
    // A path under an existing *file* can never be created as a directory.
    let dir = try TemporaryDirectory()
    try dir.write("blocking file")
    let impossible = dir.scratchpad.appending(path: "nested")

    let store = ScratchpadStore(directory: impossible, debounce: fastDebounce)
    store.text = "this cannot be saved"
    try await Task.sleep(for: afterDebounce)

    #expect(store.saveError != nil)
    #expect(store.text == "this cannot be saved")
}
