import Foundation

/// The Mac's battery. `supported` is false on a desktop Mac, which turns the tile off.
public struct BatteryState: Equatable, Sendable {
    public var level: Double
    public var charging: Bool
    public var supported: Bool

    public init(level: Double, charging: Bool, supported: Bool) {
        self.level = level; self.charging = charging; self.supported = supported
    }

    public static let none = BatteryState(level: 1, charging: true, supported: false)

    /// `pmset -g batt` output: "-InternalBattery-0 (id=1)\t80%; charging; 1:02 remaining". No such line is a desktop Mac.
    public init(pmset output: String) {
        guard let match = output.firstMatch(of: /(\d+)%;\s*([^;]+)/) else { self = .none; return }
        self.init(level: min(1, Double(match.1)! / 100), charging: !match.2.trimmingCharacters(in: .whitespaces).hasPrefix("discharging"), supported: true)
    }

    /// Colour only when it means something: a low charge that is not being topped up.
    public var isLow: Bool { !charging && level <= 0.2 }
}

/// Headphones that just connected, from the audio output list.
public enum Headphones {
    /// Outputs that are worn: Bluetooth headsets name themselves this way.
    public static func isWorn(_ label: String) -> Bool { label.contains(/(?i)headphone|headset|airpods|buds|earphone|earbud|hands-free|wh-|wf-/) }

    /// "Headphones (WH-1000XM4)" is "WH-1000XM4": the model, not the role.
    public static func name(of label: String) -> String {
        guard let inner = label.firstMatch(of: /\(([^)]+)\)/)?.1 else { return label }
        let model = inner.replacing(/(?i)\s*Hands-Free.*$/, with: "").trimmingCharacters(in: .whitespaces)
        return model.isEmpty ? label : model
    }

    /// The worn output in `now` that was not in `before` (id to name). One Bluetooth headset can list as two outputs at once;
    /// the caller shows one moment for the first.
    public static func arrival(before: [String: String], now: [String: String]) -> String? {
        now.filter { before[$0.key] == nil && isWorn($0.value) }.values.sorted().first.map(name(of:))
    }
}

/// The apps used most, by Spotlight's launch count.
public enum TopApps {
    /// Paths by launch count, highest first. Never-launched apps and `excluding` (this app) are left out; ties go by path.
    public static func rank(_ counts: [String: Int], excluding: String?, limit: Int) -> [String] {
        counts.filter { $0.value > 0 && $0.key != excluding }
            .sorted { ($0.value, $1.key) > ($1.value, $0.key) }
            .prefix(limit).map(\.key)
    }

    /// `mdls -raw -nullMarker 0` prints one NUL separated value per path, in the order asked. Unreadable is 0.
    public static func counts(paths: [String], mdls output: String) -> [String: Int] {
        let values = output.split(separator: "\0", omittingEmptySubsequences: false)
        return Dictionary(paths.enumerated().map { ($1, values.indices.contains($0) ? Int(values[$0]) ?? 0 : 0) }, uniquingKeysWith: max) // a path listed twice (a symlinked folder) must not trap
    }
}

public enum Wifi {
    /// CoreWLAN's RSSI as a percent in steps of 20, so a drifting reading is not news.
    public static func signal(rssi: Int) -> Int { min(100, max(0, (rssi + 100) * 2)) / 20 * 20 }
}

/// A connected Bluetooth device. `battery` is a percent, nil for a device that does not report one.
public struct BluetoothDevice: Equatable, Sendable, Identifiable {
    public var name: String
    public var battery: Int?
    public var id: String { name }

    public init(name: String, battery: Int?) { self.name = name; self.battery = battery }

    /// The connected devices in `system_profiler SPBluetoothDataType -json`. Earbuds report a side each: the lower one counts.
    /// Anything unexpected is no devices, which turns the tile off.
    public static func connected(profiler json: Data) -> [BluetoothDevice] {
        guard let root = (try? JSONSerialization.jsonObject(with: json)) as? [String: Any],
              let first = (root["SPBluetoothDataType"] as? [[String: Any]])?.first,
              let connected = first["device_connected"] as? [[String: Any]] else { return [] }
        func percent(_ value: Any?) -> Int? { (value as? String).flatMap { Int($0.trimmingCharacters(in: CharacterSet(charactersIn: "% "))) } }
        return connected.compactMap { entry in
            guard let name = entry.keys.first, let info = entry[name] as? [String: Any] else { return nil }
            let sides = [percent(info["device_batteryLevelLeft"]), percent(info["device_batteryLevelRight"])].compactMap { $0 }
            return BluetoothDevice(name: name, battery: percent(info["device_batteryLevelMain"]) ?? sides.min())
        }
    }
}
