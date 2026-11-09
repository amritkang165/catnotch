import Foundation

extension StoreData {
    /// The longest task, as in the Electron field.
    public static let taskMaxLength = 200

    public var openTasks: [StoreTask] { tasks.filter { !$0.done } }
    public var doneTasks: [StoreTask] { tasks.filter(\.done) }

    /// Adds a task at the end. Blank text does nothing; newlines become spaces, since a task is one thought.
    /// `due` is a local day, YYYY-MM-DD (the calendar's day pane sets it; quick add does not).
    public mutating func addTask(_ label: String, due: String? = nil, id: String = UUID().uuidString.lowercased()) {
        let flat = label.components(separatedBy: .newlines).joined(separator: " ") // \r\n counts as one break
        let text = String(flat.trimmingCharacters(in: .whitespaces).prefix(Self.taskMaxLength))
        guard !text.isEmpty else { return }
        tasks.append(StoreTask(id: id, label: text, done: false, due: due))
    }

    public mutating func toggleTask(_ id: String) {
        guard let i = tasks.firstIndex(where: { $0.id == id }) else { return }
        tasks[i].done.toggle()
    }

    public mutating func removeTask(_ id: String) { tasks.removeAll { $0.id == id } }

    public mutating func clearDoneTasks() { tasks.removeAll(where: \.done) }
}

extension CatNotchStore {
    public func addTask(_ label: String, due: String? = nil) { update { $0.addTask(label, due: due) } }
    public func toggleTask(_ id: String) { update { $0.toggleTask(id) } }
    public func removeTask(_ id: String) { update { $0.removeTask(id) } }
    public func clearDoneTasks() { update { $0.clearDoneTasks() } }
}
