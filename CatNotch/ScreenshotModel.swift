import CoreServices
import Foundation
import Observation
import CatNotchCore

/// The newest screenshots in the folder macOS saves them to. The folder is watched with a file system
/// event source (no polling), so a capture shows up as soon as macOS has saved it.
@MainActor @Observable
final class ScreenshotModel {
    private(set) var items: [URL] = []
    private let folder: URL
    private var source: DispatchSourceFileSystemObject?
    private var generation = 0
    /// Screenshots taken off the card (the files stay). Paths only, so it is small enough to keep as is.
    private var hidden = Set(UserDefaults.standard.stringArray(forKey: "hiddenScreenshots") ?? [])

    init() {
        let location = CFPreferencesCopyAppValue("location" as CFString, "com.apple.screencapture" as CFString) as? String
        folder = Screenshots.folder(location: location, home: FileManager.default.homeDirectoryForCurrentUser)
        scan()
        watch()
    }

    /// True when macOS marked the file as a screenshot, in any system language. Reads the extended attribute
    /// macOS writes itself (what Spotlight later indexes), so it works before, or without, Spotlight indexing.
    private static func isCapture(_ url: URL) -> Bool {
        let name = "com.apple.metadata:kMDItemIsScreenCapture"
        let size = getxattr(url.path, name, nil, 0, 0, 0)
        guard size > 0 else { return false }
        var data = Data(count: size)
        guard data.withUnsafeMutableBytes({ getxattr(url.path, name, $0.baseAddress, size, 0, 0) }) == size else { return false }
        return (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? Bool == true
    }

    private func scan() {
        let hidden = hidden
        let next = Screenshots.newest(in: folder, limit: 6) { !hidden.contains($0.path) && Self.isCapture($0) }
        if next != items { items = next }
    }

    /// Takes a screenshot off the card without touching the file; the next newest one fills the gap.
    func hide(_ url: URL) {
        hidden.insert(url.path)
        UserDefaults.standard.set(Array(hidden), forKey: "hiddenScreenshots")
        scan()
    }

    func trash(_ url: URL) {
        try? FileManager.default.trashItem(at: url, resultingItemURL: nil)
        scan()
    }

    private func watch() {
        let fd = open(folder.path, O_EVTONLY)
        guard fd >= 0 else { return } // no such folder, or no permission yet: nothing to show
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .rename, .delete], queue: .main)
        source.setEventHandler { [weak self] in MainActor.assumeIsolated { self?.changed() } }
        source.setCancelHandler { close(fd) }
        source.resume()
        self.source = source
    }

    /// The folder changed. The file can land in more than one go and Spotlight flags it a moment later, so look
    /// again a few times (one shots, and only the latest change's).
    private func changed() {
        generation += 1
        let mine = generation
        for delay in [0.3, 0.8, 1.6, 3.0] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { MainActor.assumeIsolated { [weak self] in
                if let self, self.generation == mine { self.scan() }
            } }
        }
    }
}
