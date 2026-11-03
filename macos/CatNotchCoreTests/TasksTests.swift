import Foundation
import Testing
@testable import CatNotchCore

@Test func addTrimsAndKeepsOrder() {
    var data = StoreData()
    data.addTask("  Write spec ", id: "a")
    data.addTask("Ship it", id: "b")
    #expect(data.tasks == [StoreTask(id: "a", label: "Write spec", done: false, due: nil),
                           StoreTask(id: "b", label: "Ship it", done: false, due: nil)])
}

@Test func addIgnoresBlankAndCapsLength() {
    var data = StoreData()
    data.addTask("   ", id: "a")
    data.addTask("", id: "b")
    #expect(data.tasks.isEmpty)
    data.addTask(String(repeating: "x", count: 300), id: "c")
    #expect(data.tasks[0].label.count == StoreData.taskMaxLength)
}

@Test func addFlattensNewlines() {
    var data = StoreData()
    data.addTask("one\ntwo", id: "a") // a task is one thought, as in the Electron field
    #expect(data.tasks[0].label == "one two")
    data.addTask("pasted\r\n", id: "b")
    #expect(data.tasks[1].label == "pasted")
}

@Test func toggleCompleteAndBack() {
    var data = StoreData()
    data.addTask("A", id: "a")
    data.toggleTask("a")
    #expect(data.tasks[0].done)
    #expect(data.openTasks.isEmpty && data.doneTasks.count == 1)
    data.toggleTask("a")
    #expect(!data.tasks[0].done)
    data.toggleTask("missing") // no such task: nothing happens
    #expect(data.tasks.count == 1)
}

@Test func removeAndClearDone() {
    var data = StoreData()
    for id in ["a", "b", "c"] { data.addTask(id.uppercased(), id: id) }
    data.toggleTask("a")
    data.toggleTask("b")
    data.removeTask("c")
    #expect(data.tasks.map(\.id) == ["a", "b"])
    data.clearDoneTasks()
    #expect(data.tasks.isEmpty)
}

@Test func tasksSurviveARelaunchAndImportKeepsDue() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let legacy = root.appendingPathComponent("DeskNotch")
    try FileManager.default.createDirectory(at: legacy, withIntermediateDirectories: true)
    try Data(#"{"todos":[{"id":"x","label":"Old one","done":true,"due":"2026-11-05"}]}"#.utf8)
        .write(to: legacy.appendingPathComponent("desknotch-store.json"))
    let dir = root.appendingPathComponent("CatNotch")

    let first = CatNotchStore(directory: dir, legacyDirectory: legacy)
    #expect(first.data.tasks == [StoreTask(id: "x", label: "Old one", done: true, due: "2026-11-05")]) // imported
    first.addTask("New one")
    first.toggleTask("x")

    let second = CatNotchStore(directory: dir, legacyDirectory: legacy) // a relaunch
    #expect(second.data.tasks.map(\.label) == ["Old one", "New one"])
    #expect(second.data.tasks[0].done == false)
    #expect(second.data.tasks[0].due == "2026-11-05")
    second.removeTask("x")
    #expect(CatNotchStore(directory: dir, legacyDirectory: legacy).data.tasks.map(\.label) == ["New one"])
}
