import Testing
@testable import NotchKit

@MainActor
private func machine() -> NotchStateMachine {
    NotchStateMachine(openDelay: .milliseconds(20), closeDelay: .milliseconds(20))
}

private let settle = Duration.milliseconds(120)
private let beforeDelay = Duration.milliseconds(5)

@Test @MainActor func hoveringOpensThePanelAfterTheOpenDelay() async throws {
    let notch = machine()
    notch.hoverChanged(inside: true)

    #expect(notch.state == .collapsed)   // not yet
    try await Task.sleep(for: settle)
    #expect(notch.state == .peek)
}

@Test @MainActor func passingThroughTheNotchDoesNotOpenIt() async throws {
    let notch = machine()
    notch.hoverChanged(inside: true)
    try await Task.sleep(for: beforeDelay)
    notch.hoverChanged(inside: false)

    try await Task.sleep(for: settle)
    #expect(notch.state == .collapsed)
}

@Test @MainActor func leavingCollapsesAfterTheGracePeriod() async throws {
    let notch = machine()
    notch.hoverChanged(inside: true)
    try await Task.sleep(for: settle)

    notch.hoverChanged(inside: false)
    #expect(notch.state == .peek)        // grace period still running
    try await Task.sleep(for: settle)
    #expect(notch.state == .collapsed)
}

@Test @MainActor func returningDuringTheGracePeriodKeepsItOpen() async throws {
    let notch = machine()
    notch.hoverChanged(inside: true)
    try await Task.sleep(for: settle)

    notch.hoverChanged(inside: false)
    try await Task.sleep(for: beforeDelay)
    notch.hoverChanged(inside: true)

    try await Task.sleep(for: settle)
    #expect(notch.state == .peek)
}

@Test @MainActor func clickingWhilePeekingPinsThePanel() async throws {
    let notch = machine()
    notch.hoverChanged(inside: true)
    try await Task.sleep(for: settle)

    notch.click()
    #expect(notch.state == .pinned)
}

@Test @MainActor func pinnedIgnoresHoverAndClosesOnlyOnDismiss() async throws {
    let notch = machine()
    notch.hoverChanged(inside: true)
    try await Task.sleep(for: settle)
    notch.click()

    notch.hoverChanged(inside: false)
    try await Task.sleep(for: settle)
    #expect(notch.state == .pinned)

    notch.dismiss()
    #expect(notch.state == .collapsed)
}

@Test @MainActor func clickingWhileCollapsedDoesNothing() {
    let notch = machine()
    notch.click()
    #expect(notch.state == .collapsed)
}
