import Foundation
import Combine

public enum NotchState: Equatable, Sendable {
    /// Nothing drawn. The panel ignores mouse events.
    case collapsed
    /// Open because the cursor is inside it. Closes when the cursor leaves.
    case peek
    /// Open until explicitly dismissed. Hover is ignored.
    case pinned

    public var isOpen: Bool { self != .collapsed }
}

/// The open/close policy, with no AppKit in it so it can be tested headlessly.
///
/// The two delays exist to stop the panel flapping when the user is reaching
/// for a menu bar item near the top of the screen.
@MainActor
public final class NotchStateMachine: ObservableObject {
    @Published public private(set) var state: NotchState = .collapsed

    private let openDelay: Duration
    private let closeDelay: Duration
    private var pendingTransition: Task<Void, Never>?

    public init(
        openDelay: Duration = .milliseconds(180),
        closeDelay: Duration = .milliseconds(250)
    ) {
        self.openDelay = openDelay
        self.closeDelay = closeDelay
    }

    public func hoverChanged(inside: Bool) {
        switch (state, inside) {
        case (.collapsed, true):  transition(to: .peek, after: openDelay)
        case (.collapsed, false): cancelPending()
        case (.peek, false):      transition(to: .collapsed, after: closeDelay)
        case (.peek, true):       cancelPending()
        case (.pinned, _):        break
        }
    }

    public func click() {
        guard state == .peek else { return }
        cancelPending()
        state = .pinned
    }

    public func dismiss() {
        cancelPending()
        state = .collapsed
    }

    private func transition(to next: NotchState, after delay: Duration) {
        cancelPending()
        pendingTransition = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            self?.state = next
        }
    }

    private func cancelPending() {
        pendingTransition?.cancel()
        pendingTransition = nil
    }
}
