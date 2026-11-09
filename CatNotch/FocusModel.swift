import Foundation
import Observation
import CatNotchCore

/// The one focus timer, shared by the Notch on every display and by Settings.
/// It wakes once a second, and only while a session runs.
@MainActor @Observable
final class FocusModel {
    private(set) var timer = FocusTimer()
    /// The time the views draw at; moves each second while running.
    private(set) var now = Date()
    private var data: StoreData
    private let store: CatNotchStore
    private var ticker: Timer?

    init(store: CatNotchStore) {
        self.store = store
        data = store.data
        // Lives as long as the app.
        _ = store.observe { [weak self] next in MainActor.assumeIsolated { self?.data = next } }
    }

    var phase: FocusTimer.Phase { timer.phase }
    var minutes: Double { data.focusMinutes }
    var today: (sessions: Int, minutes: Double) { data.focusToday() } // read at draw time, so it rolls over at midnight
    var remaining: TimeInterval { timer.remaining(at: now) }
    var progress: Double { timer.progress(at: now) }

    /// Start, or pause a running session, or resume a paused one.
    func toggle() {
        now = Date()
        if let session = timer.toggle(minutes: minutes, at: now) { store.logFocus(session, now: now) }
        syncTicker()
    }

    func reset() {
        now = Date()
        timer.reset()
        syncTicker()
    }

    func setMinutes(_ value: Double) { store.update { $0.focusMinutes = value } }

    private func syncTicker() {
        ticker?.invalidate()
        ticker = nil
        guard timer.phase == .running else { return }
        let t = Timer(timeInterval: 1, repeats: true) { [weak self] _ in MainActor.assumeIsolated { self?.tick() } }
        RunLoop.main.add(t, forMode: .common) // keeps counting while a menu or drag is tracking
        ticker = t
    }

    private func tick() {
        now = Date()
        if let session = timer.tick(at: now) {
            store.logFocus(session, now: now)
            syncTicker()
        }
    }
}
