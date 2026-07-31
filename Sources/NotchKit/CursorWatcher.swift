import AppKit

/// Reports whether the cursor is inside a rect by polling `NSEvent.mouseLocation`.
///
/// Reading the cursor position is not TCC-gated — only *monitoring events* is.
/// That makes polling the one hover mechanism that needs no permission at all:
///
/// - `addGlobalMonitorForEvents` requires Input Monitoring on macOS 15.4+.
/// - `NSTrackingArea` needs a window under the cursor that accepts mouse
///   events, so it would have to swallow clicks over the notch — and in
///   practice such a window only begins reporting after it receives a real
///   mouse event, so hover did not register until the notch was clicked.
///
/// A point-in-rect test 30 times a second is far cheaper than either.
@MainActor
public final class CursorWatcher {
    /// The region that currently counts as "inside". Swapped by the controller
    /// when the panel opens, so moving into the panel is still "inside".
    public var activeRect: CGRect = .zero

    /// Fired only when the inside/outside answer actually changes.
    public var onChange: ((Bool) -> Void)?

    private let interval: TimeInterval
    private var timer: DispatchSourceTimer?
    private var isInside = false

    public init(interval: TimeInterval = 1.0 / 30.0) {
        self.interval = interval
    }

    public func start() {
        stop()
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now(), repeating: interval, leeway: .milliseconds(5))
        timer.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.evaluate() }
        }
        timer.resume()
        self.timer = timer
    }

    public func stop() {
        timer?.cancel()
        timer = nil
    }

    private func evaluate() {
        let inside = activeRect.contains(NSEvent.mouseLocation)
        guard inside != isInside else { return }
        isInside = inside
        onChange?(inside)
    }
}
