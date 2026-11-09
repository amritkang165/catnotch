import Foundation

/// A file the app keeps: where it was, and a bookmark that follows it if it moves.
/// Plain bookmarks, not security scoped: the app is unsandboxed, so they already find a moved file.
public struct FileRef: Codable, Equatable, Sendable, ExpressibleByStringLiteral {
    public var path: String
    public var bookmark: Data?

    public init(path: String, bookmark: Data?) { self.path = path; self.bookmark = bookmark }
    public init(url: URL) { self.init(path: url.path, bookmark: try? url.bookmarkData()) }
    public init(stringLiteral path: String) { self.init(path: path, bookmark: nil) }

    /// Old stores keep a bare path string.
    public init(from decoder: Decoder) throws {
        if let path = try? decoder.singleValueContainer().decode(String.self) { self.init(path: path, bookmark: nil); return }
        let c = try decoder.container(keyedBy: Key.self)
        self.init(path: try c.decode(String.self, forKey: .path), bookmark: try c.decodeIfPresent(Data.self, forKey: .bookmark))
    }

    private enum Key: String, CodingKey { case path, bookmark }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Key.self)
        try c.encode(path, forKey: .path)
        try c.encodeIfPresent(bookmark, forKey: .bookmark)
    }

    public struct Found: Equatable, Sendable {
        public var url: URL
        /// The bookmark should be made again (macOS says it is out of date).
        public var stale: Bool
    }

    /// Where the file is now: the bookmark's answer if it resolves, else the saved path. Nil when the file is gone.
    /// A file in the Trash counts as gone.
    public func resolve() -> Found? {
        let fm = FileManager.default
        if let bookmark {
            var stale = false
            if let url = try? URL(resolvingBookmarkData: bookmark, options: [.withoutUI, .withoutMounting], relativeTo: nil, bookmarkDataIsStale: &stale),
               fm.fileExists(atPath: url.path), !url.path.contains("/.Trash/") {
                return Found(url: url, stale: stale)
            }
        }
        return fm.fileExists(atPath: path) && !path.contains("/.Trash/") ? Found(url: URL(fileURLWithPath: path), stale: false) : nil
    }

    /// The file's current place, or its saved one when it cannot be found.
    public var url: URL? { resolve()?.url }
}

extension StoreData {
    /// Puts files at the end of the shelf. One already there (by path) is not added again.
    public mutating func addToShelf(_ urls: [URL]) {
        for url in urls where !shelf.contains(where: { $0.path == url.path }) { shelf.append(FileRef(url: url)) }
    }

    public mutating func removeFromShelf(path: String) { shelf.removeAll { $0.path == path } }

    public mutating func clearShelf() { shelf.removeAll() }

    /// Follows moved files (the path becomes the new one) and bookmarks the ones that have none, such as paths
    /// from the old store. A file that cannot be found stays, so it comes back if the disk does.
    public mutating func refreshShelf() {
        for i in shelf.indices {
            guard let found = shelf[i].resolve() else { continue }
            if found.url.path != shelf[i].path || found.stale || shelf[i].bookmark == nil { shelf[i] = FileRef(url: found.url) }
        }
    }
}

extension CatNotchStore {
    public func addToShelf(_ urls: [URL]) { update { $0.addToShelf(urls) } }
    public func removeFromShelf(path: String) { update { $0.removeFromShelf(path: path) } }
    public func clearShelf() { update { $0.clearShelf() } }
    public func refreshShelf() { update { $0.refreshShelf() } }
    public func setPhoto(_ url: URL?) { update { $0.photo = url.map(FileRef.init(url:)) } }
}
