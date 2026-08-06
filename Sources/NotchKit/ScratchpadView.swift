import SwiftUI

public struct ScratchpadView: View {
    @ObservedObject var store: ScratchpadStore
    let isPinned: Bool
    /// False while another field in the panel holds the caret. Being pinned is
    /// not by itself a reason to claim focus back from it.
    let takesFocus: Bool

    public init(store: ScratchpadStore, isPinned: Bool, takesFocus: Bool = true) {
        self.store = store
        self.isPinned = isPinned
        self.takesFocus = takesFocus
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ScratchpadTextView(
                text: $store.text,
                placeholder: isPinned ? "type…" : "click to write",
                shouldFocus: isPinned && takesFocus,
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
