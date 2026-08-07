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

    /// Cmd-U / Cmd-Shift-H land here: the panel has no Format menu, so the
    /// key equivalents are handled in the view itself.
    var onToggleStyle: ((ScratchpadStyle) -> Void)?

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if let style = formattingStyle(for: event), let onToggleStyle {
            onToggleStyle(style)
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    private func formattingStyle(for event: NSEvent) -> ScratchpadStyle? {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let key = event.charactersIgnoringModifiers?.lowercased()
        if modifiers == .command, key == "u" { return .underline }
        if modifiers == [.command, .shift], key == "h" { return .highlight }
        return nil
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

/// Colors for the markup layer, all chosen against the panel's dark
/// background. The highlight is a translucent yellow rather than a solid
/// highlighter fill: at 0.3 opacity over the dark panel it reads as a dim
/// amber band, so the white text on top keeps roughly a 10:1 contrast ratio
/// instead of vanishing into a bright field.
enum ScratchpadPalette {
    static let text = NSColor.white
    static let marker = NSColor.white.withAlphaComponent(0.3)
    static let highlight = NSColor.systemYellow.withAlphaComponent(0.3)
    static let link = NSColor(srgbRed: 0.45, green: 0.72, blue: 1.0, alpha: 1.0)
}

struct ScratchpadTextView: NSViewRepresentable {
    @Binding var text: String
    let placeholder: String
    let font: NSFont
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
        textView.font = font
        textView.textColor = .white
        textView.insertionPointColor = .white
        // Zero both so the placeholder origin above is simply (0, 0).
        textView.textContainerInset = .zero
        textView.textContainer?.lineFragmentPadding = 0
        textView.placeholder = placeholder
        textView.linkTextAttributes = [
            .foregroundColor: ScratchpadPalette.link,
            .underlineStyle: NSUnderlineStyle.single.rawValue,
            .cursor: NSCursor.pointingHand,
        ]
        textView.onToggleStyle = { [weak textView] style in
            guard let textView else { return }
            context.coordinator.toggle(style, in: textView)
        }

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

        // A font switch restyles through the same markup pass as an edit, so
        // the new face lands on existing text together with its highlights,
        // underlines, and links rather than through a second attribute path.
        if textView.font != font {
            textView.font = font
            context.coordinator.applyMarkup(to: textView)
        }
        if textView.string != text {
            textView.string = text
            context.coordinator.applyMarkup(to: textView)
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

        /// Applies the markup edit through `shouldChangeText`/`didChangeText`
        /// so the toggle participates in undo like any typed edit.
        @MainActor
        func toggle(_ style: ScratchpadStyle, in textView: NSTextView) {
            let selection = textView.selectedRange()
            guard
                let edit = ScratchpadMarkup.toggle(style, in: textView.string, selection: selection),
                textView.shouldChangeText(in: edit.replacementRange, replacementString: edit.replacement)
            else { return }
            textView.textStorage?.replaceCharacters(in: edit.replacementRange, with: edit.replacement)
            textView.didChangeText()
            textView.setSelectedRange(edit.selectionAfter)
        }

        /// Re-derives every visual attribute from the plain text: highlight
        /// and underline spans from their markers, dimmed markers, and
        /// clickable links. Attributes are display-only — the persisted value
        /// is always just `textView.string`.
        @MainActor
        func applyMarkup(to textView: NSTextView) {
            // Never restyle mid-IME-composition; it would fight the input method.
            guard !textView.hasMarkedText(), let storage = textView.textStorage else { return }
            storage.beginEditing()
            resetAttributes(of: storage, font: textView.font)
            for span in ScratchpadMarkup.markupSpans(in: storage.string) {
                apply(span, to: storage)
            }
            for link in ScratchpadMarkup.linkSpans(in: storage.string) {
                storage.addAttribute(.link, value: link.url, range: link.range)
            }
            storage.endEditing()
            textView.typingAttributes = [
                .font: textView.font ?? NSFont.systemFont(ofSize: 13),
                .foregroundColor: ScratchpadPalette.text,
            ]
        }

        private func resetAttributes(of storage: NSTextStorage, font: NSFont?) {
            let whole = NSRange(location: 0, length: storage.length)
            storage.removeAttribute(.backgroundColor, range: whole)
            storage.removeAttribute(.underlineStyle, range: whole)
            storage.removeAttribute(.link, range: whole)
            storage.addAttribute(.foregroundColor, value: ScratchpadPalette.text, range: whole)
            storage.addAttribute(.font, value: font ?? NSFont.systemFont(ofSize: 13), range: whole)
        }

        private func apply(_ span: MarkupSpan, to storage: NSTextStorage) {
            switch span.style {
            case .highlight:
                storage.addAttribute(.backgroundColor, value: ScratchpadPalette.highlight, range: span.innerRange)
            case .underline:
                storage.addAttribute(
                    .underlineStyle,
                    value: NSUnderlineStyle.single.rawValue,
                    range: span.innerRange
                )
            }
            for marker in markerRanges(of: span) {
                storage.addAttribute(.foregroundColor, value: ScratchpadPalette.marker, range: marker)
            }
        }

        private func markerRanges(of span: MarkupSpan) -> [NSRange] {
            [
                NSRange(
                    location: span.fullRange.location,
                    length: span.innerRange.location - span.fullRange.location
                ),
                NSRange(
                    location: NSMaxRange(span.innerRange),
                    length: NSMaxRange(span.fullRange) - NSMaxRange(span.innerRange)
                ),
            ]
        }

        /// Opens links directly: the panel is non-activating, so routing
        /// through the default handler is not left to chance.
        func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
            guard let url = url(from: link) else { return false }
            NSWorkspace.shared.open(url)
            return true
        }

        private func url(from link: Any) -> URL? {
            (link as? URL) ?? (link as? String).flatMap(URL.init(string:))
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
            applyMarkup(to: textView)
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
