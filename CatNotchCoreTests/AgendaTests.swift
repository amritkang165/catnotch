import Foundation
import Testing
@testable import CatNotchCore

private var cal: Calendar {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "Europe/London")!
    return c
}

private func at(_ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
    cal.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
}

private func event(_ title: String, _ start: Date, _ end: Date, allDay: Bool = false, type: CalendarType = .other, calendar: String = "work") -> AgendaEvent {
    AgendaEvent(id: title, title: title, start: start, end: end, allDay: allDay, calendarID: calendar, calendarType: type)
}

// MARK: kinds and join links

@Test func kindComesFromTheCalendarTypeAndAllDay() {
    #expect(event("b", at(5), at(6), allDay: true, type: .birthday).kind == .birthday)
    #expect(event("h", at(5), at(6), allDay: true, type: .readonly).kind == .holiday)
    #expect(event("t", at(5, 9), at(5, 10), type: .readonly).kind == .event) // a timed event of a read only calendar is a meeting
    #expect(event("trip", at(5), at(6), allDay: true, type: .other).kind == .event) // your own all day entry is not a holiday
}

@Test func joinLinkAcceptsOnlyTheAllowlistOverHTTPS() {
    #expect(JoinLink.find(in: [nil, "Room 4", "Join https://us02web.zoom.us/j/123?pwd=x now"]) == URL(string: "https://us02web.zoom.us/j/123?pwd=x"))
    #expect(JoinLink.find(in: ["https://meet.google.com/abc-defg-hij"]) != nil)
    #expect(JoinLink.find(in: ["https://teams.microsoft.com/l/meetup-join/1"]) != nil)
    #expect(JoinLink.find(in: ["http://zoom.us/j/1"]) == nil)
    #expect(JoinLink.find(in: ["https://zoom.us.evil.com/j/1"]) == nil)
    #expect(JoinLink.find(in: ["https://evil.com/zoom.us"]) == nil)
    #expect(JoinLink.find(in: ["javascript:alert(1)"]) == nil)
}

@Test func joinLinkSkipsAnUnsafeLinkForALaterSafeOne() {
    #expect(JoinLink.find(in: ["https://evil.com/x", "https://zoom.us/j/9"]) == URL(string: "https://zoom.us/j/9"))
}

// MARK: days

@Test func dayKeyUsesTheLocalDay() {
    #expect(Agenda.dayKey(at(5, 23, 30), calendar: cal) == "2026-11-05")
    #expect(Agenda.dayKey(at(5, 0, 10), calendar: cal) == "2026-11-05")
}

@Test func anAllDayEventDoesNotLeakIntoTomorrow() {
    let day = event("off", at(5), at(6), allDay: true) // end is exclusive
    #expect(Agenda.overlaps(day, day: at(5, 15), calendar: cal))
    #expect(!Agenda.overlaps(day, day: at(6, 15), calendar: cal))
    #expect(!Agenda.overlaps(day, day: at(4, 15), calendar: cal))
}

@Test func aMultiDayEventShowsOnEveryDayItCovers() {
    let trip = event("trip", at(5), at(8), allDay: true)
    #expect([5, 6, 7].allSatisfy { Agenda.overlaps(trip, day: at($0, 12), calendar: cal) })
    #expect(!Agenda.overlaps(trip, day: at(8, 12), calendar: cal))
}

@Test func aDaysEventsPutAllDayFirstThenByStart() {
    let list = [event("late", at(5, 15), at(5, 16)), event("early", at(5, 9), at(5, 10)),
                event("holiday", at(5), at(6), allDay: true), event("other day", at(6, 9), at(6, 10))]
    #expect(Agenda.events(on: at(5), in: list, calendar: cal).map(\.title) == ["holiday", "early", "late"])
}

@Test func hiddenCalendarsAndRepeatedSpecialDaysDropOut() {
    let list = [event("a", at(5, 9), at(5, 10), calendar: "noise"), event("b", at(5, 9), at(5, 10)),
                event("Diwali", at(5), at(6), allDay: true, type: .readonly, calendar: "india"),
                event("diwali ", at(5), at(6), allDay: true, type: .readonly, calendar: "google")]
    #expect(Agenda.visible(list, hidden: ["noise"]).map(\.title) == ["b", "Diwali"])
    #expect(Agenda.visible(list, hidden: ["india", "noise"]).map(\.title) == ["b", "diwali "]) // the other copy stays
}

// MARK: the Home line

@Test func upcomingDropsEndedEventsAndNextTodaySkipsAllDay() {
    let now = at(5, 10, 30)
    let list = [event("ended", at(5, 9), at(5, 10)), event("holiday", at(5), at(6), allDay: true),
                event("now", at(5, 10), at(5, 11)), event("lunch", at(5, 12), at(5, 13)), event("tomorrow", at(6, 9), at(6, 10))]
    #expect(Agenda.upcoming(list, now: now).map(\.title) == ["holiday", "now", "lunch", "tomorrow"])
    #expect(Agenda.nextToday(list, now: now, calendar: cal)?.title == "now") // on now counts as next
    #expect(Agenda.nextToday([list[1], list[4]], now: now, calendar: cal) == nil) // nothing timed left today
}

@Test func untilCountsDownInWholeMinutesRoundedUp() {
    let e = event("x", at(5, 12), at(5, 13))
    #expect(Agenda.until(e, now: at(5, 11, 35)) == "in 25 min")
    #expect(Agenda.until(e, now: at(5, 11, 59)) == "in 1 min")
    #expect(Agenda.until(e, now: at(5, 10, 55)) == "in 1 h 5 min")
    #expect(Agenda.until(e, now: at(5, 11)) == "in 1 h")
    #expect(Agenda.until(e, now: at(5, 12)) == "now")
    #expect(Agenda.until(e, now: at(5, 12, 20)) == "now")
}

// MARK: day pane

@Test func countLineReadsLikeTheElectronPane() {
    #expect(Agenda.countLine(special: 1, events: 2, tasks: 1) == "1 special day, 2 events, 1 task")
    #expect(Agenda.countLine(special: 0, events: 0, tasks: 0) == "No events, No tasks")
    #expect(Agenda.countLine(special: 3, events: 1, tasks: nil) == "3 special days, 1 event")
    #expect(Agenda.countLine(special: nil, events: nil, tasks: 2) == "2 tasks") // calendar access off
}

@Test func aDaysTasksAreThoseDueThenAndUndatedOnesOnToday() {
    var data = StoreData()
    data.tasks = [StoreTask(id: "a", label: "done today", done: true, due: "2026-11-05"),
                  StoreTask(id: "b", label: "open today", done: false, due: "2026-11-05"),
                  StoreTask(id: "c", label: "undated", done: false, due: nil),
                  StoreTask(id: "d", label: "later", done: false, due: "2026-11-09")]
    let now = at(5, 12)
    #expect(data.dayTasks(on: at(5), now: now, calendar: cal).map(\.id) == ["b", "c", "a"]) // open first
    #expect(data.dayTasks(on: at(9), now: now, calendar: cal).map(\.id) == ["d"]) // undated stay on today only
    #expect(data.dayTasks(on: at(6), now: now, calendar: cal).isEmpty)
}

@Test func onlyAnOpenDatedTaskMarksADay() {
    var data = StoreData()
    data.tasks = [StoreTask(id: "a", label: "x", done: false, due: "2026-11-05"),
                  StoreTask(id: "b", label: "y", done: true, due: "2026-11-06"),
                  StoreTask(id: "c", label: "z", done: false, due: nil)]
    #expect(data.hasOpenTask(on: at(5), calendar: cal))
    #expect(!data.hasOpenTask(on: at(6), calendar: cal)) // done
    #expect(!data.hasOpenTask(on: at(7), calendar: cal)) // undated tasks mark nothing
}

@Test func aTaskAddedOnADayKeepsThatDay() {
    var data = StoreData()
    data.addTask("plan", due: "2026-11-09", id: "a")
    data.addTask("quick", id: "b")
    #expect(data.tasks.map(\.due) == ["2026-11-09", nil])
}

// MARK: month

@Test func monthCellsStartOnTheRightWeekday() {
    let nov = Agenda.monthCells(at(15), calendar: cal) // 1 November 2026 is a Sunday
    #expect(nov.first == 1 && nov.count == 30)
    let dec = Agenda.monthCells(cal.date(from: DateComponents(year: 2026, month: 12, day: 15))!, calendar: cal) // 1 December is a Tuesday
    #expect(dec.prefix(3) == [0, 0, 1] && dec.count == 2 + 31)
}

@Test func aMonthHasAsManyWeeksAsItNeeds() {
    #expect(Agenda.weeks(at(15), calendar: cal) == 5) // November 2026: Sunday the 1st, 30 days
    #expect(Agenda.weeks(cal.date(from: DateComponents(year: 2026, month: 12, day: 15))!, calendar: cal) == 5) // Tuesday the 1st, 31 days
    #expect(Agenda.weeks(cal.date(from: DateComponents(year: 2026, month: 8, day: 15))!, calendar: cal) == 6) // Saturday the 1st, 31 days
}

@Test func theQueryWindowCoversTheMonthTodayAndTomorrow() {
    let now = at(5, 12)
    let same = Agenda.window(month: at(15), now: now, calendar: cal)
    #expect(same.start == at(1) && same.end == cal.date(from: DateComponents(year: 2026, month: 12, day: 1))!)
    let past = Agenda.window(month: cal.date(from: DateComponents(year: 2026, month: 8, day: 1))!, now: now, calendar: cal)
    #expect(past.start == cal.date(from: DateComponents(year: 2026, month: 8, day: 1))! && past.end == at(7)) // reaches today and tomorrow
}

// MARK: settings

@Test func hiddenCalendarsAndTheSwitchRoundTripThroughSettings() {
    var data = StoreData()
    #expect(data.hiddenCalendarIDs.isEmpty && data.showCalendar)
    data.hiddenCalendarIDs = ["b", "a"]
    data.showCalendar = false
    #expect(data.hiddenCalendarIDs == ["a", "b"] && !data.showCalendar)
    // The Electron store keeps the same keys, so an imported value reads back.
    let old = try? JSONDecoder().decode(StoreData.self, from: Data(#"{"settings":{"hiddenCalendarIds":["x"],"showCalendar":false}}"#.utf8))
    #expect(old?.hiddenCalendarIDs == ["x"] && old?.showCalendar == false)
}

// MARK: reminders

@Test func remindersGroupByDayAndSortSoonestFirst() {
    let now = at(5, 12)
    func r(_ id: String, _ due: Date) -> ReminderItem { ReminderItem(id: id, title: id, due: due, hasTime: true) }
    let items = [r("later", at(9, 9)), r("passed today", at(5, 9)), r("yesterday", at(4, 18)), r("tonight", at(5, 21)), r("soon", at(6, 8))]
    let groups = Reminders.grouped(items, now: now, calendar: cal)
    #expect(groups.map(\.group) == [.overdue, .today, .later])
    #expect(groups.map { $0.items.map(\.id) } == [["yesterday"], ["passed today", "tonight"], ["soon", "later"]])
    #expect(Reminders.grouped([], now: now, calendar: cal).isEmpty)
}
