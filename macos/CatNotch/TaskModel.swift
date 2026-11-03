import Foundation
import Observation
import CatNotchCore

/// The task list for every display's Notch. It mirrors the store, so a task added on one display shows on all.
@MainActor @Observable
final class TaskModel {
    private var data: StoreData
    private let store: CatNotchStore

    init(store: CatNotchStore) {
        self.store = store
        data = store.data
        // Lives as long as the app.
        _ = store.observe { [weak self] next in MainActor.assumeIsolated { self?.data = next } }
    }

    var open: [StoreTask] { data.openTasks }
    var done: [StoreTask] { data.doneTasks }

    func add(_ label: String) { store.addTask(label) }
    func toggle(_ id: String) { store.toggleTask(id) }
    func remove(_ id: String) { store.removeTask(id) }
    func clearDone() { store.clearDoneTasks() }
}
