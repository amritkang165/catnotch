/// Which displays get a Notch. Displays are identified by CGDirectDisplayID.
public enum DisplaySelection: Hashable, Sendable {
    case all
    case primary
    case chosen(UInt32)

    /// From the saved setting: "all", "primary", or a display id. Unset or unreadable means primary.
    public init(setting: String?) {
        if setting == "all" { self = .all }
        else if let setting, let id = UInt32(setting) { self = .chosen(id) }
        else { self = .primary }
    }

    /// The displays to put a Notch on. A chosen display that is unplugged falls back to the primary.
    public func targets(available: [UInt32], primary: UInt32) -> [UInt32] {
        switch self {
        case .all: available
        case .primary: [primary]
        case .chosen(let id): [available.contains(id) ? id : primary]
        }
    }
}

extension DisplaySelection {
    /// The saved form, the inverse of `init(setting:)`.
    public var setting: String {
        switch self {
        case .all: "all"
        case .primary: "primary"
        case .chosen(let id): String(id)
        }
    }
}

extension StoreData {
    /// The display rule, saved under the same `selectedDisplayId` key the Electron app used, so the import carries it.
    public var displaySelection: DisplaySelection {
        get {
            if case .string(let s)? = settings["selectedDisplayId"] { DisplaySelection(setting: s) } else { .primary }
        }
        set { settings["selectedDisplayId"] = .string(newValue.setting) }
    }
}
