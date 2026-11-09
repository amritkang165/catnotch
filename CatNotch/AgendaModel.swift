import AppKit
import EventKit
import Observation
import CatNotchCore

/// Where one macOS permission stands. Denied also covers restricted and "add only" access.
enum AgendaAccess { case unknown, granted, denied }

private func accessState(_ status: EKAuthorizationStatus) -> AgendaAccess {
    switch status {
    case .notDetermined: .unknown
    case .fullAccess: .granted
    default: .denied
    }
}

private func hex(_ color: CGColor?) -> UInt32 {
    guard let color, let c = NSColor(cgColor: color)?.usingColorSpace(.sRGB) else { return 0x888888 }
    return UInt32(c.redComponent * 255) << 16 | UInt32(c.greenComponent * 255) << 8 | UInt32(c.blueComponent * 255)
}

/// Declined and cancelled events never show. An event with no attendees is never declined.
private func shown(_ event: EKEvent) -> Bool {
    event.status != .canceled && event.attendees?.first(where: \.isCurrentUser)?.participantStatus != .declined
}

private func agendaEvent(_ e: EKEvent) -> AgendaEvent {
    AgendaEvent(id: e.eventIdentifier ?? "", title: e.title ?? "", start: e.startDate, end: e.endDate, allDay: e.isAllDay,
                calendarID: e.calendar.calendarIdentifier, color: hex(e.calendar.cgColor),
                calendarType: e.calendar.type == .birthday ? .birthday : e.calendar.allowsContentModifications ? .other : .readonly,
                joinURL: JoinLink.find(in: [e.url?.absoluteString, e.location, e.notes]))
}

// The two EventKit callbacks below run on an arbitrary queue, so they are free functions (not main actor closures).
private func requestAccess(_ store: EKEventStore, reminders: Bool, done: @escaping @Sendable () -> Void) {
    if reminders { store.requestFullAccessToReminders { _, _ in done() } } else { store.requestFullAccessToEvents { _, _ in done() } }
}

private func fetchDueReminders(_ store: EKEventStore, done: @escaping @Sendable ([ReminderItem]) -> Void) {
    let predicate = store.predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil, calendars: nil)
    store.fetchReminders(matching: predicate) { found in
        done((found ?? []).compactMap { r in
            guard let parts = r.dueDateComponents, let due = Calendar.current.date(from: parts) else { return nil } // a reminder with no day is not "due"
            return ReminderItem(id: r.calendarItemIdentifier, title: r.title ?? "", due: due, hasTime: parts.hour != nil,
                                list: r.calendar.title, color: hex(r.calendar.cgColor))
        })
    }
}

/// The Mac's calendar events and reminders, read only through EventKit and held in memory only. One model
/// serves the Notch on every display and Settings. Nothing here saves, edits or deletes an event or a reminder.
///
/// It never asks for permission by itself: `allowCalendar` and `allowReminders` are called from the Allow buttons.
@MainActor @Observable
final class AgendaModel {
    private(set) var eventsAccess: AgendaAccess
    private(set) var remindersAccess: AgendaAccess
    /// Every event read for the months that have been shown, calendars switched off included (see `Agenda.visible`).
    private(set) var events: [AgendaEvent] = []
    private(set) var calendars: [AgendaCalendar] = []
    private(set) var reminders: [ReminderItem] = []
    private(set) var hidden: Set<String>
    private(set) var showCalendar: Bool

    private let eventStore = EKEventStore()
    // ponytail: the shown months only ever grow (a few KB each); trim them if someone browses for years.
    @ObservationIgnored private var months: Set<Date> = []
    @ObservationIgnored private var reloadPending = false

    init(store: CatNotchStore) {
        eventsAccess = accessState(EKEventStore.authorizationStatus(for: .event))
        remindersAccess = accessState(EKEventStore.authorizationStatus(for: .reminder))
        hidden = store.data.hiddenCalendarIDs
        showCalendar = store.data.showCalendar
        // Both live as long as the app.
        _ = store.observe { [weak self] next in MainActor.assumeIsolated {
            self?.hidden = next.hiddenCalendarIDs
            self?.showCalendar = next.showCalendar
        } }
        let center = NotificationCenter.default
        for name in [Notification.Name.EKEventStoreChanged, .NSCalendarDayChanged, NSApplication.didBecomeActiveNotification] {
            center.addObserver(forName: name, object: name == .EKEventStoreChanged ? eventStore : nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.scheduleReload() }
            }
        }
        showMonth(Date())
    }

    // MARK: access

    /// Looks again, since the permission may have been changed in System Settings. Never prompts.
    func refreshAccess() {
        eventsAccess = accessState(EKEventStore.authorizationStatus(for: .event))
        remindersAccess = accessState(EKEventStore.authorizationStatus(for: .reminder))
        reload()
    }

    /// Only the Allow buttons call these: they are what makes macOS ask.
    func allowCalendar() { allow(reminders: false) }
    func allowReminders() { allow(reminders: true) }

    private func allow(reminders: Bool) {
        NSApp.activate() // a background app has no window to anchor the system prompt, so come forward for it
        requestAccess(eventStore, reminders: reminders) { [weak self] in Task { @MainActor in self?.refreshAccess() } }
    }

    // MARK: reading

    /// Makes sure `month` (any date in it) is read. The views call this as the shown month changes.
    func showMonth(_ month: Date) {
        let first = Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: month))!
        if months.insert(first).inserted { reload() }
    }

    private func scheduleReload() {
        guard !reloadPending else { return }
        reloadPending = true // a sync fires several changes at once; read once after they settle
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            MainActor.assumeIsolated { self?.reloadPending = false; self?.refreshAccess() }
        }
    }

    private func reload() {
        let now = Date()
        months.insert(Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: now))!)
        if eventsAccess == .granted {
            var seen = Set<String>()
            events = months.flatMap { month in
                let w = Agenda.window(month: month, now: now)
                return eventStore.events(matching: eventStore.predicateForEvents(withStart: w.start, end: w.end, calendars: nil)).filter(shown).map(agendaEvent)
            }.filter { seen.insert($0.key).inserted }
            calendars = eventStore.calendars(for: .event).map {
                AgendaCalendar(id: $0.calendarIdentifier, title: $0.title, account: $0.source?.title ?? "", color: hex($0.cgColor))
            }
        } else {
            events = []
            calendars = []
        }
        if remindersAccess == .granted {
            fetchDueReminders(eventStore) { [weak self] items in Task { @MainActor in self?.reminders = items } }
        } else {
            reminders = []
        }
    }

    // MARK: opening

    /// Opens the event in Calendar, or Calendar itself when it has no id.
    func open(_ event: AgendaEvent) {
        let id = event.id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? ""
        if !id.isEmpty, let url = URL(string: "ical://ekevent/\(id)?method=show&options=more"), NSWorkspace.shared.open(url) { return }
        NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: "/System/Applications/Calendar.app"), configuration: .init())
    }

    /// Opens the reminder in Reminders, or Reminders itself when the link finds nothing.
    func openReminder(_ item: ReminderItem) {
        if let url = URL(string: "x-apple-reminderkit://REMCDReminder/\(item.id)"), NSWorkspace.shared.open(url) { return }
        NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: "/System/Applications/Reminders.app"), configuration: .init())
    }

    /// Opens the event's call link in the browser. The link is checked again here, whatever put it on the event.
    func join(_ event: AgendaEvent) {
        if let url = event.joinURL, JoinLink.isAllowed(url) { NSWorkspace.shared.open(url) }
    }

    func openPrivacy(reminders: Bool) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_\(reminders ? "Reminders" : "Calendars")") {
            NSWorkspace.shared.open(url)
        }
    }
}
