import Testing
import Combine
@testable import NotchKit

@Test @MainActor func notesStartInThePanel() {
    #expect(NotesPopoutPresenter().isPoppedOut == false)
}

@Test @MainActor func poppingOutMovesTheNotesToTheWindow() {
    let presenter = NotesPopoutPresenter()

    presenter.popOut()

    #expect(presenter.isPoppedOut)
}

@Test @MainActor func returningBringsTheNotesBack() {
    let presenter = NotesPopoutPresenter()
    presenter.popOut()

    presenter.returnToPanel()

    #expect(presenter.isPoppedOut == false)
}

/// The controller shows the window and flushes the store on every publish,
/// so a repeated pop-out must stay silent.
@Test @MainActor func repeatedPopOutPublishesOnce() {
    let presenter = NotesPopoutPresenter()
    var publishes = 0
    let subscription = presenter.objectWillChange.sink { publishes += 1 }

    presenter.popOut()
    presenter.popOut()

    withExtendedLifetime(subscription) {}
    #expect(publishes == 1)
}

/// The window's close box reports through `returnToPanel` even when the
/// controller already hid the window — the echo must be a no-op.
@Test @MainActor func returningWhileAlreadyInThePanelPublishesNothing() {
    let presenter = NotesPopoutPresenter()
    var publishes = 0
    let subscription = presenter.objectWillChange.sink { publishes += 1 }

    presenter.returnToPanel()

    withExtendedLifetime(subscription) {}
    #expect(publishes == 0)
}
