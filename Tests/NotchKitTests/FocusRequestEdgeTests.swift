import Testing
@testable import NotchKit

/// Feeds a run of `shouldFocus` values through one edge and reports which of
/// them would have claimed the caret.
private func claims(from requests: [Bool]) -> [Bool] {
    var edge = FocusRequestEdge()
    return requests.map { edge.fires(on: $0) }
}

/// The rule the notes column claims the caret by. The claim itself needs a
/// window server; this is the part of it that does not.
@Test func claimsOnlyWhenTheRequestTurnsOn() {
    #expect(claims(from: [false, true]) == [false, true])
}

/// The regression this exists for: the panel stays pinned, so `shouldFocus`
/// stays true through every re-render. Only the first pass may take the caret,
/// or clicking into any other field would be undone by the next keystroke.
@Test func staysQuietWhileTheRequestRemainsOn() {
    #expect(claims(from: [true, true, true]) == [true, false, false])
}

/// Closing and reopening the panel is a new claim.
@Test func armsAgainAfterTheRequestTurnsOff() {
    #expect(claims(from: [true, false, true]) == [true, false, true])
}
