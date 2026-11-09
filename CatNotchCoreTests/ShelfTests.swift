import Foundation
import Testing
@testable import CatNotchCore

/// A temp folder with real files, since bookmarks point at the disk.
private struct Disk {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    init() throws { try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true) }

    @discardableResult func file(_ name: String, in folder: String? = nil, created: Date? = nil) throws -> URL {
        let dir = folder.map { root.appendingPathComponent($0) } ?? root
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(name)
        try Data("x".utf8).write(to: url)
        if let created { try FileManager.default.setAttributes([.creationDate: created], ofItemAtPath: url.path) }
        return url
    }
}

@Test func shelfItemSurvivesAMove() throws {
    let disk = try Disk()
    let a = try disk.file("a.txt")
    let item = FileRef(url: a)
    let moved = disk.root.appendingPathComponent("b.txt")
    try FileManager.default.moveItem(at: a, to: moved)
    let found = try #require(item.resolve())
    #expect(found.url.resolvingSymlinksInPath().path == moved.resolvingSymlinksInPath().path)
}

@Test func shelfItemFallsBackToItsPathWithoutABookmark() throws {
    let disk = try Disk()
    let a = try disk.file("a.txt")
    #expect(FileRef(path: a.path, bookmark: nil).resolve()?.url.path == a.path)
}

@Test func goneFileResolvesToNothing() throws {
    let disk = try Disk()
    let a = try disk.file("a.txt")
    let item = FileRef(url: a)
    try FileManager.default.removeItem(at: a)
    #expect(item.resolve() == nil)
    #expect(FileRef(path: "/no/such/file", bookmark: nil).resolve() == nil)
}

@Test func addToShelfKeepsOrderAndSkipsDuplicates() throws {
    let disk = try Disk()
    let a = try disk.file("a.txt"), b = try disk.file("b.txt")
    var data = StoreData()
    data.addToShelf([a, b])
    data.addToShelf([a])
    #expect(data.shelf.map(\.path) == [a.path, b.path])
    #expect(data.shelf.allSatisfy { $0.bookmark != nil })
}

@Test func removeFromShelfTakesOnlyThatItem() throws {
    let disk = try Disk()
    let a = try disk.file("a.txt"), b = try disk.file("b.txt")
    var data = StoreData()
    data.addToShelf([a, b])
    data.removeFromShelf(path: a.path)
    #expect(data.shelf.map(\.path) == [b.path])
}

@Test func clearShelfEmptiesIt() throws {
    let disk = try Disk()
    var data = StoreData()
    data.addToShelf([try disk.file("a.txt"), try disk.file("b.txt")])
    data.clearShelf()
    #expect(data.shelf.isEmpty)
}

@Test func refreshFollowsAMovedFileAndBookmarksOldPaths() throws {
    let disk = try Disk()
    let a = try disk.file("a.txt"), c = try disk.file("c.txt")
    var data = StoreData()
    data.addToShelf([a])
    data.shelf.append(FileRef(path: c.path, bookmark: nil)) // as the import leaves it
    let moved = disk.root.appendingPathComponent("b.txt")
    try FileManager.default.moveItem(at: a, to: moved)
    data.refreshShelf()
    #expect(data.shelf[0].url?.resolvingSymlinksInPath().path == moved.resolvingSymlinksInPath().path)
    #expect(data.shelf[1].bookmark != nil)
}

@Test func refreshLeavesAGoneItemOnTheShelf() throws {
    var data = StoreData()
    data.shelf = [FileRef(path: "/no/such/file", bookmark: nil)]
    data.refreshShelf()
    #expect(data.shelf.map(\.path) == ["/no/such/file"])
}

@Test func shelfReadsOldPathsAndWritesObjects() throws {
    let old = try JSONDecoder().decode(StoreData.self, from: Data(#"{ "shelf": ["/x"] }"#.utf8))
    #expect(old.shelf == ["/x"])
    var data = StoreData()
    data.shelf = [FileRef(path: "/y", bookmark: Data([1, 2]))]
    let back = try JSONDecoder().decode(StoreData.self, from: JSONEncoder().encode(data))
    #expect(back.shelf == data.shelf)
}

@Test func photoSurvivesASaveAndReload() throws {
    let disk = try Disk()
    let picked = try disk.file("me.png")
    var data = StoreData()
    data.photo = FileRef(url: picked)
    let back = try JSONDecoder().decode(StoreData.self, from: JSONEncoder().encode(data))
    #expect(back.photo?.resolve()?.url.lastPathComponent == "me.png")
}

@Test func screenshotFolderIsTheSetLocationElseDesktop() {
    let home = URL(fileURLWithPath: "/Users/me")
    #expect(Screenshots.folder(location: nil, home: home).path == "/Users/me/Desktop")
    #expect(Screenshots.folder(location: "  ", home: home).path == "/Users/me/Desktop")
    #expect(Screenshots.folder(location: "~/Pictures/Shots", home: home).path == "/Users/me/Pictures/Shots")
    #expect(Screenshots.folder(location: "/Volumes/Big/Shots", home: home).path == "/Volumes/Big/Shots")
}

@Test func newestScreenshotsAreCapturesOnlyNewestFirst() throws {
    let disk = try Disk()
    let now = Date()
    try disk.file("old.png", created: now - 300)
    try disk.file("mid.jpg", created: now - 200)
    try disk.file("new.png", created: now - 100)
    try disk.file("photo.jpeg", created: now - 50)  // an image, but not a capture
    try disk.file("notes.txt", created: now - 10)   // not an image
    let found = Screenshots.newest(in: disk.root, limit: 2) { $0.lastPathComponent != "photo.jpeg" }
    #expect(found.map(\.lastPathComponent) == ["new.png", "mid.jpg"])
}

@Test func newestScreenshotsOfAMissingFolderIsEmpty() {
    #expect(Screenshots.newest(in: URL(fileURLWithPath: "/no/such/folder"), limit: 3) { _ in true }.isEmpty)
}
