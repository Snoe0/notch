import Testing
import Foundation
@testable import NotchKit

/// Ids are minted per parse, so comparisons look at the content only.
private func contents(of items: [TodoItem]) -> [String] {
    items.map { "\($0.isDone ? "x" : " ")|\($0.text)" }
}

@Test func parsesCheckedAndUncheckedLines() {
    let items = TodoMarkdown.parse("- [ ] ship v2\n- [x] email Sam\n")

    #expect(items.map(\.text) == ["ship v2", "email Sam"])
    #expect(items.map(\.isDone) == [false, true])
}

@Test func acceptsAnUppercaseCheckMarkAndSurroundingWhitespace() {
    let items = TodoMarkdown.parse("   - [X]   book the flight   ")

    #expect(items.map(\.text) == ["book the flight"])
    #expect(items.map(\.isDone) == [true])
}

@Test func dropsEverythingThatIsNotAChecklistLine() {
    let markdown = """
        # Today

        - [ ] real todo
        just a note
        - not a checkbox
        - [ ]
        """

    #expect(TodoMarkdown.parse(markdown).map(\.text) == ["real todo"])
}

@Test func parsesAnEmptyFileAsAnEmptyList() {
    #expect(TodoMarkdown.parse("").isEmpty)
}

@Test func serializesOneLinePerItemWithATrailingNewline() {
    let items = [
        TodoItem(text: "ship v2"),
        TodoItem(text: "email Sam", isDone: true),
    ]

    #expect(TodoMarkdown.serialize(items) == "- [ ] ship v2\n- [x] email Sam\n")
}

@Test func serializesAnEmptyListAsAnEmptyFile() {
    #expect(TodoMarkdown.serialize([]) == "")
}

@Test func roundTripsThroughSerializeAndParse() {
    let items = [
        TodoItem(text: "ship v2"),
        TodoItem(text: "email Sam", isDone: true),
        TodoItem(text: "buy milk [not a checkbox]"),
    ]

    let reparsed = TodoMarkdown.parse(TodoMarkdown.serialize(items))

    #expect(contents(of: reparsed) == contents(of: items))
}

@Test func serializingNormalizesAMessyFile() {
    let messy = "# notes\n  - [X]  done thing  \n\n- [ ] next thing\n"

    let normalized = TodoMarkdown.serialize(TodoMarkdown.parse(messy))

    #expect(normalized == "- [x] done thing\n- [ ] next thing\n")
}
