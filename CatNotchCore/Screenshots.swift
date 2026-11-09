import Foundation

/// Where macOS saves screenshots, and which files in there are the latest.
public enum Screenshots {
    /// The folder set in `com.apple.screencapture` (`~` allowed), else the Desktop.
    public static func folder(location: String?, home: URL) -> URL {
        let set = location?.trimmingCharacters(in: .whitespaces) ?? ""
        if set.isEmpty { return home.appendingPathComponent("Desktop") }
        if set == "~" { return home }
        if set.hasPrefix("~/") { return home.appendingPathComponent(String(set.dropFirst(2))) }
        return URL(fileURLWithPath: set)
    }

    /// The `limit` newest PNG and JPEG files in `folder` that `isCapture` accepts, newest first.
    /// `isCapture` is asked newest first, for at most the 40 newest images (a Desktop can hold hundreds).
    public static func newest(in folder: URL, limit: Int, isCapture: (URL) -> Bool) -> [URL] {
        let keys: [URLResourceKey] = [.creationDateKey]
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: keys, options: .skipsHiddenFiles)) ?? []
        let images = files.filter { ["png", "jpg", "jpeg"].contains($0.pathExtension.lowercased()) }
            .map { ($0, (try? $0.resourceValues(forKeys: Set(keys)).creationDate) ?? .distantPast) }
            .sorted { $0.1 > $1.1 }
        var found: [URL] = []
        for (url, _) in images.prefix(40) where found.count < limit && isCapture(url) { found.append(url) }
        return found
    }
}
