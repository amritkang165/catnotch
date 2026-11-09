import Testing
import Foundation
@testable import CatNotchCore

private let pages: [NotchPage] = [.home, .desk, .calendar, .files]
private var cal: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c }
private func day(_ d: Int, month: Int = 11) -> Date { cal.date(from: DateComponents(year: 2026, month: month, day: d))! }

@Test func escapeAlwaysCloses() {
    for page in NotchPage.allCases {
        #expect(NotchKeys.action(for: .escape, option: false, page: page) == .close)
    }
}

@Test func arrowsSwitchSectionsOffTheCalendar() {
    #expect(NotchKeys.action(for: .left, option: false, page: .home) == .section(-1))
    #expect(NotchKeys.action(for: .right, option: false, page: .files) == .section(1))
    #expect(NotchKeys.action(for: .up, option: false, page: .home) == nil)
}

@Test func landingOnTheCalendarKeepsArrowsOnSections() {
    #expect(NotchKeys.action(for: .left, option: false, page: .calendar) == .section(-1))
    #expect(NotchKeys.action(for: .right, option: false, page: .calendar) == .section(1))
    #expect(NotchKeys.action(for: .up, option: false, page: .calendar) == nil)
}

@Test func downChoosesADayOnTheCalendarOnly() {
    #expect(NotchKeys.action(for: .down, option: false, page: .calendar) == .day(.down))
    #expect(NotchKeys.action(for: .down, option: false, page: .home) == nil)
}

@Test func aChosenDayTakesTheArrowsButOptionStillSwitches() {
    #expect(NotchKeys.action(for: .left, option: false, page: .calendar, daySelected: true) == .day(.left))
    #expect(NotchKeys.action(for: .up, option: false, page: .calendar, daySelected: true) == .day(.up))
    #expect(NotchKeys.action(for: .left, option: true, page: .calendar, daySelected: true) == .section(-1))
    #expect(NotchKeys.action(for: .right, option: true, page: .calendar, daySelected: true) == .section(1))
}

@Test func sectionsStopAtTheEnds() {
    #expect(NotchKeys.page(from: .home, step: -1, among: pages) == .home)
    #expect(NotchKeys.page(from: .files, step: 1, among: pages) == .files)
    #expect(NotchKeys.page(from: .desk, step: 1, among: pages) == .calendar)
    #expect(NotchKeys.page(from: .desk, step: -1, among: pages) == .home)
}

@Test func aHiddenPageIsSkipped() {
    let noCalendar: [NotchPage] = [.home, .desk, .files]
    #expect(NotchKeys.page(from: .desk, step: 1, among: noCalendar) == .files)
    // a page not in the list (Calendar was just hidden) lands on the first
    #expect(NotchKeys.page(from: .calendar, step: 1, among: noCalendar) == .home)
}

@Test func daysMoveByOneAndByAWeek() {
    #expect(NotchKeys.day(from: day(10), key: .right, now: day(1), calendar: cal) == day(11))
    #expect(NotchKeys.day(from: day(10), key: .left, now: day(1), calendar: cal) == day(9))
    #expect(NotchKeys.day(from: day(10), key: .down, now: day(1), calendar: cal) == day(17))
    #expect(NotchKeys.day(from: day(10), key: .up, now: day(1), calendar: cal) == day(3))
}

@Test func daysCrossMonths() {
    #expect(NotchKeys.day(from: day(30), key: .right, now: day(1), calendar: cal) == day(1, month: 12))
    #expect(NotchKeys.day(from: day(1), key: .left, now: day(1), calendar: cal) == day(31, month: 10))
}

@Test func firstPressStartsFromToday() {
    let now = cal.date(byAdding: .hour, value: 15, to: day(5))!
    #expect(NotchKeys.day(from: nil, key: .right, now: now, calendar: cal) == day(5))
}
