import AppKit

/// Reports whether the cursor is inside a rect, using global mouse monitoring.
///
/// Mouse monitoring needs no Accessibility permission — only keyboard
/// monitoring does — so the app prompts for nothing.
@MainActor
public final class HoverMonitor {
    /// The region that currently counts as "inside". Swapped by the controller
    /// when the panel opens, so moving into the panel is still "inside".
    public var activeRect: CGRect = .zero

    /// Fired only when the inside/outside answer actually changes.
    public var onChange: ((Bool) -> Void)?

    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var isInside = false

    private static let events: NSEvent.EventTypeMask = [
        .mouseMoved, .leftMouseDragged, .rightMouseDragged,
    ]

    public init() {}

    public func start() {
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: Self.events) { [weak self] _ in
            MainActor.assumeIsolated { self?.evaluate() }
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: Self.events) { [weak self] event in
            MainActor.assumeIsolated { self?.evaluate() }
            return event
        }
    }

    public func stop() {
        [globalMonitor, localMonitor].compactMap { $0 }.forEach(NSEvent.removeMonitor)
        globalMonitor = nil
        localMonitor = nil
    }

    // No deinit: `NSEvent.removeMonitor` is main-thread-only and `deinit` is not
    // actor-isolated in Swift 6. The monitor lives as long as the app does, so
    // teardown goes through `stop()` instead.

    private func evaluate() {
        let inside = activeRect.contains(NSEvent.mouseLocation)
        guard inside != isInside else { return }
        isInside = inside
        onChange?(inside)
    }
}
