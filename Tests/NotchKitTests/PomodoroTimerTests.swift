import Combine
import Testing
import Foundation
@testable import NotchKit

/// A timer whose ticking task effectively never fires, so every test drives
/// the countdown by hand through `advance(by:)` — no wall-clock sleeps.
@MainActor
private func handDrivenTimer(
    work: Duration = .seconds(5),
    rest: Duration = .seconds(3)
) -> PomodoroTimer {
    PomodoroTimer(work: work, rest: rest, tick: .seconds(3600))
}

private let second = Duration.seconds(1)

// MARK: - Initial state

@Test @MainActor func startsIdleInWorkAtFullDuration() {
    let timer = PomodoroTimer()

    #expect(timer.phase == .work)
    #expect(timer.remaining == .seconds(25 * 60))
    #expect(!timer.isRunning)
}

// MARK: - Start, pause, toggle

@Test @MainActor func toggleStartsAndPauses() {
    let timer = handDrivenTimer()

    timer.toggle()
    #expect(timer.isRunning)

    timer.toggle()
    #expect(!timer.isRunning)
}

@Test @MainActor func startingTwiceIsHarmless() {
    let timer = handDrivenTimer()

    timer.start()
    timer.start()
    timer.advance(by: second)

    #expect(timer.isRunning)
    #expect(timer.remaining == .seconds(4))
}

@Test @MainActor func pausingHoldsTheCount() {
    let timer = handDrivenTimer()
    timer.start()
    timer.advance(by: second)

    timer.pause()
    timer.advance(by: second)

    #expect(timer.remaining == .seconds(4))
}

@Test @MainActor func resumingContinuesWhereItPaused() {
    let timer = handDrivenTimer()
    timer.start()
    timer.advance(by: second)
    timer.pause()

    timer.start()
    timer.advance(by: second)

    #expect(timer.remaining == .seconds(3))
}

// MARK: - Counting down

@Test @MainActor func countingDownReducesRemaining() {
    let timer = handDrivenTimer()
    timer.start()

    timer.advance(by: second)
    timer.advance(by: second)

    #expect(timer.remaining == .seconds(3))
}

@Test @MainActor func aTimerThatWasNeverStartedDoesNotCount() {
    let timer = handDrivenTimer()

    timer.advance(by: second)

    #expect(timer.remaining == .seconds(5))
}

// MARK: - Phase completion

@Test @MainActor func finishedWorkRollsIntoBreakStillRunning() {
    let timer = handDrivenTimer()
    timer.start()

    timer.advance(by: .seconds(5))

    #expect(timer.phase == .rest)
    #expect(timer.remaining == .seconds(3))
    #expect(timer.isRunning)
}

@Test @MainActor func finishedBreakRollsBackIntoWork() {
    let timer = handDrivenTimer()
    timer.start()
    timer.advance(by: .seconds(5))

    timer.advance(by: .seconds(3))

    #expect(timer.phase == .work)
    #expect(timer.remaining == .seconds(5))
}

@Test @MainActor func anOvershootingTickStillCompletesThePhase() {
    let timer = handDrivenTimer()
    timer.start()

    timer.advance(by: .seconds(99))

    #expect(timer.phase == .rest)
    #expect(timer.remaining == .seconds(3))
}

@Test @MainActor func eachFinishedIntervalIsAnnouncedWithItsPhase() {
    let timer = handDrivenTimer()
    var announced: [PomodoroPhase] = []
    let subscription = timer.phaseCompletions.sink { announced.append($0) }
    defer { subscription.cancel() }

    timer.start()
    timer.advance(by: .seconds(5))
    timer.advance(by: .seconds(3))

    #expect(announced == [.work, .rest])
}

@Test @MainActor func merelyCountingAnnouncesNothing() {
    let timer = handDrivenTimer()
    var announcements = 0
    let subscription = timer.phaseCompletions.sink { _ in announcements += 1 }
    defer { subscription.cancel() }

    timer.start()
    timer.advance(by: second)
    timer.pause()
    timer.reset()

    #expect(announcements == 0)
}

// MARK: - Reset

@Test @MainActor func resetRestoresThePhaseDurationAndStops() {
    let timer = handDrivenTimer()
    timer.start()
    timer.advance(by: .seconds(2))

    timer.reset()

    #expect(timer.phase == .work)
    #expect(timer.remaining == .seconds(5))
    #expect(!timer.isRunning)
}

// MARK: - Switching phase

@Test @MainActor func switchingArmsTheOtherPhaseFromTheTop() {
    let timer = handDrivenTimer()

    timer.switchPhase()

    #expect(timer.phase == .rest)
    #expect(timer.remaining == .seconds(3))
    #expect(!timer.isRunning)
}

@Test @MainActor func switchingMidCountKeepsTheTimerRunning() {
    let timer = handDrivenTimer()
    timer.start()
    timer.advance(by: second)

    timer.switchPhase()

    #expect(timer.phase == .rest)
    #expect(timer.remaining == .seconds(3))
    #expect(timer.isRunning)
}

// MARK: - The ticking task

/// The one wall-clock test: proves the started task actually drives
/// `advance(by:)`. Everything about *what* advancing does is covered above.
@Test @MainActor func theTickerDrivesTheCountdown() async throws {
    let timer = PomodoroTimer(
        work: .seconds(600),
        rest: .seconds(60),
        tick: .milliseconds(10)
    )

    timer.start()
    try await Task.sleep(for: .milliseconds(100))

    #expect(timer.remaining < .seconds(600))
    timer.pause()
}

// MARK: - Display

@Test func formatsRemainingAsMinutesAndSeconds() {
    #expect(PomodoroTimer.timeString(for: .seconds(25 * 60)) == "25:00")
    #expect(PomodoroTimer.timeString(for: .seconds(9 * 60 + 5)) == "09:05")
    #expect(PomodoroTimer.timeString(for: .zero) == "00:00")
}

@Test func clampsNegativeRemainingToZero() {
    #expect(PomodoroTimer.timeString(for: .seconds(-3)) == "00:00")
}
