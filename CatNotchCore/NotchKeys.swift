import Foundation

extension NotchPage {
    /// The sections the dock shows, in order. Calendar and the pages in `off` can be switched off in Settings; Home never is.
    public static func shown(calendar: Bool, off: Set<NotchPage> = []) -> [NotchPage] { allCases.filter { ($0 != .calendar || calendar) && !off.contains($0) } }
}

public enum NotchKey: Sendable { case left, right, up, down, escape }

/// What a key does to the open Notch.
public enum NotchKeyAction: Equatable, Sendable {
    case close
    /// Previous (-1) or next (+1) section.
    case section(Int)
    /// Move the calendar's chosen day.
    case day(NotchKey)
}

/// Spec 0031: the keyboard's meaning on each page. Pure; the panel only routes events here.
public enum NotchKeys {
    /// `daySelected`: a day is chosen on the Calendar. Until one is, arrows only switch sections, so landing on Calendar
    /// does not change what they do; Down chooses today and the arrows then move the day.
    public static func action(for key: NotchKey, option: Bool, page: NotchPage, daySelected: Bool = false) -> NotchKeyAction? {
        switch key {
        case .escape: return .close
        case .left, .right:
            if page == .calendar && daySelected && !option { return .day(key) } // Option always switches sections
            return .section(key == .left ? -1 : 1)
        case .down: return page == .calendar ? .day(key) : nil
        case .up: return page == .calendar && daySelected ? .day(key) : nil
        }
    }

    /// The section `step` away in the dock's order, stopping at the ends. A page that is not shown lands on the first.
    public static func page(from page: NotchPage, step: Int, among pages: [NotchPage]) -> NotchPage {
        guard let at = pages.firstIndex(of: page) else { return pages.first ?? page }
        return pages[min(max(at + step, 0), pages.count - 1)]
    }

    /// The calendar's chosen day after `key`: a day either way, a week up or down. With none chosen it starts from today.
    public static func day(from day: Date?, key: NotchKey, now: Date, calendar: Calendar = .current) -> Date {
        guard let day else { return calendar.startOfDay(for: now) }
        let by: Int
        switch key {
        case .left: by = -1
        case .right: by = 1
        case .up: by = -7
        case .down: by = 7
        case .escape: by = 0
        }
        return calendar.date(byAdding: .day, value: by, to: calendar.startOfDay(for: day))!
    }
}
