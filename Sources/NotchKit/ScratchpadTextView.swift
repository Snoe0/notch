import AppKit
import SwiftUI

/// An `NSTextView` that draws its own placeholder.
///
/// SwiftUI's `TextEditor` is not used here because its internal text insets are
/// not exposed, so a placeholder drawn as a SwiftUI overlay cannot be aligned
/// to the caret — it always sits a few points off. Drawing the placeholder
/// inside the text view means it shares the exact text container as the real
/// text, so the two line up by construction rather than by guesswork.
final class PlaceholderTextView: NSTextView {
    var placeholder: String = "" {
        didSet { needsDisplay = true }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard string.isEmpty, !placeholder.isEmpty else { return }

        let attributes: [NSAttributedString.Key: Any] = [
            .font: font ?? NSFont.monospacedSystemFont(ofSize: 13, weight: .regular),
            .foregroundColor: NSColor.white.withAlphaComponent(0.35),
        ]
        // Exactly where the first glyph of real text would be laid out.
        let origin = NSPoint(
            x: textContainerInset.width + (textContainer?.lineFragmentPadding ?? 0),
            y: textContainerInset.height
        )
        placeholder.draw(at: origin, withAttributes: attributes)
    }
}

struct ScratchpadTextView: NSViewRepresentable {
    @Binding var text: String
    let placeholder: String
    let shouldFocus: Bool
    let onEditingChange: (Bool) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let textView = PlaceholderTextView()
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.isEditable = true
        textView.isSelectable = true
        textView.allowsUndo = true
        textView.drawsBackground = false
        textView.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        textView.textColor = .white
        textView.insertionPointColor = .white
        // Zero both so the placeholder origin above is simply (0, 0).
        textView.textContainerInset = .zero
        textView.textContainer?.lineFragmentPadding = 0
        textView.placeholder = placeholder

        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.minSize = .zero
        textView.maxSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.textContainer?.widthTracksTextView = true

        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = false
        scroll.hasHorizontalScroller = false
        scroll.autohidesScrollers = true
        scroll.documentView = textView
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let textView = scroll.documentView as? PlaceholderTextView else { return }
        context.coordinator.parent = self

        if textView.string != text {
            textView.string = text
        }
        textView.placeholder = placeholder

        if shouldFocus, textView.window?.firstResponder !== textView {
            textView.window?.makeFirstResponder(textView)
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: ScratchpadTextView

        init(_ parent: ScratchpadTextView) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
            textView.needsDisplay = true      // repaint so the placeholder clears
        }

        func textDidBeginEditing(_ notification: Notification) {
            parent.onEditingChange(true)
        }

        func textDidEndEditing(_ notification: Notification) {
            parent.onEditingChange(false)
        }
    }
}
