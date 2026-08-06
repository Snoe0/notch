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
            .font: font ?? NSFont.systemFont(ofSize: 13),
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

/// Fires once each time a request goes from off to on, and re-arms when it
/// goes back off.
///
/// Focus in the panel is an edge, not a level: "the panel just became pinned"
/// is a reason to claim the caret, "the panel is still pinned" is not. Kept
/// out of the AppKit call below so the rule can be tested without a window.
struct FocusRequestEdge {
    private var wasRequested = false

    mutating func fires(on requested: Bool) -> Bool {
        defer { wasRequested = requested }
        return requested && !wasRequested
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
        textView.font = .systemFont(ofSize: 13)
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

        context.coordinator.claimFocusIfNewlyRequested(textView, shouldFocus: shouldFocus)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: ScratchpadTextView

        private var focusRequest = FocusRequestEdge()

        init(_ parent: ScratchpadTextView) {
            self.parent = parent
        }

        /// Takes the caret only as `shouldFocus` goes false → true.
        ///
        /// The panel becoming pinned is a reason to put the caret in the notes;
        /// a later update pass is not. Claiming on every pass — as this used to
        /// — snatched the caret back from the other field in the panel the
        /// moment anything re-rendered, which is every keystroke. Clicking back
        /// into this text view afterwards needs no help: `shouldFocus` stays
        /// true the whole time the panel is pinned, and AppKit routes the click
        /// to the text view itself.
        ///
        /// Even the edge yields, because the click that pins the panel can be
        /// the one that lands in the add field: that field becomes first
        /// responder while this pass is still pending.
        @MainActor
        func claimFocusIfNewlyRequested(_ textView: NSTextView, shouldFocus: Bool) {
            // Off-screen: leave the edge unconsumed and try again next pass.
            guard let window = textView.window else { return }
            guard focusRequest.fires(on: shouldFocus) else { return }
            guard !(window.firstResponder is NSText) else { return }
            window.makeFirstResponder(textView)
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
