# 0023. Native calendar and reminders

**Date**: 2026-11-05
**Status**: Accepted

## Summary

Issue #24 (native rewrite, ADR 0001). The Mac's calendar and Apple Reminders through EventKit, with no helper: a Calendar view (month grid, Today and Tomorrow, day details with tasks, special days), a Reminders view, a next event card on Home, and live updates. It ports specs 0003, 0008 and 0009 and keeps their rules. It only reads: no call that saves, edits or removes an event or a reminder.

## Requirements

- **AC-1** Nothing asks for permission by itself. The Calendar and Reminders views each show an explainer and an Allow button; only that button makes macOS ask. Denied (or restricted, or "add only") reads "access is off" with an Open System Settings button, and the view re-checks each time the Notch opens.
- **AC-2** With access, Today and Tomorrow list what is still to come (all day first, then by start), each with the calendar's colour, the title, "start to end" or "All day", "Now" while on, and Join for an allowed Zoom, Meet or Teams `https` link. Declined and cancelled events never show. Clicking a row opens it in Calendar.
- **AC-3** Clicking a day in the month grid shows its day pane: heading, a count line ("1 special day, 3 events, 2 tasks"), special days, events (ended ones greyed), and the tasks due that day (undated tasks on today only). A task added there gets that day. A day shows a dot for a visible event or an open task due that day.
- **AC-4** Birthdays (the Birthdays calendar) and holidays (all day items of a calendar you cannot edit) get an icon and no time, list first under "Special days", and never show on the Home card.
- **AC-5** A change in the Calendar app or Reminders shows within a second or so with no restart. Ended events and the Now mark follow the clock each minute with no new read.
- **AC-6** Settings can hide the Calendar view and switch single calendars off (`showCalendar`, `hiddenCalendarIds`, the Electron keys, so the import carries them). Hidden calendars give no events, counts or dots.
- **AC-7** The Reminders view lists incomplete reminders that have a due day, under Overdue, Today and Later, soonest first. Clicking one opens it in Reminders.
- **AC-8** Home shows the next timed event today ("NEXT · IN 25 MIN", title, time, Join), "now" while one is on, and nothing when none is left or access is not granted.
- **AC-9** Events and reminders are held in memory only, never logged or written.

## Design

- `CatNotchCore/Agenda.swift`: `AgendaEvent` (kind from the calendar type and all day flag), `JoinLink` (the allowlist: `zoom.us`, `*.zoom.us`, `meet.google.com`, `teams.microsoft.com`, `teams.live.com`), `Agenda` (visible, overlap, ordering, upcoming, next today, until, count line, month cells, query window), `StoreData` extras (`dayTasks`, `hasOpenTask`, `hiddenCalendarIDs`, `showCalendar`), `Reminders.grouped`. `addTask` gains an optional `due`.
- `CatNotch/AgendaModel.swift`: an `@Observable` model shared by every display and Settings. One `EKEventStore`; it reads each month that has been shown plus today and tomorrow, and reads again (coalesced over 0.5 s) on `EKEventStoreChanged`, a new day, and the app becoming active (a permission changed in System Settings).
- `CatNotch/CalendarViews.swift`: `CalendarPage`, `RemindersPage`, `NextEventCard`. `NotchPage` gains `calendar` and `reminders`.
- The Xcode project sets the four usage description keys (`NSCalendarsUsageDescription`, `NSCalendarsFullAccessUsageDescription`, `NSRemindersUsageDescription`, `NSRemindersFullAccessUsageDescription`). The app is unsandboxed, so no entitlement is needed.

## Out of scope

Ticking or adding Apple Reminders (read only, as with events). Reminders due on a day in the day pane. The Electron timed reminder that rings the companion (it belongs to the companion, issue #30). Drawing and the permission prompts are platform behaviour, checked by hand.
