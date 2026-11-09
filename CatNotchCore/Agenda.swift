import Foundation

/// What kind of calendar an event came from. Sent by EventKit, not guessed from a name.
public enum CalendarType: Sendable {
    /// The Birthdays calendar.
    case birthday
    /// Any other calendar you cannot edit: a subscribed one, a Google holidays one.
    case readonly
    case other
}

public enum EventKind: Sendable { case birthday, holiday, event }

/// One calendar event, as the Notch shows it. Read only and held in memory only.
public struct AgendaEvent: Equatable, Sendable, Identifiable {
    public var id: String
    public var title: String
    public var start: Date
    public var end: Date
    public var allDay: Bool
    public var calendarID: String
    /// 0xRRGGBB, the calendar's own colour.
    public var color: UInt32
    public var calendarType: CalendarType
    /// An allowlisted video call link, if the event has one.
    public var joinURL: URL?

    public init(id: String, title: String, start: Date, end: Date, allDay: Bool = false, calendarID: String = "",
                color: UInt32 = 0x888888, calendarType: CalendarType = .other, joinURL: URL? = nil) {
        self.id = id; self.title = title; self.start = start; self.end = end; self.allDay = allDay
        self.calendarID = calendarID; self.color = color; self.calendarType = calendarType; self.joinURL = joinURL
    }

    /// Unique per occurrence: a recurring event shares its id, and a birthday may have none.
    public var key: String { "\(calendarID)|\(id)|\(title)|\(start.timeIntervalSinceReferenceDate)" }

    /// A birthday, a holiday (an all day item of a calendar you cannot edit) or a normal event.
    public var kind: EventKind {
        switch calendarType {
        case .birthday: .birthday
        case .readonly: allDay ? .holiday : .event
        case .other: .event
        }
    }

    public var displayTitle: String { title.isEmpty ? "Untitled" : title }
}

/// A calendar the Mac knows, for the Settings switches.
public struct AgendaCalendar: Equatable, Sendable, Identifiable {
    public var id: String
    public var title: String
    public var account: String
    public var color: UInt32

    public init(id: String, title: String, account: String, color: UInt32) {
        self.id = id; self.title = title; self.account = account; self.color = color
    }
}

/// Finds the link that joins a video call. Only Zoom, Google Meet and Teams over https ever get a button.
public enum JoinLink {
    public static func isAllowed(_ url: URL) -> Bool {
        guard url.scheme == "https", let host = url.host?.lowercased() else { return false }
        return host == "zoom.us" || host.hasSuffix(".zoom.us") || host == "meet.google.com"
            || host == "teams.microsoft.com" || host == "teams.live.com"
    }

    private static let pattern = try! NSRegularExpression(pattern: "https://[^\\s<>\"')\\]]+")

    /// The first allowed link across the event's url, then location, then notes (pass them in that order).
    public static func find(in texts: [String?]) -> URL? {
        for case let text? in texts {
            for match in pattern.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                if let range = Range(match.range, in: text), let url = URL(string: String(text[range])), isAllowed(url) { return url }
            }
        }
        return nil
    }
}

/// The agenda's rules, as pure functions of events and a clock.
public enum Agenda {
    /// Midnight of the local day `offset` days from `date`.
    public static func dayStart(_ date: Date, offset: Int = 0, calendar: Calendar = .current) -> Date {
        calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: date))!
    }

    /// The local day as YYYY-MM-DD, the form tasks keep their `due` in. Built from the local parts, never from UTC.
    public static func dayKey(_ date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// Events from calendars that are switched on, ended ones included. A special day two calendars both hold shows once.
    public static func visible(_ events: [AgendaEvent], hidden: Set<String>) -> [AgendaEvent] {
        var seen = Set<String>()
        return events.filter { event in
            guard !hidden.contains(event.calendarID) else { return false }
            if event.kind == .event { return true }
            return seen.insert("\(event.title.trimmingCharacters(in: .whitespaces).lowercased())|\(event.start.timeIntervalSinceReferenceDate)").inserted
        }
    }

    /// Whether the event is on any part of `day`. An all day event's end is exclusive, so it never leaks into the next day.
    public static func overlaps(_ event: AgendaEvent, day: Date, calendar: Calendar = .current) -> Bool {
        event.start < dayStart(day, offset: 1, calendar: calendar) && event.end > calendar.startOfDay(for: day)
    }

    /// One day's events: all day ones first, then by start.
    public static func events(on day: Date, in events: [AgendaEvent], calendar: Calendar = .current) -> [AgendaEvent] {
        events.filter { overlaps($0, day: day, calendar: calendar) }.sorted(by: order)
    }

    /// What is still to come or on now, in the order the list shows it.
    public static func upcoming(_ events: [AgendaEvent], now: Date) -> [AgendaEvent] {
        events.filter { $0.end > now }.sorted(by: order)
    }

    private static func order(_ a: AgendaEvent, _ b: AgendaEvent) -> Bool {
        a.allDay != b.allDay ? a.allDay : a.start < b.start
    }

    /// The next timed event today, for the Home line. All day items never count.
    public static func nextToday(_ events: [AgendaEvent], now: Date, calendar: Calendar = .current) -> AgendaEvent? {
        let midnight = dayStart(now, offset: 1, calendar: calendar)
        return upcoming(events, now: now).first { !$0.allDay && $0.start < midnight }
    }

    /// "in 25 min", "in 1 h 5 min", or "now".
    public static func until(_ event: AgendaEvent, now: Date) -> String {
        let minutes = Int((event.start.timeIntervalSince(now) / 60).rounded(.up))
        if minutes <= 0 { return "now" }
        if minutes < 60 { return "in \(minutes) min" }
        return "in \(minutes / 60) h\(minutes % 60 == 0 ? "" : " \(minutes % 60) min")"
    }

    /// "1 special day, 3 events, 2 tasks". A nil count leaves that part out; zero reads "No events".
    public static func countLine(special: Int?, events: Int?, tasks: Int?) -> String {
        func part(_ n: Int, _ noun: String) -> String { n == 0 ? "No \(noun)s" : "\(n) \(noun)\(n == 1 ? "" : "s")" }
        var parts: [String] = []
        if let special, special > 0 { parts.append(part(special, "special day")) }
        if let events { parts.append(part(events, "event")) }
        if let tasks { parts.append(part(tasks, "task")) }
        return parts.joined(separator: ", ")
    }

    /// The month grid: a 0 for each blank before the 1st (weeks start on Sunday, as the weekday header reads), then 1...days.
    public static func monthCells(_ month: Date, calendar: Calendar = .current) -> [Int] {
        let first = calendar.date(from: calendar.dateComponents([.year, .month], from: month))!
        let blanks = calendar.component(.weekday, from: first) - 1
        let days = calendar.range(of: .day, in: .month, for: first)!.count
        return Array(repeating: 0, count: blanks) + Array(1...days)
    }

    /// How many week rows the month grid has (Electron's `calendarHeight`), so the Notch is only as tall as the month needs.
    public static func weeks(_ month: Date, calendar: Calendar = .current) -> Int {
        (monthCells(month, calendar: calendar).count + 6) / 7
    }

    /// Where events are read for a shown month: the month itself, widened to cover today and tomorrow.
    public static func window(month: Date, now: Date, calendar: Calendar = .current) -> DateInterval {
        let first = calendar.date(from: calendar.dateComponents([.year, .month], from: month))!
        let next = calendar.date(byAdding: .month, value: 1, to: first)!
        return DateInterval(start: min(first, dayStart(now, calendar: calendar)), end: max(next, dayStart(now, offset: 2, calendar: calendar)))
    }
}

extension StoreData {
    /// The tasks that belong on a day: those due that day, and, on today, those with no day. Open first.
    public func dayTasks(on day: Date, now: Date, calendar: Calendar = .current) -> [StoreTask] {
        let key = Agenda.dayKey(day, calendar: calendar)
        let isToday = key == Agenda.dayKey(now, calendar: calendar)
        return tasks.filter { $0.due == key || ($0.due == nil && isToday) }.sorted { !$0.done && $1.done }
    }

    /// Whether an open task is due that day. Undated tasks never mark a day.
    public func hasOpenTask(on day: Date, calendar: Calendar = .current) -> Bool {
        let key = Agenda.dayKey(day, calendar: calendar)
        return tasks.contains { !$0.done && $0.due == key }
    }

    /// Calendars switched off in Settings, saved under the Electron key `hiddenCalendarIds`.
    public var hiddenCalendarIDs: Set<String> {
        get {
            guard case .array(let list)? = settings["hiddenCalendarIds"] else { return [] }
            return Set(list.compactMap { if case .string(let s) = $0 { s } else { nil } })
        }
        set { settings["hiddenCalendarIds"] = .array(newValue.sorted().map(JSONValue.string)) }
    }

    /// The calendar view's on switch (`showCalendar`, default on).
    public var showCalendar: Bool {
        get { if case .bool(let on)? = settings["showCalendar"] { on } else { true } }
        set { settings["showCalendar"] = .bool(newValue) }
    }
}

extension CatNotchStore {
    public func setCalendar(_ id: String, shown: Bool) {
        update { if shown { $0.hiddenCalendarIDs.remove(id) } else { $0.hiddenCalendarIDs.insert(id) } }
    }
}

/// One Apple Reminder that is not done and has a due day.
public struct ReminderItem: Equatable, Sendable, Identifiable {
    public var id: String
    public var title: String
    public var due: Date
    /// False for a reminder due on a day with no time of day.
    public var hasTime: Bool
    public var list: String
    public var color: UInt32

    public init(id: String, title: String, due: Date, hasTime: Bool, list: String = "", color: UInt32 = 0x888888) {
        self.id = id; self.title = title; self.due = due; self.hasTime = hasTime; self.list = list; self.color = color
    }
}

public enum ReminderGroup: Int, Comparable, CaseIterable, Sendable {
    case overdue, today, later

    public static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }
    public var title: String { ["Overdue", "Today", "Later"][rawValue] }

    /// A day before today is overdue. Today's reminder stays under Today whether or not its time has passed.
    public init(due: Date, now: Date, calendar: Calendar = .current) {
        let today = calendar.startOfDay(for: now)
        self = due < today ? .overdue : due < Agenda.dayStart(now, offset: 1, calendar: calendar) ? .today : .later
    }
}

public enum Reminders {
    /// Soonest first within each group; empty groups are left out.
    public static func grouped(_ items: [ReminderItem], now: Date, calendar: Calendar = .current) -> [(group: ReminderGroup, items: [ReminderItem])] {
        let sorted = items.sorted { $0.due < $1.due }
        return ReminderGroup.allCases.compactMap { group in
            let inGroup = sorted.filter { ReminderGroup(due: $0.due, now: now, calendar: calendar) == group }
            return inGroup.isEmpty ? nil : (group, inGroup)
        }
    }
}
