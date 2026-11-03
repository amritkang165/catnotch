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

/// The places the open Notch can show. Only the switcher exists so far; each feature fills its page.
public enum NotchPage: String, CaseIterable, Sendable {
    case home, desk, files

    public var label: String {
        switch self {
        case .home: "Home"
        case .desk: "Focus & tasks"
        case .files: "Files"
        }
    }

    /// An SF Symbol name.
    public var symbol: String {
        switch self {
        case .home: "square.grid.2x2"
        case .desk: "checklist"
        case .files: "folder"
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
