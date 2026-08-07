import Combine
import Foundation

/// Which host owns the notes column: the panel under the notch, or the small
/// floating window the pin button opens.
///
/// State only, so it is tested without a window. The window itself is managed
/// by `NotesPopoutWindowController`, and while the notes are popped out the
/// panel column shows a placeholder instead of a second editor — one live
/// text view per store, so two carets can never fight over it and two hosts
/// can never race their edits.
@MainActor
public final class NotesPopoutPresenter: ObservableObject {
    /// True while the floating window owns the notes.
    @Published public private(set) var isPoppedOut = false

    public init() {}

    /// The pin button in the notes corner sends the notes to the window.
    public func popOut() {
        guard !isPoppedOut else { return }
        isPoppedOut = true
    }

    /// The placeholder's button — or the window's close box, which reports
    /// through the same path — brings the notes back to the panel.
    public func returnToPanel() {
        guard isPoppedOut else { return }
        isPoppedOut = false
    }
}
