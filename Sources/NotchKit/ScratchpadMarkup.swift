import Foundation

/// An inline style the scratchpad can toggle, persisted as plain markers
/// inside `scratchpad.md`: `==text==` renders as a highlight and
/// `<u>text</u>` as an underline. Keeping the markers in the string means the
/// file stays ordinary markdown and the store's debounced saves, external
/// reloads, and relaunch behavior never have to know about styling.
enum ScratchpadStyle: CaseIterable {
    case underline
    case highlight

    var openMarker: String {
        switch self {
        case .underline: "<u>"
        case .highlight: "=="
        }
    }

    var closeMarker: String {
        switch self {
        case .underline: "</u>"
        case .highlight: "=="
        }
    }

    /// Spans never cross a line break, so a stray marker cannot restyle the
    /// rest of the document.
    fileprivate var pattern: String {
        switch self {
        case .underline: "<u>([^\n]*?)</u>"
        case .highlight: "==([^\n]*?)=="
        }
    }
}

/// One marked-up run of text. Ranges are UTF-16, ready for `NSTextStorage`.
struct MarkupSpan: Equatable {
    let style: ScratchpadStyle
    /// The whole span including its markers.
    let fullRange: NSRange
    /// Just the styled text between the markers.
    let innerRange: NSRange
}

/// One URL found in the text. The range is UTF-16.
struct LinkSpan: Equatable {
    let range: NSRange
    let url: URL
}

/// A single text replacement that applies or removes a style, expressed so
/// the view can route it through `shouldChangeText` and keep undo working.
struct MarkupEdit: Equatable {
    let replacementRange: NSRange
    let replacement: String
    let selectionAfter: NSRange
}

/// Pure string logic for the scratchpad's markup: parsing spans, finding
/// links, and computing the edit that toggles a style. No AppKit, so all of
/// it runs headless under `swift test`.
enum ScratchpadMarkup {
    static func markupSpans(in text: String) -> [MarkupSpan] {
        ScratchpadStyle.allCases.flatMap { spans(of: $0, in: text) }
    }

    static func linkSpans(in text: String) -> [LinkSpan] {
        let types = NSTextCheckingResult.CheckingType.link.rawValue
        guard let detector = try? NSDataDetector(types: types) else { return [] }
        return detector.matches(in: text, range: wholeRange(of: text)).compactMap { match in
            match.url.map { LinkSpan(range: match.range, url: $0) }
        }
    }

    /// The edit that toggles `style` for `selection`: unwraps the enclosing
    /// span when the selection already sits in one, wraps the selection in
    /// markers otherwise. Nil when the selection is out of bounds.
    static func toggle(
        _ style: ScratchpadStyle,
        in text: String,
        selection: NSRange
    ) -> MarkupEdit? {
        guard isValid(selection, in: text) else { return nil }
        if let span = enclosingSpan(of: style, around: selection, in: text) {
            return unwrap(span, in: text)
        }
        return wrap(style, around: selection, in: text)
    }

    // MARK: - Parsing

    private static func spans(of style: ScratchpadStyle, in text: String) -> [MarkupSpan] {
        guard let regex = try? NSRegularExpression(pattern: style.pattern) else { return [] }
        return regex.matches(in: text, range: wholeRange(of: text)).map { match in
            MarkupSpan(style: style, fullRange: match.range, innerRange: match.range(at: 1))
        }
    }

    private static func wholeRange(of text: String) -> NSRange {
        NSRange(location: 0, length: (text as NSString).length)
    }

    private static func isValid(_ selection: NSRange, in text: String) -> Bool {
        selection.location != NSNotFound
            && selection.location >= 0
            && NSMaxRange(selection) <= (text as NSString).length
    }

    // MARK: - Toggling

    private static func enclosingSpan(
        of style: ScratchpadStyle,
        around selection: NSRange,
        in text: String
    ) -> MarkupSpan? {
        spans(of: style, in: text).first { span in
            span.fullRange.location <= selection.location
                && NSMaxRange(selection) <= NSMaxRange(span.fullRange)
        }
    }

    private static func unwrap(_ span: MarkupSpan, in text: String) -> MarkupEdit {
        let inner = (text as NSString).substring(with: span.innerRange)
        return MarkupEdit(
            replacementRange: span.fullRange,
            replacement: inner,
            selectionAfter: NSRange(location: span.fullRange.location, length: span.innerRange.length)
        )
    }

    private static func wrap(
        _ style: ScratchpadStyle,
        around selection: NSRange,
        in text: String
    ) -> MarkupEdit {
        let selected = (text as NSString).substring(with: selection)
        return MarkupEdit(
            replacementRange: selection,
            replacement: style.openMarker + selected + style.closeMarker,
            // The original text stays selected (or, for an empty selection,
            // the caret lands between the markers ready to type).
            selectionAfter: NSRange(
                location: selection.location + style.openMarker.utf16.count,
                length: selection.length
            )
        )
    }
}
