import AppKit

/// The typefaces the notes can be set in: the system face plus its serif,
/// rounded, and monospaced designs. A small curated set instead of the full
/// font panel — every choice is resolved from the system font's own designs
/// (New York, SF Rounded, SF Mono), so each one is guaranteed present and
/// legible at note size on the dark panel.
enum ScratchpadFont: String, CaseIterable, Identifiable {
    case system
    case serif
    case rounded
    case mono

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system: "System"
        case .serif: "Serif"
        case .rounded: "Rounded"
        case .mono: "Mono"
        }
    }

    /// The concrete font at `size`. A design that cannot be resolved falls
    /// back to the plain system font rather than failing.
    func resolved(size: CGFloat) -> NSFont {
        let base = NSFont.systemFont(ofSize: size)
        guard
            let design,
            let descriptor = base.fontDescriptor.withDesign(design),
            let designed = NSFont(descriptor: descriptor, size: size)
        else { return base }
        return designed
    }

    private var design: NSFontDescriptor.SystemDesign? {
        switch self {
        case .system: nil
        case .serif: .serif
        case .rounded: .rounded
        case .mono: .monospaced
        }
    }
}

/// Remembers the chosen notes font across relaunches. UserDefaults rather
/// than a file beside the notes: the choice is a UI preference of this Mac,
/// not note content, so it stays out of `scratchpad.md` and out of the
/// store's save/reload machinery.
@MainActor
final class ScratchpadFontSetting: ObservableObject {
    @Published var choice: ScratchpadFont {
        didSet { defaults.set(choice.rawValue, forKey: Self.key) }
    }

    static let key = "scratchpadFont"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        choice = Self.storedChoice(in: defaults)
    }

    /// An unknown or missing stored value reads as the default, so a renamed
    /// case in a future version can never wedge the notes into no font.
    private static func storedChoice(in defaults: UserDefaults) -> ScratchpadFont {
        defaults.string(forKey: key).flatMap(ScratchpadFont.init(rawValue:)) ?? .system
    }
}
