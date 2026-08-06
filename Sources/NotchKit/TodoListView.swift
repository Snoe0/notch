import SwiftUI

/// The checklist column: the todos, then the field that appends to them.
public struct TodoListView: View {
    @ObservedObject var store: TodoStore
    @State private var draft: String = ""
    @FocusState private var isAddingTodo: Bool

    /// Matches the scratchpad's monospaced face one step smaller, so the two
    /// columns read as one surface.
    private static let font = Font.system(size: 12, design: .monospaced)

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

    /// The placeholder is drawn rather than passed to `TextField`, whose own
    /// prompt colour is not legible on black.
    private var addField: some View {
        ZStack(alignment: .leading) {
            if draft.isEmpty {
                Text("add a todo…")
                    .foregroundStyle(.white.opacity(0.35))
            }
            TextField("", text: $draft)
                .textFieldStyle(.plain)
                .foregroundStyle(.white)
                .focused($isAddingTodo)
                .onSubmit(commitDraft)
        }
        .onChange(of: isAddingTodo) { _, focused in store.isEditing = focused }
    }

    /// The store drops blank input, so Return never needs a guard here.
    private func commitDraft() {
        store.add(draft)
        draft = ""
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
        HStack(spacing: 6) {
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
        Text(item.text)
            .strikethrough(item.isDone)
            .foregroundStyle(.white.opacity(item.isDone ? 0.35 : 0.9))
            .lineLimit(1)
            .truncationMode(.tail)
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
