import Foundation
import Testing
@testable import CatNotchCore

/// An old DeskNotch store as the Electron app wrote it, with keys the native store does not import.
private let oldStore = """
{
  "todos": [{ "id": "a", "label": "Ship it", "done": false, "due": "2026-11-05" }, { "id": "b", "label": "Rest", "done": true }],
  "settings": { "notchStyle": "glass", "focusMinutes": 25, "showMusic": true, "favoriteApps": ["/Applications/Mail.app"], "dockSize": null },
  "photo": "data:image/png;base64,AAAA",
  "shelf": ["/Users/me/a.png"],
  "pins": [],
  "focusLog": [{ "at": 1762000000000, "minutes": 25 }],
  "reminders": [],
  "aiConsent": true,
  "claudeHooks": { "enabled": true, "token": "t", "port": 47821 }
}
"""

/// A temp support folder with an old DeskNotch folder beside it.
private struct Folders {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    var new: URL { root.appendingPathComponent("CatNotch") }
    var old: URL { root.appendingPathComponent("DeskNotch") }
    var oldFile: URL { old.appendingPathComponent("desknotch-store.json") }

    init(oldContents: String? = oldStore) throws {
        try FileManager.default.createDirectory(at: old, withIntermediateDirectories: true)
        if let oldContents { try Data(oldContents.utf8).write(to: oldFile) }
    }

    func launch() -> CatNotchStore { CatNotchStore(directory: new, legacyDirectory: old) }
}

@Test func firstLaunchImportsTheOldStore() throws {
    let store = try Folders().launch()
    #expect(store.data.tasks == [
        StoreTask(id: "a", label: "Ship it", done: false, due: "2026-11-05"),
        StoreTask(id: "b", label: "Rest", done: true, due: nil),
    ])
    #expect(store.data.focusLog == [FocusSession(at: 1762000000000, minutes: 25)])
    #expect(store.data.shelf == ["/Users/me/a.png"])
    #expect(store.data.settings["notchStyle"] == .string("glass"))
    #expect(store.data.settings["focusMinutes"] == .number(25))
    #expect(store.data.settings["favoriteApps"] == .array([.string("/Applications/Mail.app")]))
}

@Test func importLeavesTheOldFileByteIdentical() throws {
    let folders = try Folders()
    let before = try Data(contentsOf: folders.oldFile)
    let store = folders.launch()
    store.update { $0.tasks.removeAll() }
    _ = folders.launch()
    #expect(try Data(contentsOf: folders.oldFile) == before)
}

@Test func theImportIsWrittenToCatNotchStoreJson() throws {
    let folders = try Folders()
    _ = folders.launch()
    #expect(FileManager.default.fileExists(atPath: folders.new.appendingPathComponent("catnotch-store.json").path))
}

@Test func secondLaunchKeepsNewerDataAndDoesNotReimport() throws {
    let folders = try Folders()
    folders.launch().update { $0.tasks = [StoreTask(id: "z", label: "Newer", done: false, due: nil)] }
    #expect(folders.launch().data.tasks.map(\.id) == ["z"])
}

@Test func corruptNewStoreStartsCleanAndIsKeptAside() throws {
    let folders = try Folders()
    try FileManager.default.createDirectory(at: folders.new, withIntermediateDirectories: true)
    try Data("{ not json".utf8).write(to: folders.new.appendingPathComponent("catnotch-store.json"))
    let store = folders.launch()
    #expect(store.data == StoreData()) // not re-imported over the user's data
    #expect(FileManager.default.fileExists(atPath: folders.new.appendingPathComponent("catnotch-store.unreadable.json").path))
}

@Test func newStoreMissingAKeyStillLoads() throws {
    let folders = try Folders()
    try FileManager.default.createDirectory(at: folders.new, withIntermediateDirectories: true)
    try Data(#"{ "shelf": ["/x"] }"#.utf8).write(to: folders.new.appendingPathComponent("catnotch-store.json"))
    #expect(folders.launch().data.shelf == ["/x"])
}

@Test func focusLogSurvivesARelaunch() throws {
    let folders = try Folders()
    _ = folders.launch()
    #expect(folders.launch().data.focusLog == [FocusSession(at: 1762000000000, minutes: 25)])
}

@Test func missingOldStoreStartsEmpty() throws {
    let store = try Folders(oldContents: nil).launch()
    #expect(store.data == StoreData())
}

@Test func corruptOldStoreStartsEmpty() throws {
    let store = try Folders(oldContents: "{ not json").launch()
    #expect(store.data == StoreData())
}

@Test func aSettingChangedOnOneDisplayShowsOnTheOthers() throws {
    let store = try Folders().launch()
    var seenOnA: JSONValue?, seenOnB: JSONValue?
    _ = store.observe { seenOnA = $0.settings["notchStyle"] }
    _ = store.observe { seenOnB = $0.settings["notchStyle"] }
    store.update { $0.settings["notchStyle"] = .string("transparent") } // one display changes it
    #expect(seenOnA == .string("transparent"))
    #expect(seenOnB == .string("transparent"))
}

@Test func anUnchangedUpdateDoesNotNotify() throws {
    let store = try Folders().launch()
    var calls = 0
    _ = store.observe { _ in calls += 1 }
    store.update { _ in }
    #expect(calls == 0)
}

@Test func stoppedObserversAreNotCalled() throws {
    let store = try Folders().launch()
    var calls = 0
    let stop = store.observe { _ in calls += 1 }
    stop()
    store.update { $0.shelf = ["/x"] }
    #expect(calls == 0)
}
