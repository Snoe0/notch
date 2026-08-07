import Testing
import Foundation
@testable import NotchKit

// MARK: - Parsing

@Test func findsAHighlightSpanBetweenDoubleEqualsMarkers() {
    let text = "call ==Ann== today"
    let spans = ScratchpadMarkup.markupSpans(in: text)

    #expect(spans.count == 1)
    #expect(spans[0].style == .highlight)
    #expect((text as NSString).substring(with: spans[0].innerRange) == "Ann")
    #expect((text as NSString).substring(with: spans[0].fullRange) == "==Ann==")
}

@Test func findsAnUnderlineSpanBetweenUTags() {
    let text = "the <u>rent</u> is due"
    let spans = ScratchpadMarkup.markupSpans(in: text)

    #expect(spans.count == 1)
    #expect(spans[0].style == .underline)
    #expect((text as NSString).substring(with: spans[0].innerRange) == "rent")
    #expect((text as NSString).substring(with: spans[0].fullRange) == "<u>rent</u>")
}

@Test func spansNeverCrossALineBreak() {
    let spans = ScratchpadMarkup.markupSpans(in: "==first\nsecond==")
    #expect(spans.isEmpty)
}

@Test func spanRangesAreUTF16SoEmojiUpstreamDoesNotShiftThem() {
    let text = "🙂 ==hi=="
    let spans = ScratchpadMarkup.markupSpans(in: text)

    #expect(spans.count == 1)
    #expect((text as NSString).substring(with: spans[0].innerRange) == "hi")
}

@Test func detectsAFullURLAsALink() {
    let text = "docs at https://example.com/a?b=1 tonight"
    let links = ScratchpadMarkup.linkSpans(in: text)

    #expect(links.count == 1)
    #expect(links[0].url.absoluteString == "https://example.com/a?b=1")
    #expect((text as NSString).substring(with: links[0].range) == "https://example.com/a?b=1")
}

@Test func detectsABareWWWAddressAsALink() {
    let links = ScratchpadMarkup.linkSpans(in: "see www.apple.com")

    #expect(links.count == 1)
    #expect(links[0].url.host() == "www.apple.com")
}

@Test func plainProseContainsNoLinks() {
    #expect(ScratchpadMarkup.linkSpans(in: "gate 34, 6:40pm").isEmpty)
}

// MARK: - Toggling on

@Test func togglingASelectionWrapsItInHighlightMarkers() throws {
    let edit = try #require(
        ScratchpadMarkup.toggle(.highlight, in: "hello world", selection: NSRange(location: 6, length: 5))
    )

    #expect(edit.replacementRange == NSRange(location: 6, length: 5))
    #expect(edit.replacement == "==world==")
    // The original word stays selected, inside the new markers.
    #expect(edit.selectionAfter == NSRange(location: 8, length: 5))
}

@Test func togglingASelectionWrapsItInUnderlineTags() throws {
    let edit = try #require(
        ScratchpadMarkup.toggle(.underline, in: "hello world", selection: NSRange(location: 0, length: 5))
    )

    #expect(edit.replacement == "<u>hello</u>")
    #expect(edit.selectionAfter == NSRange(location: 3, length: 5))
}

@Test func togglingAnEmptySelectionInsertsMarkersWithTheCaretBetweenThem() throws {
    let edit = try #require(
        ScratchpadMarkup.toggle(.highlight, in: "note: ", selection: NSRange(location: 6, length: 0))
    )

    #expect(edit.replacement == "====")
    #expect(edit.selectionAfter == NSRange(location: 8, length: 0))
}

// MARK: - Toggling off

@Test func togglingInsideAnExistingSpanUnwrapsIt() throws {
    let text = "call ==Ann== today"
    let edit = try #require(
        // Selection sits on "Ann", inside the markers.
        ScratchpadMarkup.toggle(.highlight, in: text, selection: NSRange(location: 7, length: 3))
    )

    #expect(edit.replacementRange == NSRange(location: 5, length: 7))
    #expect(edit.replacement == "Ann")
    #expect(edit.selectionAfter == NSRange(location: 5, length: 3))
}

@Test func togglingASelectionThatIncludesTheMarkersAlsoUnwraps() throws {
    let text = "the <u>rent</u> is due"
    let edit = try #require(
        ScratchpadMarkup.toggle(.underline, in: text, selection: NSRange(location: 4, length: 11))
    )

    #expect(edit.replacementRange == NSRange(location: 4, length: 11))
    #expect(edit.replacement == "rent")
    #expect(edit.selectionAfter == NSRange(location: 4, length: 4))
}

@Test func stylesToggleIndependentlyOfEachOther() throws {
    // A caret inside a highlight still *adds* an underline rather than
    // removing the highlight.
    let text = "==Ann=="
    let edit = try #require(
        ScratchpadMarkup.toggle(.underline, in: text, selection: NSRange(location: 2, length: 3))
    )

    #expect(edit.replacement == "<u>Ann</u>")
}

@Test func anOutOfBoundsSelectionProducesNoEdit() {
    #expect(ScratchpadMarkup.toggle(.highlight, in: "hi", selection: NSRange(location: 1, length: 5)) == nil)
    #expect(
        ScratchpadMarkup.toggle(
            .highlight, in: "hi", selection: NSRange(location: NSNotFound, length: 0)
        ) == nil
    )
}
