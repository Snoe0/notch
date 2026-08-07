import Combine
import Foundation

/// The two intervals a pomodoro alternates between. `rest` is shown to the
/// user as "Break" — the classic name — but `break` is a Swift keyword and not
/// worth the backticks at every call site.
public enum PomodoroPhase: Equatable, Sendable, CaseIterable {
    case work
    case rest

    public var other: PomodoroPhase {
        self == .work ? .rest : .work
    }

    public var label: String {
        self == .work ? "Work" : "Break"
    }
}

/// Drives the pomodoro strip: counts an interval down, rolls into the other
/// interval when it runs out, and announces each completion so something
/// audible can mark it.
///
/// The countdown is deliberately split in two, the same seam idea as
/// `MediaController`'s injected scripting: `advance(by:)` holds all the
/// arithmetic and phase policy and is a plain synchronous method tests drive
/// directly, while the ticking task only ever sleeps and calls it. State lives
/// here rather than in any view, so it survives the panel opening and closing;
/// it is not persisted across relaunch.
@MainActor
public final class PomodoroTimer: ObservableObject {
    @Published public private(set) var phase: PomodoroPhase = .work
    @Published public private(set) var remaining: Duration
    @Published public private(set) var isRunning = false

    /// Fires once per finished interval, carrying the phase that just ended.
    /// The controller keys the completion sound off this, the same shape as
    /// `MediaController.playbackEvents`.
    public var phaseCompletions: AnyPublisher<PomodoroPhase, Never> {
        completionSubject.eraseToAnyPublisher()
    }

    private let durations: [PomodoroPhase: Duration]
    private let tick: Duration
    private let completionSubject = PassthroughSubject<PomodoroPhase, Never>()
    private var ticking: Task<Void, Never>?

    public init(
        work: Duration = .seconds(25 * 60),
        rest: Duration = .seconds(5 * 60),
        tick: Duration = .seconds(1)
    ) {
        self.durations = [.work: work, .rest: rest]
        self.tick = tick
        self.remaining = work
    }

    deinit { ticking?.cancel() }

    // MARK: - Controls

    public func start() {
        guard !isRunning else { return }
        isRunning = true
        ticking = Task { [weak self, tick] in
            while !Task.isCancelled {
                try? await Task.sleep(for: tick)
                guard !Task.isCancelled else { return }
                self?.advance(by: tick)
            }
        }
    }

    public func pause() {
        ticking?.cancel()
        ticking = nil
        isRunning = false
    }

    /// The start/pause button's single action.
    public func toggle() {
        isRunning ? pause() : start()
    }

    /// Back to the top of the current interval, stopped. Resetting while the
    /// count is running would restart it silently, which reads as a glitch.
    public func reset() {
        pause()
        remaining = duration(of: phase)
    }

    /// Arms the other interval from the top. Running state is preserved: a
    /// user who flips to Break mid-count wants the break to start counting,
    /// not a second tap.
    public func switchPhase() {
        phase = phase.other
        remaining = duration(of: phase)
    }

    // MARK: - Countdown

    /// One step of the countdown. Internal rather than private so tests can
    /// drive the arithmetic and the phase policy without wall-clock sleeps —
    /// the same reasoning as `MediaController.handlePlaybackNotification`.
    func advance(by delta: Duration) {
        guard isRunning else { return }
        remaining -= delta
        guard remaining <= .zero else { return }
        completeCurrentPhase()
    }

    /// Rolling into the other interval keeps the count running: work, chime,
    /// break, chime, work — the kitchen-timer rhythm. Stopping is always the
    /// user's move, via pause or reset.
    private func completeCurrentPhase() {
        let finished = phase
        phase = phase.other
        remaining = duration(of: phase)
        completionSubject.send(finished)
    }

    private func duration(of phase: PomodoroPhase) -> Duration {
        durations[phase] ?? .zero
    }

    // MARK: - Display

    /// "mm:ss", clamped at zero so a mid-tick overshoot never shows a minus.
    nonisolated static func timeString(for remaining: Duration) -> String {
        let totalSeconds = max(0, remaining.components.seconds)
        return String(format: "%02d:%02d", totalSeconds / 60, totalSeconds % 60)
    }
}
