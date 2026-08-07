import SwiftUI

public struct ScratchpadView: View {
    @ObservedObject var store: ScratchpadStore
    @StateObject private var fontSetting = ScratchpadFontSetting()
    let isPinned: Bool

    private static let textSize: CGFloat = 13

    public init(store: ScratchpadStore, isPinned: Bool) {
        self.store = store
        self.isPinned = isPinned
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            notes
            if let error = store.saveError {
                banner(error)
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 10)
        .padding(.bottom, 14)
    }

    private var notes: some View {
        ScratchpadTextView(
            text: $store.text,
            placeholder: isPinned ? "type…" : "click to write",
            font: fontSetting.choice.resolved(size: Self.textSize),
            shouldFocus: isPinned,
            onEditingChange: { store.isEditing = $0 }
        )
        .overlay(alignment: .topTrailing) { fontMenu }
    }

    /// A small "Aa" in the notes' top-right corner that picks the typeface.
    /// An NSMenu-backed `Menu` rather than anything focusable: menu tracking
    /// runs in its own session and never touches first responder, so picking
    /// a font leaves the caret exactly where it was in the text.
    private var fontMenu: some View {
        Menu {
            Picker("Notes font", selection: $fontSetting.choice) {
                ForEach(ScratchpadFont.allCases) { font in
                    Text(font.displayName).tag(font)
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        } label: {
            Text("Aa")
                .font(.system(size: 10, weight: .semibold))
                .frame(width: 20, height: 16)
                .contentShape(.rect)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        // Same rule as the media transport: the notes text is the panel's
        // only focusable control.
        .focusable(false)
        .foregroundStyle(.white.opacity(0.35))
        .help("Notes font")
    }

    private func banner(_ message: String) -> some View {
        Label("Not saved: \(message)", systemImage: "exclamationmark.triangle.fill")
            .font(.system(size: 10))
            .foregroundStyle(.orange)
            .lineLimit(1)
    }
}
