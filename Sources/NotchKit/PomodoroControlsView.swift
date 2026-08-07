import SwiftUI

/// The pomodoro strip beside the notch, mirroring the media strip on the
/// other flank: transport-style buttons against the notch, the readout at the
/// outer edge. Sized for the same roughly 215×32pt flank.
public struct PomodoroControlsView: View {
    @ObservedObject var timer: PomodoroTimer
    /// Which flank of the notch the strip occupies. The layout mirrors with
    /// it, so the buttons stay against the notch on either side.
    let flank: HorizontalEdge

    public init(timer: PomodoroTimer, flank: HorizontalEdge = .trailing) {
        self.timer = timer
        self.flank = flank
    }

    public var body: some View {
        HStack(spacing: 6) {
            if flank == .trailing {
                controls
                Spacer(minLength: 4)
                readout
            } else {
                readout
                Spacer(minLength: 4)
                controls
            }
        }
        // Mirror of the media strip's padding: the notch edge keeps just a
        // sliver, because the notch provides its own visual margin; the outer
        // edge matches the column below.
        .padding(.leading, flank == .trailing ? 6 : 18)
        .padding(.trailing, flank == .trailing ? 18 : 6)
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
