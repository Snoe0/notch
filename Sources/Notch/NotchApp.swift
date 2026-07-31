import SwiftUI
import NotchKit

@main
struct NotchApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra("Notch", systemImage: "note.text") {
            MenuContent(revealNotes: { delegate.revealNotes() })
        }
    }
}

private struct MenuContent: View {
    let revealNotes: () -> Void
    @State private var launchAtLogin = LaunchAtLogin.isEnabled

    var body: some View {
        Button("Reveal Notes in Finder", action: revealNotes)
        Toggle("Launch at Login", isOn: $launchAtLogin)
            .onChange(of: launchAtLogin) { _, enabled in LaunchAtLogin.set(enabled) }
        Divider()
        Button("Quit Notch") { NSApplication.shared.terminate(nil) }
            .keyboardShortcut("q")
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: NotchController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        MainActor.assumeIsolated {
            let controller = NotchController()
            controller.start()
            self.controller = controller
        }
    }

    @MainActor
    func revealNotes() {
        controller?.revealNotes()
    }
}
