import SwiftUI

/// Everything below the notch strip: the checklist on the left, the notes on
/// the right, split by a hairline. Each column carries its own padding, so
/// this view adds none of its own.
public struct PanelContentView: View {
    /// Passed straight through: each column observes the store it draws.
    let todos: TodoStore
    let scratchpad: ScratchpadStore
    let isPinned: Bool

    private static let todoColumnFraction: CGFloat = 0.4

    public init(todos: TodoStore, scratchpad: ScratchpadStore, isPinned: Bool) {
        self.todos = todos
        self.scratchpad = scratchpad
        self.isPinned = isPinned
    }

    public var body: some View {
        GeometryReader { proxy in
            HStack(spacing: 0) {
                TodoListView(store: todos)
                    .frame(width: proxy.size.width * Self.todoColumnFraction)
                divider
                ScratchpadView(store: scratchpad, isPinned: isPinned)
            }
        }
    }

    private var divider: some View {
        Rectangle()
            .fill(.white.opacity(0.08))
            .frame(width: 1)
            .padding(.vertical, 10)
    }
}
