# 0031. Native keyboard navigation

**Date**: 2026-11-08
**Status**: Accepted

## Summary

Issue #35 (native rewrite, ADR 0001), the first slice: open the Notch, switch sections and move through the calendar from the keyboard. Tasks and timer keys, Allow/Deny on Claude requests and a rebindable shortcut stay on #35 for later specs.

## Requirements

- **AC-1** Cmd+Option+. opens the Notch on the display the pointer is on and gives it the keyboard; pressed again it closes. It stays open with the pointer away until it is closed or the panel loses the keyboard (a click in another app).
- **AC-2** Esc closes the Notch, even with the pointer on it. It stays closed until the pointer has left it, so it does not spring back open.
- **AC-3** Left and Right switch to the previous and next section shown in the dock, and stop at the ends, on every page including Calendar while no day is chosen. Once a day is chosen on Calendar the arrows belong to the calendar (AC-4); Option+Left and Option+Right still switch sections.
- **AC-4** On Calendar, Down chooses today when no day is chosen (a click on a day chooses it too). With a day chosen, Left and Right move it by one and Up and Down by a week, and the month follows. Leaving Calendar clears the chosen day, so landing there again leaves the arrows on sections.
- **AC-5** While a text field is being typed in (task or Claude boxes), the Notch takes only Esc. Arrows move the caret.
- **AC-6** Hovering alone never takes the keyboard (specs 0005 AC-10, 0007 AC-8). Only the shortcut or a click does, and it does not activate the app, so the app the user was in stays frontmost.
- **AC-8** A Notch open by hover alone (not key) still answers Left and Right: the controller holds Left, Right and Esc as plain hot keys for exactly as long as such a Notch is open, and lets go when it closes or takes the keyboard. This does mean those keys do not reach the app in front while the pointer rests on the open Notch. Esc closes it as in AC-2. Up and Down need the shortcut or a click.
- **AC-7** The shortcut is fixed in code. If another app owns it, the app logs a warning and runs on.

## Design

- `CatNotchCore/NotchKeys.swift`: `NotchKey`, `NotchKeys.action(for:option:page:)` (what a key means on a page), `NotchKeys.page(from:step:among:)` and `NotchKeys.day(from:key:now:)`. Pure, tested.
- `GlobalShortcut` takes the key and an id so there can be two Carbon hot keys (Settings and the Notch).
- `NotchController` owns one local `keyDown` monitor and the shortcut; it routes to the panel that is key (or, for the shortcut, the one under the pointer). `NotchPanel` gains `toggleFromKeyboard()`, `dismiss()` and `handle(key:)`; `pinned` keeps it open, `suppressed` keeps it closed after Esc until the pointer leaves.
- `NotchModel.calendarDay` lifts the chosen day out of `CalendarPage` so a key can move it.

## Out of scope

Tasks and timer keys, Allow/Deny keys, Enter to act, rebinding, a VoiceOver audit. Focus hand-back, the hot key and key delivery are platform behaviour, checked by hand.
