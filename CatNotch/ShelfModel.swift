import Foundation
import Observation
import CatNotchCore

/// One shelf file with where it is now (nil when it is gone).
struct ShelfEntry: Identifiable {
    let ref: FileRef
    let url: URL?
    var id: String { ref.path }
    var name: String { (ref.path as NSString).lastPathComponent }
}

/// The shelf for every display's Notch. It mirrors the store, so a file dropped on one display shows on all.
@MainActor @Observable
final class ShelfModel {
    private(set) var entries: [ShelfEntry] = []
    private let store: CatNotchStore

    init(store: CatNotchStore) {
        self.store = store
        entries = Self.entries(store.data)
        // Lives as long as the app.
        _ = store.observe { [weak self] next in MainActor.assumeIsolated { self?.entries = Self.entries(next) } }
        refresh()
    }

    private static func entries(_ data: StoreData) -> [ShelfEntry] { data.shelf.map { ShelfEntry(ref: $0, url: $0.url) } }

    func add(_ urls: [URL]) { store.addToShelf(urls) }
    func remove(_ entry: ShelfEntry) { store.removeFromShelf(path: entry.ref.path) }
    func clear() { store.clearShelf() }

    /// Follows files that moved since the shelf was last looked at. Cheap, so the Files view calls it each time it shows.
    func refresh() {
        store.refreshShelf()
        entries = Self.entries(store.data) // a file that came back or went away changes nothing in the store
    }
}
