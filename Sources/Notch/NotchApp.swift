import SwiftUI

@main
struct NotchApp: App {
    var body: some Scene {
        MenuBarExtra("Notch", systemImage: "note.text") {
            Button("Quit Notch") { NSApplication.shared.terminate(nil) }
                .keyboardShortcut("q")
        }
    }
}
