import Foundation

/// How the Notch is filled. Saved under `notchStyle`, the Electron key, so the import carries it.
public enum NotchStyle: String, CaseIterable, Sendable {
    case black, transparent, glass

    /// Unset or unknown means black. `translucent` is the old Electron name for glass; `mica` (Windows) is black.
    public init(setting: String?) {
        self = switch setting {
        case "translucent": .glass
        default: setting.flatMap(NotchStyle.init(rawValue:)) ?? .black
        }
    }

    public var label: String { rawValue.capitalized }
}

/// The Catppuccin dark flavours. Saved under `notchFlavor`.
public enum Flavor: String, CaseIterable, Sendable {
    case mocha, macchiato, frappe

    public init(setting: String?) { self = setting.flatMap(Flavor.init(rawValue:)) ?? .mocha }

    public var label: String { self == .frappe ? "Frappé" : rawValue.capitalized }

    /// The flavour's base colour, 0xRRGGBB. It tints the transparent and glass styles.
    public var base: UInt32 {
        switch self {
        case .mocha: 0x1e1e2e
        case .macchiato: 0x24273a
        case .frappe: 0x303446
        }
    }
}

extension Flavor {
    /// The flavour's accent colours by name, in Electron's order, 0xRRGGBB. They colour the rim and the cat's coat.
    public var accents: [(name: String, hex: UInt32)] {
        switch self {
        case .mocha: [("Mauve", 0xcba6f7), ("Blue", 0x89b4fa), ("Sapphire", 0x74c7ec), ("Green", 0xa6e3a1), ("Peach", 0xfab387), ("Pink", 0xf5c2e7), ("Red", 0xf38ba8), ("Text", 0xcdd6f4)]
        case .macchiato: [("Mauve", 0xc6a0f6), ("Blue", 0x8aadf4), ("Sapphire", 0x7dc4e4), ("Green", 0xa6da95), ("Peach", 0xf5a97f), ("Pink", 0xf5bde6), ("Red", 0xed8796), ("Text", 0xcad3f5)]
        case .frappe: [("Mauve", 0xca9ee6), ("Blue", 0x8caaee), ("Sapphire", 0x85c1dc), ("Green", 0xa6d189), ("Peach", 0xef9f76), ("Pink", 0xf4b8e4), ("Red", 0xe78284), ("Text", 0xc6d0f5)]
        }
    }

    /// An accent by name; Mauve when the name is unknown.
    public func accent(named name: String) -> UInt32 { accents.first { $0.name == name }?.hex ?? mauve }
}

/// The colours the user chose over the flavour's: the Electron `notchColor`, `notchAccent` and `notchOpacity`.
public struct NotchTint: Equatable, Sendable {
    public static let defaultOpacity = 0.7
    /// A custom background for Transparent and Glass; nil means the flavour's base.
    public var fill: UInt32?
    /// The hairline along the Notch's sides and bottom; nil means none.
    public var rim: UInt32?
    public var opacity = defaultOpacity

    public init(fill: UInt32? = nil, rim: UInt32? = nil, opacity: Double = defaultOpacity) { (self.fill, self.rim, self.opacity) = (fill, rim, opacity) }
}

/// The places the open Notch can show. Only the switcher exists so far; each feature fills its page.
public enum NotchPage: String, CaseIterable, Sendable {
    case home, desk, calendar, reminders, files, claude

    public var label: String {
        switch self {
        case .home: "Home"
        case .desk: "Focus & tasks"
        case .calendar: "Calendar"
        case .reminders: "Reminders"
        case .files: "Files"
        case .claude: "Claude"
        }
    }

    /// An SF Symbol name.
    public var symbol: String {
        switch self {
        case .home: "square.grid.2x2"
        case .desk: "checklist"
        case .calendar: "calendar"
        case .reminders: "bell"
        case .files: "folder"
        case .claude: "terminal"
        }
    }
}

extension StoreData {
    public var notchStyle: NotchStyle {
        get { NotchStyle(setting: settings["notchStyle"]?.stringValue) }
        set { settings["notchStyle"] = .string(newValue.rawValue) }
    }

    public var notchFlavor: Flavor {
        get { Flavor(setting: settings["notchFlavor"]?.stringValue) }
        set { settings["notchFlavor"] = .string(newValue.rawValue) }
    }
}

extension StoreData {
    /// `#rrggbb` as Electron saves it. Nil clears the key.
    private func color(_ key: String) -> UInt32? { settings[key]?.stringValue.flatMap { UInt32($0.dropFirst(), radix: 16) } }
    private mutating func setColor(_ key: String, _ hex: UInt32?) { settings[key] = hex.map { .string("#" + String(format: "%06x", $0)) } }

    public var notchColor: UInt32? { get { color("notchColor") } set { setColor("notchColor", newValue) } }
    public var notchAccent: UInt32? { get { color("notchAccent") } set { setColor("notchAccent", newValue) } }

    public var notchOpacity: Double {
        get { if case .number(let n) = settings["notchOpacity"] { min(1, max(0.2, n)) } else { NotchTint.defaultOpacity } }
        set { settings["notchOpacity"] = .number(newValue) }
    }

    /// The Catppuccin cat's coat, an accent name. Nil is Mauve.
    public var catAccent: String? {
        get { settings["catAccent"]?.stringValue }
        set { settings["catAccent"] = newValue.map { .string($0) } }
    }

    public var notchTint: NotchTint { NotchTint(fill: notchColor, rim: notchAccent, opacity: notchOpacity) }
}

extension JSONValue {
    fileprivate var stringValue: String? { if case .string(let s) = self { s } else { nil } }
}

public enum WallClock {
    public struct Text: Equatable, Sendable {
        public var time: String
        public var meridiem: String
    }

    /// 12-hour time with a separate AM or PM: 13:05 is `1:05` `PM`. Not locale formatted, so it matches the Electron app.
    public static func text(_ date: Date, calendar: Calendar = .current) -> Text {
        let c = calendar.dateComponents([.hour, .minute], from: date)
        let h = c.hour ?? 0
        return Text(time: "\(h % 12 == 0 ? 12 : h % 12):\(String(format: "%02d", c.minute ?? 0))", meridiem: h < 12 ? "AM" : "PM")
    }
}
