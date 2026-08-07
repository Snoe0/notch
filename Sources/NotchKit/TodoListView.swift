import SwiftUI

/// The checklist column: the todos, then the field that appends to them.
public struct TodoListView: View {
    @ObservedObject var store: TodoStore

    /// Matches the scratchpad's face one step smaller, so the two columns read
    /// as one surface.
    private static let font = Font.system(size: 12)

    public init(store: TodoStore) {
        self.store = store
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            rows
            addField
            if let error = store.saveError {
                banner(error)
            }
        }
        .font(Self.font)
        .padding(.horizontal, 18)
        .padding(.top, 10)
        .padding(.bottom, 14)
    }

    private var rows: some View {
        ScrollView(.vertical) {
            LazyVStack(alignment: .leading, spacing: 4) {
                ForEach(store.items) { item in
                    TodoRow(
                        item: item,
                        toggle: { store.toggle(item.id) },
                        delete: { store.delete(item.id) }
                    )
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.never)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    /// `isEditing` is what stops a reload from disk landing mid-word, so it has
    /// to follow the caret, not the keystrokes.
    private var addField: some View {
        TodoAddField(
            placeholder: "add a todo…",
            onCommit: { store.add($0) },
            onEditingChange: { store.isEditing = $0 }
        )
        // A faint well fades in while the field holds the caret. Drawn with
        // negative padding so taking focus never shifts the layout under the
        // caret it is highlighting.
        .background {
            RoundedRectangle(cornerRadius: 6)
                .fill(.white.opacity(store.isEditing ? 0.08 : 0))
                .padding(-5)
        }
        .animation(.easeOut(duration: 0.18), value: store.isEditing)
    }

    private func banner(_ message: String) -> some View {
        Label("Not saved: \(message)", systemImage: "exclamationmark.triangle.fill")
            .font(.system(size: 10))
            .foregroundStyle(.orange)
            .lineLimit(1)
    }
}

/// One todo. Owns its own hover state so the delete button appears on the row
/// the cursor is actually over.
private struct TodoRow: View {
    let item: TodoItem
    let toggle: () -> Void
    let delete: () -> Void

    @State private var isHovering = false

    var body: some View {
        // First-baseline alignment keeps the checkbox on the opening line when
        // a long title wraps, instead of drifting to the row's vertical center.
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            checkbox
            text
            Spacer(minLength: 4)
            if isHovering {
                deleteButton
            }
        }
        .contentShape(.rect)
        .onHover { isHovering = $0 }
    }

    private var checkbox: some View {
        iconButton(
            item.isDone ? "checkmark.square" : "square",
            opacity: item.isDone ? 0.45 : 0.8,
            action: toggle
        )
    }

    private var deleteButton: some View {
        iconButton("xmark", opacity: 0.5, action: delete)
    }

    private var text: some View {
        // Long titles wrap instead of truncating; strikethrough is applied to
        // the whole Text, so it carries across every wrapped line.
        Text(item.text)
            .strikethrough(item.isDone)
            .foregroundStyle(.white.opacity(item.isDone ? 0.35 : 0.9))
            .fixedSize(horizontal: false, vertical: true)
    }

    private func iconButton(
        _ symbol: String,
        opacity: Double,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11))
                .frame(width: 14, height: 14)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        // Focus belongs to whichever text field the user chose; a button that
        // took it would pull the caret out from under them.
        .focusable(false)
        .foregroundStyle(.white.opacity(opacity))
    }
}
