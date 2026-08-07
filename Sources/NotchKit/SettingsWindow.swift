import AppKit
import SwiftUI

/// Owns the settings window: one instance for the app's lifetime, shown from
/// the status-item menu. Unlike the notch panel this is an ordinary activating
/// window — settings are deliberate work, not hover UI — and closing it only
/// hides it, so the frame autosave keeps its place across opens and relaunches.
@MainActor
final class SettingsWindowController {
    private let settings: PanelSettings
    private let fontSetting: ScratchpadFontSetting
    private var window: NSWindow?

    private static let autosaveName = "Settings"

    init(settings: PanelSettings, fontSetting: ScratchpadFontSetting) {
        self.settings = settings
        self.fontSetting = fontSetting
    }

    func show() {
        let window = self.window ?? makeWindow()
        self.window = window
        window.makeKeyAndOrderFront(nil)
        // The click that opened the menu may have left another app active, and
        // only an active app's key window gets keystrokes.
        NSApp.activate()
    }

    /// Sized by its SwiftUI content — the form is fixed, so the window carries
    /// no resize handle and the autosave only remembers where it was put.
    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentViewController: NSHostingController(
                rootView: SettingsView(settings: settings, fontSetting: fontSetting)
            )
        )
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.title = "Notch Settings"
        window.isReleasedWhenClosed = false
        window.setFrameAutosaveName(Self.autosaveName)
        return window
    }
}

/// The settings form: which surfaces the panel shows, how they sit around the
/// notch, and the notes typeface. Plain native controls in a grouped form —
/// the system styles it for either appearance, so nothing here names a color.
struct SettingsView: View {
    @ObservedObject var settings: PanelSettings
    @ObservedObject var fontSetting: ScratchpadFontSetting

    var body: some View {
        Form {
            featureSection
            layoutSection
            notesSection
        }
        .formStyle(.grouped)
        .frame(width: 360)
        .fixedSize()
    }

    private var featureSection: some View {
        Section("Features") {
            Toggle("Media controls", isOn: $settings.showsMedia)
            Toggle("Pomodoro timer", isOn: $settings.showsPomodoro)
            Toggle("Todos", isOn: $settings.showsTodos)
            Toggle("Notes", isOn: $settings.showsNotes)
        }
    }

    /// Both choices are pickers over the two arrangements rather than "swap"
    /// switches, so the labels say what ends up where instead of asking the
    /// user to remember what the default was.
    private var layoutSection: some View {
        Section("Layout") {
            Picker("Left of the notch", selection: $settings.swapsFlanks) {
                Text("Media").tag(false)
                Text("Pomodoro").tag(true)
            }
            Picker("Left column", selection: $settings.swapsColumns) {
                Text("Todos").tag(false)
                Text("Notes").tag(true)
            }
        }
    }

    private var notesSection: some View {
        Section("Notes") {
            Picker("Font", selection: $fontSetting.choice) {
                ForEach(ScratchpadFont.allCases) { font in
                    Text(font.displayName).tag(font)
                }
            }
        }
    }
}
