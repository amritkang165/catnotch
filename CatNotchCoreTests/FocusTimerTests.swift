import Foundation
import Testing
@testable import CatNotchCore

private let t0 = Date(timeIntervalSince1970: 1_762_000_000)
private func after(_ s: TimeInterval) -> Date { t0.addingTimeInterval(s) }

@Test func startRunsDownAndFinishesOnce() {
    var timer = FocusTimer()
    #expect(timer.phase == .idle)
    timer.start(minutes: 1, at: t0)
    #expect(timer.phase == .running)
    #expect(timer.remaining(at: after(20)) == 40)
    #expect(timer.progress(at: after(15)) == 0.25)
    #expect(timer.tick(at: after(59)) == nil)
    #expect(timer.tick(at: after(60)) == FocusSession(at: after(60).timeIntervalSince1970 * 1000, minutes: 1))
    #expect(timer.phase == .finished)
    #expect(timer.remaining(at: after(90)) == 0)
    #expect(timer.tick(at: after(91)) == nil) // logged once, on the edge
}

@Test func pauseHoldsTheTimeAndResumeContinues() {
    var timer = FocusTimer()
    timer.start(minutes: 2, at: t0)
    timer.pause(at: after(30))
    #expect(timer.phase == .paused)
    #expect(timer.remaining(at: after(500)) == 90)
    #expect(timer.tick(at: after(500)) == nil) // a paused session never finishes
    timer.resume(at: after(500))
    #expect(timer.phase == .running)
    #expect(timer.remaining(at: after(560)) == 30)
}

@Test func resetAndRestartAfterFinish() {
    var timer = FocusTimer()
    timer.start(minutes: 1, at: t0)
    timer.reset()
    #expect(timer.phase == .idle)
    #expect(timer.remaining(at: after(5)) == 0)
    timer.start(minutes: 1, at: t0)
    _ = timer.tick(at: after(60))
    timer.start(minutes: 5, at: after(100)) // a new session after a finish
    #expect(timer.phase == .running)
    #expect(timer.remaining(at: after(100)) == 300)
}

@Test func controlsOutOfPhaseDoNothing() {
    var timer = FocusTimer()
    timer.pause(at: t0)
    timer.resume(at: t0)
    #expect(timer.phase == .idle)
    timer.start(minutes: 0, at: t0) // no empty session
    #expect(timer.phase == .idle)
}

@Test func loggedMinutesRoundTheLength() {
    var timer = FocusTimer()
    timer.start(minutes: 1.5, at: t0) // 1:30 is a legal custom length
    #expect(timer.tick(at: after(90))?.minutes == 2)
}

@Test func lengthsFormatAndOfferOldValues() {
    #expect(FocusLength.format(25) == "25:00")
    #expect(FocusLength.format(1.5) == "1:30")
    #expect(FocusLength.clock(seconds: 61.2) == "1:02") // rounds up so the ring never shows 0:00 while running
    #expect(FocusLength.options(including: 25) == FocusLength.all)
    #expect(FocusLength.options(including: 1.5) == [1, 1.5, 2, 5, 10, 15, 20, 25, 30, 45, 60])
}

@Test func focusMinutesDefaultsTo25AndPersists() {
    var data = StoreData()
    #expect(data.focusMinutes == 25)
    data.settings["focusMinutes"] = .number(0)
    #expect(data.focusMinutes == 25) // unusable values fall back
    data.focusMinutes = 45
    #expect(data.settings["focusMinutes"] == .number(45))
}

@Test func loggedSessionsSurviveARelaunchAndOldOnesAreDropped() {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    func open() -> CatNotchStore {
        CatNotchStore(directory: root.appendingPathComponent("CatNotch"), legacyDirectory: root.appendingPathComponent("DeskNotch"))
    }
    let now = Date()
    let old = FocusSession(at: now.addingTimeInterval(-91 * 86400).timeIntervalSince1970 * 1000, minutes: 25)
    let store = open()
    store.update { $0.focusLog = [old] }
    let fresh = FocusSession(at: now.timeIntervalSince1970 * 1000, minutes: 25)
    store.logFocus(fresh, now: now)
    #expect(open().data.focusLog == [fresh])
}

@Test func todayCountsOnlyTodaysSessions() {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(identifier: "UTC")!
    let noon = cal.date(from: DateComponents(year: 2026, month: 11, day: 3, hour: 12))!
    func ms(_ d: Date) -> Double { d.timeIntervalSince1970 * 1000 }
    var data = StoreData()
    data.focusLog = [
        FocusSession(at: ms(noon.addingTimeInterval(-86400)), minutes: 50),
        FocusSession(at: ms(noon.addingTimeInterval(-3600)), minutes: 25),
        FocusSession(at: ms(noon), minutes: 10),
    ]
    let today = data.focusToday(now: noon, calendar: cal)
    #expect(today.sessions == 2)
    #expect(today.minutes == 35)
}

@Test func toggleStartsPausesAndResumes() {
    var timer = FocusTimer()
    #expect(timer.toggle(minutes: 1, at: t0) == nil)
    #expect(timer.phase == .running)
    _ = timer.toggle(minutes: 1, at: after(10))
    #expect(timer.phase == .paused)
    _ = timer.toggle(minutes: 1, at: after(20))
    #expect(timer.phase == .running)
    #expect(timer.remaining(at: after(20)) == 50)
}

@Test func lateToggleFinishesInsteadOfFreezingAtZero() {
    var timer = FocusTimer()
    timer.start(minutes: 1, at: t0)
    let done = timer.toggle(minutes: 1, at: after(75)) // Pause pressed after the time ran out
    #expect(timer.phase == .finished)
    #expect(done == FocusSession(at: after(60).timeIntervalSince1970 * 1000, minutes: 1)) // logged when it ran out
}

@Test func unusableLengthsFallBackTo25() {
    var data = StoreData()
    for bad in [1e300, -5, Double.infinity] {
        data.settings["focusMinutes"] = .number(bad)
        #expect(data.focusMinutes == 25)
    }
}

@Test func sessionExactlyAtTheCutoffIsDropped() {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let store = CatNotchStore(directory: root.appendingPathComponent("CatNotch"), legacyDirectory: root.appendingPathComponent("DeskNotch"))
    let now = Date(timeIntervalSince1970: 1_762_000_000)
    let edge = FocusSession(at: now.timeIntervalSince1970 * 1000 - 90 * 86_400_000, minutes: 5)
    let inside = FocusSession(at: edge.at + 1, minutes: 5)
    store.update { $0.focusLog = [edge, inside] }
    store.logFocus(FocusSession(at: now.timeIntervalSince1970 * 1000, minutes: 25), now: now)
    #expect(store.data.focusLog.map(\.at).contains(edge.at) == false)
    #expect(store.data.focusLog.map(\.at).contains(inside.at))
}
