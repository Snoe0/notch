import Testing
import Foundation
@testable import NotchKit

// The adapter itself is untested glue — it needs a running media app — but the
// two literals it has to parse are not, and both are easy to get wrong.

@Test func readsTheHexPayloadOfAnAppleScriptDataLiteral() {
    let data = OsascriptMediaScripting.artworkData(fromLiteral: "«data tdta48656C6C6F»\n")

    #expect(data == Data("Hello".utf8))
}

@Test func readsNoArtworkFromAnythingThatIsNotADataLiteral() {
    #expect(OsascriptMediaScripting.artworkData(fromLiteral: "") == nil)
    #expect(OsascriptMediaScripting.artworkData(fromLiteral: "\n") == nil)
    #expect(OsascriptMediaScripting.artworkData(fromLiteral: "«data tdta»") == nil)
    #expect(OsascriptMediaScripting.artworkData(fromLiteral: "«data tdta4865X»") == nil)
    #expect(OsascriptMediaScripting.artworkData(fromLiteral: "«data tdta486»") == nil)
    #expect(OsascriptMediaScripting.artworkData(fromLiteral: "Music got an error") == nil)
}

@Test func takesOnlyHttpArtworkURLs() {
    let url = OsascriptMediaScripting.artworkURL(fromLiteral: " https://i.scdn.co/image/abc\n")

    #expect(url?.absoluteString == "https://i.scdn.co/image/abc")
    #expect(OsascriptMediaScripting.artworkURL(fromLiteral: "") == nil)
    #expect(OsascriptMediaScripting.artworkURL(fromLiteral: "file:///etc/passwd") == nil)
}
