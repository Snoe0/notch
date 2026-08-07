import SwiftUI

/// What the collapsed-notch pomodoro chip shows. A value, not the timer
/// itself, for the same reason the chrome takes a `MediaPopout` rather than
/// the media controller: the chrome only ever draws what it is handed.
public struct PomodoroChip: Equatable, Sendable {
    public let phase: PomodoroPhase
    public let remaining: Duration

    public init(phase: PomodoroPhase, remaining: Duration) {
        self.phase = phase
        self.remaining = remaining
    }
}

/// The running countdown, shown in the menu bar band beside a collapsed notch
/// — the trailing-flank mirror of the now-playing chip. Unlike that chip it
/// has no expiry: it stays out for as long as the timer runs, because a
/// countdown is exactly the thing one glances at mid-count.
///
/// It carries no geometry of its own: the chrome hands it the notch's trailing
/// flank to live in, so it hugs its content and fills the band's height.
struct PomodoroChipView: View {
    let chip: PomodoroChip
    /// How much of the chip's leading end sits under the physical notch —
    /// the mirror of the now-playing chip's trailing overhang, closing the
    /// same potential seam on the other side.
    let notchOverhang: CGFloat

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "timer")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white.opacity(0.55))
            Text(PomodoroTimer.timeString(for: chip.remaining))
                .font(.system(size: 11).monospacedDigit())
                .foregroundStyle(.white)
        }
        .padding(.leading, 11 + notchOverhang)
        .padding(.trailing, 12)
        // Fills the notch band rather than sizing to the row, so the black
        // reaches the screen edge above and the notch's own bottom below.
        .frame(maxHeight: .infinity)
        .notchChipSurface(notchEdge: .leading)
    }
}
