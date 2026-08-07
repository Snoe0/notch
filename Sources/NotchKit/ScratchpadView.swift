import SwiftUI

public struct ScratchpadView: View {
    @ObservedObject var store: ScratchpadStore
    @ObservedObject var popout: NotesPopoutPresenter
    @StateObject private var fontSetting = ScratchpadFontSetting()
    @StateObject private var sketchStore: SketchStore
    /// Deliberately not persisted: the panel always reopens on the notes.
    @State private var mode: Mode = .text
    @State private var ink: SketchInk = .white
    let isPinned: Bool
    /// True in the floating window host, false in the panel column.
    let isPopoutWindow: Bool

    private enum Mode {
        case text
        case sketch
    }

    private static let textSize: CGFloat = 13

    public init(
        store: ScratchpadStore,
        popout: NotesPopoutPresenter,
        isPinned: Bool,
        isPopoutWindow: Bool = false
    ) {
        self.store = store
        self.popout = popout
        self.isPinned = isPinned
        self.isPopoutWindow = isPopoutWindow
        // The sketch lives beside the markdown, in the same folder.
        _sketchStore = StateObject(wrappedValue: SketchStore(directory: store.directoryURL))
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if isDisplacedByPopout {
                poppedOutNotice
            } else {
                editor
            }
            if let error = saveError {
                banner(error)
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 10)
        .padding(.bottom, 14)
    }

    /// The panel column steps aside while the floating window owns the notes.
    /// A placeholder rather than a second live editor: two text views on one
    /// store would duel over first responder and race their edits. The view
    /// itself stays in the tree, so its sketch store keeps watching the file
    /// and returns already synced with whatever the window wrote.
    private var isDisplacedByPopout: Bool {
        popout.isPoppedOut && !isPopoutWindow
    }

    /// Either column face — typed notes or the sketch canvas — under the one
    /// corner-control cluster, so the controls never move when the mode flips.
    private var editor: some View {
        Group {
            switch mode {
            case .text: notes
            case .sketch: sketchCanvas
            }
        }
        .overlay(alignment: .topTrailing) { cornerControls }
    }

    private var saveError: String? {
        store.saveError ?? sketchStore.saveError
    }

    private var notes: some View {
        ScratchpadTextView(
            text: $store.text,
            placeholder: isPinned ? "type…" : "click to write",
            font: fontSetting.choice.resolved(size: Self.textSize),
            shouldFocus: isPinned,
            onEditingChange: { store.isEditing = $0 }
        )
    }

    private var sketchCanvas: some View {
        SketchCanvasView(
            drawing: sketchStore.drawing,
            ink: ink,
            onStrokeBegan: { sketchStore.isDrawing = true },
            onStrokeCommitted: { stroke in
                sketchStore.drawing.strokes.append(stroke)
                sketchStore.isDrawing = false
            }
        )
        // The controller flushes the text stores when the panel closes, but
        // the sketch store lives here in the view. Flushing as the canvas
        // leaves the tree covers both exits — switching back to text and the
        // panel collapsing — and the task holds the store, so a pending write
        // lands even after the panel content is torn down.
        .onDisappear {
            let sketchStore = sketchStore
            Task { await sketchStore.flush() }
        }
    }

    // MARK: - Corner controls

    /// The cluster in the notes' top-right corner: ink swatches and clear
    /// while sketching, then the sketch toggle and the font menu. Same rule
    /// as the media transport for every one of them: the notes text is the
    /// panel's only focusable control.
    private var cornerControls: some View {
        HStack(spacing: 8) {
            if mode == .sketch {
                inkPicker
                clearButton
            }
            if !isPopoutWindow {
                popOutButton
            }
            sketchToggle
            fontMenu
        }
    }

    /// Sends the notes into their own floating window, pinned above other
    /// windows. Only the panel host shows it — the window's way back is its
    /// close box. Plain and never focusable, like the rest of the cluster.
    private var popOutButton: some View {
        Button {
            popout.popOut()
        } label: {
            Image(systemName: "pin")
                .font(.system(size: 10, weight: .semibold))
                .frame(width: 20, height: 16)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .focusable(false)
        .foregroundStyle(.white.opacity(0.35))
        .help("Pin notes above other windows")
    }

    /// What the panel column shows while the notes are popped out: a quiet
    /// note and the way back.
    private var poppedOutNotice: some View {
        VStack(spacing: 6) {
            Image(systemName: "pin")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white.opacity(0.25))
            Text("notes are popped out")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.35))
            Button("bring back") {
                popout.returnToPanel()
            }
            .buttonStyle(.plain)
            .focusable(false)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.white.opacity(0.6))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
        .focusable(false)
        .foregroundStyle(.white.opacity(0.35))
        .help("Notes font")
    }

    /// Flips the column between typed notes and the sketch canvas. A plain
    /// never-focusable button, so toggling modes cannot disturb the caret;
    /// the icon brightens while the canvas is up.
    private var sketchToggle: some View {
        Button {
            mode = mode == .sketch ? .text : .sketch
        } label: {
            Image(systemName: "scribble")
                .font(.system(size: 10, weight: .semibold))
                .frame(width: 20, height: 16)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .focusable(false)
        .foregroundStyle(.white.opacity(mode == .sketch ? 0.8 : 0.35))
        .help(mode == .sketch ? "Back to text" : "Sketch")
    }

    /// The three inks as swatches; the chosen one shows at full strength.
    private var inkPicker: some View {
        HStack(spacing: 5) {
            ForEach(SketchInk.allCases) { candidate in
                Button {
                    ink = candidate
                } label: {
                    Circle()
                        .fill(candidate.swatchColor.opacity(ink == candidate ? 1 : 0.4))
                        .frame(width: 7, height: 7)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .focusable(false)
                .help("\(candidate.displayName) ink")
            }
        }
        .frame(height: 16)
    }

    private var clearButton: some View {
        Button {
            guard !sketchStore.drawing.isEmpty else { return }
            sketchStore.drawing = .empty
        } label: {
            Image(systemName: "trash")
                .font(.system(size: 9, weight: .semibold))
                .frame(width: 16, height: 16)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .focusable(false)
        .foregroundStyle(.white.opacity(0.35))
        .help("Clear sketch")
    }

    private func banner(_ message: String) -> some View {
        Label("Not saved: \(message)", systemImage: "exclamationmark.triangle.fill")
            .font(.system(size: 10))
            .foregroundStyle(.orange)
            .lineLimit(1)
    }
}
