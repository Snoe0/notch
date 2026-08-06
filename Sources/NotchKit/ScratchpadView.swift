import SwiftUI

public struct ScratchpadView: View {
    @ObservedObject var store: ScratchpadStore
    let isPinned: Bool

    public init(store: ScratchpadStore, isPinned: Bool) {
        self.store = store
        self.isPinned = isPinned
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ScratchpadTextView(
                text: $store.text,
                placeholder: isPinned ? "type…" : "click to write",
                shouldFocus: isPinned,
                onEditingChange: { store.isEditing = $0 }
            )
            if let error = store.saveError {
                banner(error)
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 10)
        .padding(.bottom, 14)
    }

    private func banner(_ message: String) -> some View {
        Label("Not saved: \(message)", systemImage: "exclamationmark.triangle.fill")
            .font(.system(size: 10))
            .foregroundStyle(.orange)
            .lineLimit(1)
    }
}
