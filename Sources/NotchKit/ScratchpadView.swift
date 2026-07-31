import SwiftUI

public struct ScratchpadView: View {
    @ObservedObject var store: ScratchpadStore
    let isPinned: Bool
    @FocusState private var isFocused: Bool

    public init(store: ScratchpadStore, isPinned: Bool) {
        self.store = store
        self.isPinned = isPinned
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            editor
            if let error = store.saveError {
                banner(error)
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 10)
        .padding(.bottom, 14)
        .onChange(of: isPinned) { _, pinned in isFocused = pinned }
        .onChange(of: isFocused) { _, focused in store.isEditing = focused }
    }

    private var editor: some View {
        TextEditor(text: $store.text)
            .focused($isFocused)
            .font(.system(size: 13, weight: .regular, design: .monospaced))
            .foregroundStyle(.white)
            .tint(.white)
            .scrollContentBackground(.hidden)
            .background(.clear)
            .overlay(alignment: .topLeading) {
                if store.text.isEmpty {
                    Text(isPinned ? "type…" : "click to write")
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.35))
                        .padding(.top, 8)
                        .padding(.leading, 5)
                        .allowsHitTesting(false)
                }
            }
    }

    private func banner(_ message: String) -> some View {
        Label("Not saved: \(message)", systemImage: "exclamationmark.triangle.fill")
            .font(.system(size: 10))
            .foregroundStyle(.orange)
            .lineLimit(1)
    }
}
