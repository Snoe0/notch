import SwiftUI

/// The pomodoro strip that sits to the right of the notch, mirroring the media
/// strip on the left: transport-style buttons against the notch, the readout
/// at the outer edge. Sized for the same roughly 215×32pt flank.
public struct PomodoroControlsView: View {
    @ObservedObject var timer: PomodoroTimer

    public init(timer: PomodoroTimer) {
        self.timer = timer
    }

    public var body: some View {
        HStack(spacing: 6) {
            controls
            Spacer(minLength: 4)
            readout
        }
        // Mirror of the media strip's padding: leading hugs the notch, which
        // provides its own visual margin; trailing matches the notes column.
        .padding(.leading, 6)
        .padding(.trailing, 18)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var controls: some View {
        HStack(spacing: 1) {
            controlButton(startPauseSymbol, size: 12) { timer.toggle() }
            controlButton("arrow.counterclockwise", size: 10) { timer.reset() }
        }
    }

    private var startPauseSymbol: String {
        timer.isRunning ? "pause.fill" : "play.fill"
    }

    /// Phase name and remaining time, doubling as the phase switch — a tap
    /// flips work and break. A gesture rather than a button for the same
    /// reason as the media strip's now-playing area: it can never take focus,
    /// so it can never pull the caret out of the notes.
    private var readout: some View {
        HStack(spacing: 6) {
            Text(timer.phase.label)
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.5))
            Text(PomodoroTimer.timeString(for: timer.remaining))
                .font(.system(size: 11).monospacedDigit())
                .foregroundStyle(.white)
        }
        .contentShape(.rect)
        .onTapGesture { timer.switchPhase() }
    }

    private func controlButton(
        _ symbol: String,
        size: CGFloat,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .medium))
                .frame(width: 17, height: 20)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        // Same rule as the media transport: the panel's only focusable
        // control is the text it is written in.
        .focusable(false)
        .foregroundStyle(.white.opacity(0.85))
    }
}
