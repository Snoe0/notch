import SwiftUI

/// Everything below the notch strip: the checklist and the notes, split by a
/// hairline. Settings decide which columns are present and which side each
/// takes; a lone column simply gets the whole width. Each column carries its
/// own padding, so this view adds none of its own.
public struct PanelContentView: View {
    /// Passed straight through: each column observes the store it draws.
    let todos: TodoStore
    let scratchpad: ScratchpadStore
    let notesPopout: NotesPopoutPresenter
    let fontSetting: ScratchpadFontSetting
    let isPinned: Bool
    let showsTodos: Bool
    let showsNotes: Bool
    let swapsColumns: Bool

    private static let todoColumnFraction: CGFloat = 0.4

    init(
        todos: TodoStore,
        scratchpad: ScratchpadStore,
        notesPopout: NotesPopoutPresenter,
        fontSetting: ScratchpadFontSetting,
        isPinned: Bool,
        showsTodos: Bool = true,
        showsNotes: Bool = true,
        swapsColumns: Bool = false
    ) {
        self.todos = todos
        self.scratchpad = scratchpad
        self.notesPopout = notesPopout
        self.fontSetting = fontSetting
        self.isPinned = isPinned
        self.showsTodos = showsTodos
        self.showsNotes = showsNotes
        self.swapsColumns = swapsColumns
    }

    /// The todo column keeps its tuned fraction only while it shares the row —
    /// alone, either column stretches to the full width.
    public var body: some View {
        GeometryReader { proxy in
            HStack(spacing: 0) {
                if showsTodos && showsNotes {
                    let todoWidth = proxy.size.width * Self.todoColumnFraction
                    if swapsColumns {
                        notesColumn
                        divider
                        todoColumn.frame(width: todoWidth)
                    } else {
                        todoColumn.frame(width: todoWidth)
                        divider
                        notesColumn
                    }
                } else if showsTodos {
                    todoColumn
                } else if showsNotes {
                    notesColumn
                }
            }
        }
    }

    private var todoColumn: some View {
        TodoListView(store: todos)
    }

    private var notesColumn: some View {
        ScratchpadView(
            store: scratchpad,
            popout: notesPopout,
            fontSetting: fontSetting,
            isPinned: isPinned
        )
    }

    private var divider: some View {
        Rectangle()
            .fill(.white.opacity(0.08))
            .frame(width: 1)
            .padding(.vertical, 10)
    }
}
