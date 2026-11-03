import Foundation

/// Any JSON value. Settings are kept as these so the import loses nothing and later features read typed keys.
public enum JSONValue: Codable, Equatable, Sendable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let v = try? c.decode(Bool.self) { self = .bool(v) }
        else if let v = try? c.decode(Double.self) { self = .number(v) }
        else if let v = try? c.decode(String.self) { self = .string(v) }
        else if let v = try? c.decode([JSONValue].self) { self = .array(v) }
        else { self = .object(try c.decode([String: JSONValue].self)) }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null: try c.encodeNil()
        case .bool(let v): try c.encode(v)
        case .number(let v): try c.encode(v)
        case .string(let v): try c.encode(v)
        case .array(let v): try c.encode(v)
        case .object(let v): try c.encode(v)
        }
    }
}

public struct StoreTask: Codable, Equatable, Sendable {
    public var id: String
    public var label: String
    public var done: Bool
    /// A local day, YYYY-MM-DD.
    public var due: String?

    public init(id: String, label: String, done: Bool, due: String?) {
        self.id = id; self.label = label; self.done = done; self.due = due
    }
}

/// One finished focus session.
public struct FocusSession: Codable, Equatable, Sendable {
    /// When it ended, ms since the epoch.
    public var at: Double
    public var minutes: Double

    public init(at: Double, minutes: Double) { self.at = at; self.minutes = minutes }
}

public struct StoreData: Codable, Equatable, Sendable {
    public var tasks: [StoreTask] = []
    public var focusLog: [FocusSession] = []
    /// File paths on the shelf.
    public var shelf: [String] = []
    public var settings: [String: JSONValue] = [:]

    public init() {}

    /// Missing keys take their defaults, so a field added in a later version never makes an older file unreadable.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        tasks = try c.decodeIfPresent([StoreTask].self, forKey: .tasks) ?? []
        focusLog = try c.decodeIfPresent([FocusSession].self, forKey: .focusLog) ?? []
        shelf = try c.decodeIfPresent([String].self, forKey: .shelf) ?? []
        settings = try c.decodeIfPresent([String: JSONValue].self, forKey: .settings) ?? [:]
    }

    /// Reads what an old DeskNotch store holds. A field that is missing or the wrong shape comes out empty.
    init(legacy data: Data) throws {
        struct Old: Decodable {
            var todos: [StoreTask]?, focusLog: [FocusSession]?, shelf: [String]?, settings: [String: JSONValue]?
            enum Key: String, CodingKey { case todos, focusLog, shelf, settings }
            init(from decoder: Decoder) throws {
                let c = try decoder.container(keyedBy: Key.self)
                todos = try? c.decode([StoreTask].self, forKey: .todos)
                focusLog = try? c.decode([FocusSession].self, forKey: .focusLog)
                shelf = try? c.decode([String].self, forKey: .shelf)
                settings = try? c.decode([String: JSONValue].self, forKey: .settings)
            }
        }
        let old = try JSONDecoder().decode(Old.self, from: data)
        tasks = old.todos ?? []
        focusLog = old.focusLog ?? []
        shelf = old.shelf ?? []
        settings = old.settings ?? [:]
    }
}

/// The app's saved state: `catnotch-store.json` in the CatNotch support folder.
///
/// One instance is shared by the Notch on every display, so a change made through
/// `update` reaches every observer. Use it from the main actor.
public final class CatNotchStore {
    public private(set) var data: StoreData
    private let file: URL
    private var observers: [UUID: (StoreData) -> Void] = [:]

    /// `legacyDirectory` is the old DeskNotch folder. Its store is imported once, when this store's file does
    /// not exist yet, and never written to.
    public init(directory: URL, legacyDirectory: URL) {
        file = directory.appendingPathComponent("catnotch-store.json")
        if FileManager.default.fileExists(atPath: file.path) {
            // An unreadable file starts clean rather than re-importing over the user's newer data,
            // and is kept aside so the next save does not destroy it.
            if let saved = try? Data(contentsOf: file), let loaded = try? JSONDecoder().decode(StoreData.self, from: saved) {
                data = loaded
            } else {
                data = StoreData()
                let aside = directory.appendingPathComponent("catnotch-store.unreadable.json")
                try? FileManager.default.removeItem(at: aside)
                try? FileManager.default.moveItem(at: file, to: aside)
            }
        } else if let old = try? Data(contentsOf: legacyDirectory.appendingPathComponent("desknotch-store.json")),
                  let imported = try? StoreData(legacy: old) {
            data = imported
            save()
        } else {
            data = StoreData()
        }
    }

    /// The store in `~/Library/Application Support/CatNotch`, importing from `DeskNotch` beside it.
    public static func standard() -> CatNotchStore {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return CatNotchStore(directory: support.appendingPathComponent("CatNotch"),
                             legacyDirectory: support.appendingPathComponent("DeskNotch"))
    }

    /// Changes the data, saves it and tells every observer. A change that leaves it as it was does nothing.
    public func update(_ change: (inout StoreData) -> Void) {
        var next = data
        change(&next)
        guard next != data else { return }
        data = next
        save()
        for notify in observers.values { notify(next) }
    }

    /// Calls `handler` after every change. Returns the function that stops it.
    public func observe(_ handler: @escaping (StoreData) -> Void) -> () -> Void {
        let id = UUID()
        observers[id] = handler
        return { [weak self] in self?.observers[id] = nil }
    }

    // Synchronous and atomic: the file is tiny, and a half-written task list is worse than a few milliseconds.
    private func save() {
        do {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(data).write(to: file, options: .atomic)
        } catch {
            print("[store] write failed:", error)
        }
    }
}
