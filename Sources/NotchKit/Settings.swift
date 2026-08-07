import Foundation

/// Which of the panel's surfaces are on, and how they are arranged around the
/// notch. Everything defaults to the layout the app shipped with — all four
/// surfaces shown, media leading and todos leading — so an untouched install
/// looks exactly as before.
///
/// UserDefaults for the same reason as `ScratchpadFontSetting`: these are UI
/// preferences of this Mac, not content, so they stay out of the note files
/// and their save machinery. Every change is applied live by whoever observes
/// the published properties — nothing here reaches into the views.
@MainActor
final class PanelSettings: ObservableObject {

    // MARK: - Features

    /// The media strip while open and the now-playing chip while collapsed.
    /// One switch for both: the chip only ever stands in for the strip.
    @Published var showsMedia: Bool {
        didSet { defaults.set(showsMedia, forKey: Keys.showsMedia) }
    }

    /// The pomodoro strip while open and the countdown chip while collapsed.
    @Published var showsPomodoro: Bool {
        didSet { defaults.set(showsPomodoro, forKey: Keys.showsPomodoro) }
    }

    @Published var showsTodos: Bool {
        didSet { defaults.set(showsTodos, forKey: Keys.showsTodos) }
    }

    @Published var showsNotes: Bool {
        didSet { defaults.set(showsNotes, forKey: Keys.showsNotes) }
    }

    // MARK: - Layout

    /// Notes on the left column and todos on the right, instead of the
    /// shipped arrangement.
    @Published var swapsColumns: Bool {
        didSet { defaults.set(swapsColumns, forKey: Keys.swapsColumns) }
    }

    /// Pomodoro on the notch's leading flank and media on the trailing one,
    /// instead of the shipped arrangement. Covers strips and chips alike —
    /// a chip always emerges on the same side as its strip.
    @Published var swapsFlanks: Bool {
        didSet { defaults.set(swapsFlanks, forKey: Keys.swapsFlanks) }
    }

    enum Keys {
        static let showsMedia = "showsMedia"
        static let showsPomodoro = "showsPomodoro"
        static let showsTodos = "showsTodos"
        static let showsNotes = "showsNotes"
        static let swapsColumns = "swapsColumns"
        static let swapsFlanks = "swapsFlanks"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        showsMedia = Self.stored(Keys.showsMedia, in: defaults, or: true)
        showsPomodoro = Self.stored(Keys.showsPomodoro, in: defaults, or: true)
        showsTodos = Self.stored(Keys.showsTodos, in: defaults, or: true)
        showsNotes = Self.stored(Keys.showsNotes, in: defaults, or: true)
        swapsColumns = Self.stored(Keys.swapsColumns, in: defaults, or: false)
        swapsFlanks = Self.stored(Keys.swapsFlanks, in: defaults, or: false)
    }

    /// `bool(forKey:)` cannot tell "never set" from `false`, and the feature
    /// switches default to `true` — so absence (or garbage) must read as the
    /// per-setting default rather than as `false`.
    private static func stored(_ key: String, in defaults: UserDefaults, or fallback: Bool) -> Bool {
        defaults.object(forKey: key) as? Bool ?? fallback
    }
}
