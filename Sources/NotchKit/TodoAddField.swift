import AppKit
import SwiftUI

/// An `NSTextField` that reports focus rather than typing.
///
/// `controlTextDidBeginEditing` does not fire until the first keystroke, but
/// the field owns the caret from the click that focused it — and that is the
/// moment external reloads have to stop. Reporting from `becomeFirstResponder`
/// makes "editing" mean "holds the caret", which is what the store needs.
private final class FocusReportingTextField: NSTextField {
    var onEditingChange: (Bool) -> Void = { _ in }

    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        if accepted { onEditingChange(true) }
        return accepted
    }

    /// The panel tears its content down while this field may still be editing,
    /// and losing the window does not reliably come with an editing-ended
    /// notification. Without this the store would stay suppressed for the rest
    /// of the app's life and never pick up an external edit again.
    override func viewWillMove(toWindow newWindow: NSWindow?) {
        super.viewWillMove(toWindow: newWindow)
        if newWindow == nil, currentEditor() != nil { onEditingChange(false) }
    }
}

/// The field that appends a todo.
///
/// AppKit rather than SwiftUI's `TextField` for the same reason the notes
/// column wraps an `NSTextView`: inside a borderless `.nonactivatingPanel`,
/// `@FocusState` does not reliably win the caret — a click lands, the panel
/// re-renders, and the field never ends up editing. The draft lives in the
/// `NSTextField` itself: nothing else reads it, and it dies with the panel
/// exactly as `@State` would have.
struct TodoAddField: NSViewRepresentable {
    let placeholder: String
    let onCommit: (String) -> Void
    let onEditingChange: (Bool) -> Void

    /// Matches the rest of the checklist column.
    private static let font = NSFont.systemFont(ofSize: 12)

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSTextField {
        let field = FocusReportingTextField()
        field.delegate = context.coordinator
        field.onEditingChange = { context.coordinator.parent.onEditingChange($0) }

        field.isBordered = false
        field.isBezeled = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.usesSingleLineMode = true
        field.font = Self.font
        field.textColor = .white
        field.placeholderAttributedString = Self.placeholderString(placeholder)
        // The panel is always black, whatever the Mac is set to. The field
        // editor is shared by the window and takes its caret and selection
        // colours from the appearance it is edited in, so on a light-mode Mac
        // the caret would be black on black — the same problem the notes
        // column solves by setting `insertionPointColor`.
        field.appearance = NSAppearance(named: .darkAqua)
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        context.coordinator.parent = self
        field.placeholderAttributedString = Self.placeholderString(placeholder)
    }

    /// Fill the column and keep the field's own single-line height; left to
    /// itself the field would size to its text and shrink as it is emptied.
    func sizeThatFits(
        _ proposal: ProposedViewSize,
        nsView: NSTextField,
        context: Context
    ) -> CGSize? {
        CGSize(
            width: proposal.width ?? nsView.intrinsicContentSize.width,
            height: nsView.intrinsicContentSize.height
        )
    }

    /// `NSTextField`'s own prompt colour is not legible on black.
    private static func placeholderString(_ text: String) -> NSAttributedString {
        NSAttributedString(
            string: text,
            attributes: [
                .font: font,
                .foregroundColor: NSColor.white.withAlphaComponent(0.35),
            ]
        )
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: TodoAddField

        init(_ parent: TodoAddField) {
            self.parent = parent
        }

        /// Return appends and clears in place. Handling the command here rather
        /// than letting the field send its action means editing never ends, so
        /// the caret stays put and a run of todos can be typed one after
        /// another.
        func control(
            _ control: NSControl,
            textView: NSTextView,
            doCommandBy selector: Selector
        ) -> Bool {
            guard selector == #selector(NSResponder.insertNewline(_:)) else { return false }
            let draft = textView.string
            // The field editor holds the live text while editing; the cell
            // holds it once editing ends. Both have to be emptied.
            textView.string = ""
            control.stringValue = ""
            parent.onCommit(draft)     // blank drafts are dropped by the store
            return true
        }

        func controlTextDidEndEditing(_ notification: Notification) {
            parent.onEditingChange(false)
        }
    }
}
